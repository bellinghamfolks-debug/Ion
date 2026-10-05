import Foundation
import UIKit

final class BackgroundTransferCoordinator: NSObject, @unchecked Sendable {
    static let shared = BackgroundTransferCoordinator()
    static let sessionIdentifier = "com.basir.convert.ios.transfers"

    private struct DownloadStagingError: Error {
        let underlying: Error
    }

    private struct State {
        var data = Data()
        var downloadedURL: URL?
        var stagingError: Error?
        let continuation: CheckedContinuation<(URL?, Data, HTTPURLResponse), Error>
        let progress: @Sendable (Int64, Int64) -> Void
    }

    private let lock = NSLock()
    private var states: [Int: State] = [:]
    private var backgroundCompletionHandler: (() -> Void)?

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: Self.sessionIdentifier
        )
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    /// Result downloads normally use the background session so iOS can continue
    /// them while the app is suspended. If iOS itself cannot create the background
    /// session's temporary download file, retry once through an independent
    /// foreground session. The server result is already complete at this point, so
    /// this recovery never re-runs the conversion job.
    private lazy var foregroundSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    static func isLocalFileFailure(_ error: URLError) -> Bool {
        switch error.code {
        case .cannotCreateFile, .cannotOpenFile, .fileDoesNotExist, .noPermissionsToReadFile:
            return true
        default:
            return false
        }
    }

    func upload(
        request: URLRequest,
        fromFile fileURL: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> (Data, HTTPURLResponse) {
        let result: (URL?, Data, HTTPURLResponse) = try await withCheckedThrowingContinuation { continuation in
            let task = session.uploadTask(with: request, fromFile: fileURL)
            lock.lock()
            states[task.taskIdentifier] = State(
                continuation: continuation,
                progress: progress
            )
            lock.unlock()
            task.resume()
        }
        return (result.1, result.2)
    }

    func download(
        request: URLRequest,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> (URL, HTTPURLResponse) {
        // With Basir open, fetch the result directly: it starts at once and
        // runs at full speed. iOS schedules background-session transfers in a
        // separate process, which can leave a small file crawling for minutes.
        let isActive = await MainActor.run { UIApplication.shared.applicationState == .active }
        if isActive {
            do {
                return try await activeDownload(request: request, progress: progress)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Fall through: the background session survives suspension.
            }
        }
        do {
            return try await backgroundDownload(request: request, progress: progress)
        } catch let staging as DownloadStagingError {
            return try await foregroundDownload(
                request: request,
                progress: progress,
                firstFailure: staging.underlying
            )
        } catch let urlError as URLError where Self.isLocalFileFailure(urlError) {
            return try await foregroundDownload(
                request: request,
                progress: progress,
                firstFailure: urlError
            )
        }
    }

    /// Streams the result to a staging file, reporting real byte progress.
    private func activeDownload(
        request: URLRequest,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> (URL, HTTPURLResponse) {
        let (bytes, response) = try await foregroundSession.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BasirError.invalidResponse("Missing HTTP response.")
        }
        let partial = FileManager.default.temporaryDirectory
            .appendingPathComponent("BasirActiveDownload-\(UUID().uuidString).tmp")
        FileManager.default.createFile(atPath: partial.path, contents: nil)
        let handle = try FileHandle(forWritingTo: partial)
        var completed = false
        defer {
            try? handle.close()
            if !completed { try? FileManager.default.removeItem(at: partial) }
        }
        let expected = max(0, http.expectedContentLength)
        var received: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(256 * 1024)
        var lastReport = Date.distantPast
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 256 * 1024 {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if Date().timeIntervalSince(lastReport) > 0.2 {
                    lastReport = Date()
                    // Never report more than the expected size: a compressed
                    // transfer can decode to more bytes than its header said.
                    progress(received, max(expected, received))
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            received += Int64(buffer.count)
        }
        try handle.close()
        progress(received, received)
        let retained = try retainDownloadedFile(partial)
        completed = true
        return (retained, http)
    }

    /// Transfers left in the shared background session by an earlier launch
    /// have no one waiting for them; they only hold the session's connections
    /// and slow the next transfer. Cancel them once at launch.
    func cancelTransfersFromEarlierLaunch() async {
        let tasks = await session.allTasks
        lock.lock()
        let owned = Set(states.keys)
        lock.unlock()
        let orphans = tasks.filter { !owned.contains($0.taskIdentifier) }
        orphans.forEach { $0.cancel() }
        if !orphans.isEmpty {
            DiagnosticLogger.recordGlobal("TRANSFER cancelled \(orphans.count) orphaned background tasks")
        }
    }

    private func backgroundDownload(
        request: URLRequest,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> (URL, HTTPURLResponse) {
        let result: (URL?, Data, HTTPURLResponse) = try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: request)
            lock.lock()
            states[task.taskIdentifier] = State(
                continuation: continuation,
                progress: progress
            )
            lock.unlock()
            task.resume()
        }
        guard let url = result.0 else {
            throw BasirError.invalidResponse("Missing downloaded file.")
        }
        return (url, result.2)
    }

    private func foregroundDownload(
        request: URLRequest,
        progress: @escaping @Sendable (Int64, Int64) -> Void,
        firstFailure: Error
    ) async throws -> (URL, HTTPURLResponse) {
        do {
            let (location, response) = try await foregroundSession.download(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw BasirError.invalidResponse("Missing HTTP response for recovered result download.")
            }
            let retained = try retainDownloadedFile(location)
            let bytes = Int64(
                (try? retained.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            )
            progress(bytes, bytes)
            return (retained, http)
        } catch let urlError as URLError where Self.isLocalFileFailure(urlError) {
            throw BasirError.conversionFailed(
                "RESULT_LOCAL_FILE_WRITE_FAILED: background=\(firstFailure.localizedDescription); foreground=\(urlError.localizedDescription)"
            )
        } catch let staging as DownloadStagingError {
            throw BasirError.conversionFailed(
                "RESULT_LOCAL_FILE_WRITE_FAILED: background=\(firstFailure.localizedDescription); foreground=\(staging.underlying.localizedDescription)"
            )
        } catch {
            throw error
        }
    }

    private func retainDownloadedFile(_ location: URL) throws -> URL {
        let manager = FileManager.default
        let base: URL
        do {
            base = try manager.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            base = manager.temporaryDirectory
        }
        let directory = base.appendingPathComponent("Basir Transfers", isDirectory: true)
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            // Results may finish while the phone is locked. This protection class
            // keeps the app-owned staging directory available after first unlock.
            try? manager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: directory.path
            )
            let retained = directory.appendingPathComponent(
                "BasirDownload-\(UUID().uuidString).tmp"
            )
            do {
                try manager.moveItem(at: location, to: retained)
            } catch {
                // A move can fail when URLSession's temporary file lives in a
                // different file-system container. Copying is a safe recovery.
                do {
                    try manager.copyItem(at: location, to: retained)
                    try? manager.removeItem(at: location)
                } catch {
                    throw DownloadStagingError(underlying: error)
                }
            }
            try? manager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: retained.path
            )
            return retained
        } catch let staging as DownloadStagingError {
            throw staging
        } catch {
            throw DownloadStagingError(underlying: error)
        }
    }

    func reconnectBackgroundEvents(
        identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == Self.sessionIdentifier else {
            completionHandler()
            return
        }
        lock.lock()
        backgroundCompletionHandler = completionHandler
        lock.unlock()
        _ = session
    }
}

