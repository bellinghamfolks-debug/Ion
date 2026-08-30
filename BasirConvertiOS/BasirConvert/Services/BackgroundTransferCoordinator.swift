import Foundation

final class BackgroundTransferCoordinator: NSObject, @unchecked Sendable {
    static let shared = BackgroundTransferCoordinator()
    static let sessionIdentifier = "com.basir.convert.ios.transfers"

    private struct State {
        var data = Data()
        var downloadedURL: URL?
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
        guard let url = result.0 else { throw BasirError.invalidResponse("Missing downloaded file.") }
        return (url, result.2)
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
        let retained = FileManager.default.temporaryDirectory
            .appendingPathComponent("BasirDownload-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: retained)
            lock.lock(); states[downloadTask.taskIdentifier]?.downloadedURL = retained; lock.unlock()
        } catch {
            downloadTask.cancel()
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
        if let error {
            state.continuation.resume(throwing: error)
            return
        }
        guard let response = task.response as? HTTPURLResponse else {
            state.continuation.resume(throwing: BasirError.invalidResponse("Missing HTTP response."))
            return
        }
        state.continuation.resume(returning: (state.downloadedURL, state.data, response))
    }
}

