import Foundation

/// A result request is handed to iOS immediately after commit, while Basir is
/// still active. The server holds it until the Word file is ready. No app wake
/// or foreground polling is needed to START that transfer.
final class BackgroundResultInbox: NSObject, @unchecked Sendable {
    static let shared = BackgroundResultInbox()
    static let sessionIdentifier = "com.basir.convert.ios.results"
    private static let key = "basir_background_result_inbox_v1"

    struct Entry: Codable {
        let url: String
        let createdAt: Date
        let generation: String
        var file: String?
        var headers: [String: String]?
    }
    private let lock = NSLock()
    private var completion: (() -> Void)?
    private var waiters: [String: CheckedContinuation<(URL, HTTPURLResponse)?, Never>] = [:]
    private var progress: [String: @Sendable (Int64, Int64) -> Void] = [:]
    @MainActor var onReady: ((String) -> Void)?
    private var entries: [String: Entry] = {
        guard let data = UserDefaults.standard.data(forKey: BackgroundResultInbox.key) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 3600
        config.timeoutIntervalForResource = 24 * 60 * 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    static func transferKey(_ url: URL) -> String {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.query = nil; parts?.fragment = nil
        return parts?.url?.absoluteString ?? url.absoluteString
    }
    private static func directory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = base.appendingPathComponent("Ready Results", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: folder.path)
        return folder
    }
    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(entries), forKey: Self.key)
    }

    func arm(_ request: URLRequest) {
        guard let url = request.url else { return }
        let key = Self.transferKey(url)
        lock.lock()
        let exists = entries[key] != nil
        if !exists { entries[key] = Entry(url: key, createdAt: Date(), generation: UUID().uuidString); save() }
        lock.unlock()
        guard !exists else { return }
        schedule(request, key: key)
    }
    private func schedule(_ original: URLRequest, key: String, generation expected: String? = nil, delay: TimeInterval = 0) {
        lock.lock(); let entry = entries[key]; lock.unlock()
        guard let entry, expected == nil || expected == entry.generation else { return }
        var request = original
        guard var parts = URLComponents(url: original.url!, resolvingAgainstBaseURL: false) else { return }
        parts.queryItems = [URLQueryItem(name: "wait", value: "3300")]
        request.url = parts.url; request.timeoutInterval = 3600
        let task = session.downloadTask(with: request)
        task.taskDescription = entry.generation
        if delay > 0 { task.earliestBeginDate = Date().addingTimeInterval(delay) }
        task.resume()
    }

    /// Reconnect, without cancelling transfers whose original app process died.
    func reconnect(completionHandler: (() -> Void)? = nil) {
        lock.lock(); completion = completionHandler ?? completion; lock.unlock()
        _ = session
    }
    func cancel(resultURL: URL) {
        let key = Self.transferKey(resultURL)
        lock.lock()
        let entry = entries.removeValue(forKey: key)
        let waiter = waiters.removeValue(forKey: key); progress.removeValue(forKey: key); save()
        lock.unlock()
        if let file = entry?.file, let folder = try? Self.directory() { try? FileManager.default.removeItem(at: folder.appendingPathComponent(file)) }
        waiter?.resume(returning: nil)
        session.getAllTasks { $0.filter { $0.taskDescription == entry?.generation }.forEach { $0.cancel() } }
    }

    /// A foreground consumer joins the EXISTING background transfer, rather
    /// than fetching the same large result again. Receipts survive relaunch.
    func take(for request: URLRequest, progress callback: @escaping @Sendable (Int64, Int64) -> Void) async -> (URL, HTTPURLResponse)? {
        guard let url = request.url else { return nil }
        let key = Self.transferKey(url)
        return await withTaskCancellationHandler(operation: {
          await withCheckedContinuation { continuation in
            lock.lock()
            guard !Task.isCancelled else { lock.unlock(); continuation.resume(returning: nil); return }
            guard let entry = entries[key] else { lock.unlock(); continuation.resume(returning: nil); return }
            if let receipt = receipt(entry) {
                lock.unlock()
                continuation.resume(returning: receipt); return
            }
            // The app queue has only one producer for this result.
            guard waiters[key] == nil else { lock.unlock(); continuation.resume(returning: nil); return }
            waiters[key] = continuation; progress[key] = callback
            lock.unlock()
            session.getAllTasks { [weak self] tasks in
                guard let self, !tasks.contains(where: { $0.taskDescription == entry.generation }) else { return }
                // Recover an interrupted request without persisting its token.
                self.schedule(request, key: key, generation: entry.generation)
            }
          }
        }, onCancel: { [weak self] in self?.detachWaiter(key) })
    }
    private func detachWaiter(_ key: String) {
        lock.lock()
        let waiter = waiters.removeValue(forKey: key); progress.removeValue(forKey: key)
        lock.unlock()
        waiter?.resume(returning: nil)
    }
    private func receipt(_ entry: Entry) -> (URL, HTTPURLResponse)? {
        guard let file = entry.file, file == URL(fileURLWithPath: file).lastPathComponent,
              let folder = try? Self.directory(), let url = URL(string: entry.url),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: entry.headers),
              FileManager.default.fileExists(atPath: folder.appendingPathComponent(file).path) else { return nil }
        return (folder.appendingPathComponent(file), response)
    }
}