extension BackgroundTransferCoordinator: URLSessionDataDelegate, URLSessionDownloadDelegate {
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        lock.lock()
        let completion = backgroundCompletionHandler
        backgroundCompletionHandler = nil
        lock.unlock()
        DispatchQueue.main.async { completion?() }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        lock.lock()
        states[dataTask.taskIdentifier]?.data.append(data)
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        lock.lock()
        let callback = states[task.taskIdentifier]?.progress
        lock.unlock()
        callback?(totalBytesSent, totalBytesExpectedToSend)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        lock.lock()
        let callback = states[downloadTask.taskIdentifier]?.progress
        lock.unlock()
        callback?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let retained = try retainDownloadedFile(location)
            lock.lock()
            states[downloadTask.taskIdentifier]?.downloadedURL = retained
            lock.unlock()
        } catch {
            // Do not cancel the task and turn a file-system problem into a fake
            // transport cancellation. Preserve the exact staging failure so
            // download() can recover through the foreground session.
            lock.lock()
            states[downloadTask.taskIdentifier]?.stagingError = error
            lock.unlock()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        let state = states.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        guard let state else { return }
        if let stagingError = state.stagingError {
            state.continuation.resume(
                throwing: DownloadStagingError(underlying: stagingError)
            )
            return
        }
        if let error {
            state.continuation.resume(throwing: error)
            return
        }
        guard let response = task.response as? HTTPURLResponse else {
            state.continuation.resume(
                throwing: BasirError.invalidResponse("Missing HTTP response.")
            )
            return
        }
        state.continuation.resume(
            returning: (state.downloadedURL, state.data, response)
        )
    }
}