extension BackgroundResultInbox: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let header = (downloadTask.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Basir-Result-Bytes")
        lock.lock(); let key = entries.first(where: { $0.value.generation == downloadTask.taskDescription })?.key
        let callback = key.flatMap { progress[$0] }; lock.unlock()
        callback?(totalBytesWritten, max(Int64(header ?? "") ?? totalBytesExpectedToWrite, totalBytesWritten))
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let token = downloadTask.taskDescription, let response = downloadTask.response as? HTTPURLResponse,
              response.statusCode == 200,
              response.value(forHTTPHeaderField: "X-Basir-Result-Ready") == "true" else { return }
        do {
            let folder = try Self.directory(), file = UUID().uuidString + ".docx"
            let destination = folder.appendingPathComponent(file)
            try FileManager.default.moveItem(at: location, to: destination)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
            var headers: [String: String] = [:]
            for (name, value) in response.allHeaderFields { headers[String(describing: name)] = String(describing: value) }
            lock.lock()
            guard let key = entries.first(where: { $0.value.generation == token })?.key,
                  var entry = entries[key] else { lock.unlock(); try? FileManager.default.removeItem(at: destination); return }
            entry.file = file; entry.headers = headers; entries[key] = entry; save()
            let waiter = waiters.removeValue(forKey: key); progress.removeValue(forKey: key)
            lock.unlock()
            waiter?.resume(returning: (destination, response))
            Task { @MainActor in self.onReady?(key) }
            DiagnosticLogger.recordGlobal("RESULT_INBOX saved background result")
        } catch { DiagnosticLogger.recordGlobal("RESULT_INBOX staging failed: \(error.localizedDescription)") }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        guard let key = entries.first(where: { $0.value.generation == task.taskDescription })?.key,
              let entry = entries[key], entry.file == nil else { lock.unlock(); return }
        let retry = Date().timeIntervalSince(entry.createdAt) < 24 * 60 * 60
            && (error != nil || [202, 429, 500, 502, 503, 504].contains((task.response as? HTTPURLResponse)?.statusCode ?? 0))
        if !retry { entries.removeValue(forKey: key); save() }
        let waiter = retry ? nil : waiters.removeValue(forKey: key)
        if !retry { progress.removeValue(forKey: key) }
        lock.unlock()
        waiter?.resume(returning: nil)
        if retry, let request = task.originalRequest { schedule(request, key: key, generation: entry.generation, delay: 15) }
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        lock.lock(); let handler = completion; completion = nil; lock.unlock()
        DispatchQueue.main.async { handler?() }
    }
}
