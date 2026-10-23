import Foundation
import UIKit

/// A long task that runs on Basir's server (a long summary, a text brought
/// back to a natural voice), kept on the phone from the moment it is asked
/// for until its result is saved: in the Tasks tab, in a file on disk (not
/// in memory), so neither leaving Basir nor iOS closing it loses it.
struct ServerTask: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case summary, restyle }
    enum State: String, Codable, Sendable { case sending, working, finished, failed, cancelled }

    /// The request key: the same request always maps to the same server job.
    var id: String
    var kind: Kind
    var title: String
    var notificationID: String
    var jobID: String?
    var state: State = .sending
    var detail: String = ""
    var done = 0
    var total = 0
    var error: String?
    var createdAt = Date()
    var updatedAt = Date()
    var language = "ar"
    var choice = "auto"
    /// A summary's home: "output:<file name in My Files>" or "key:<key>", and its options.
    var summaryHome: String?
    var summaryVariant: String?
    /// Times the server lost the job and it was sent again.
    var resent = 0

    var isActive: Bool { state == .sending || state == .working }
    var percent: Int { total > 0 ? min(100, done * 100 / total) : 0 }
}

/// The record on disk: the list, and each request's body next to it until it is no longer needed.
enum ServerTaskStore {
    static var directory: URL? {
        guard let root = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return nil }
        let folder = root.appendingPathComponent("ServerTasks", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static var ledgerURL: URL? { directory?.appendingPathComponent("ledger.json") }

    static func load() -> [ServerTask] {
        guard let url = ledgerURL, let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ServerTask].self, from: data)) ?? []
    }

    static func save(_ tasks: [ServerTask]) {
        guard let url = ledgerURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(tasks) {
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    static func bodyURL(_ id: String) -> URL? { directory?.appendingPathComponent("\(id).body") }

    static func saveBody(_ data: Data, for id: String) {
        guard let url = bodyURL(id) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func body(for id: String) -> Data? { bodyURL(id).flatMap { try? Data(contentsOf: $0) } }

    static func removeBody(for id: String) {
        if let url = bodyURL(id) { try? FileManager.default.removeItem(at: url) }
    }
}

/// Follows every server task to the end: on launch, whenever Basir comes
/// back, and while it is open. A task is sent again until the server has it
/// (also after iOS closed Basir during the upload), followed through every
/// dropped connection, and its result is fetched and saved even when the
/// screen that asked for it is long gone. Only the server saying the task
/// failed for good (after its own retries), or the person cancelling it,
/// ends it otherwise.
@MainActor
final class ServerTaskCenter: ObservableObject {
    static let shared = ServerTaskCenter()

    @Published private(set) var tasks: [ServerTask]
    private var running: [String: Task<Void, Never>] = [:]
    private var configuration: ServerConfiguration?
    private weak var l10n: L10n?
    /// Results fetched during this run, for a screen waiting on them.
    private var results: [String: Data] = [:]

    /// Finished tasks stay in the Tasks tab this long.
    static let historyDays = 7.0

    private init() {
        tasks = ServerTaskStore.load()
    }

    /// The tasks the Tasks tab shows: every unfinished one and the recent finished ones.
    var visible: [ServerTask] {
        let horizon = Date().addingTimeInterval(-Self.historyDays * 86_400)
        return tasks.filter { $0.isActive || $0.updatedAt > horizon }.sorted { $0.createdAt > $1.createdAt }
    }

    func task(_ id: String) -> ServerTask? { tasks.first { $0.id == id } }

    // MARK: Asking

    /// Records the task (and its body) first, then starts it.
    @discardableResult
    func submit(kind: ServerTask.Kind, id: String, notificationID: String, title: String, body: Data,
                language: String, choice: String, summaryHome: String? = nil, summaryVariant: String? = nil,
                jobID: String? = nil, configuration: ServerConfiguration, l10n: L10n) -> String {
        self.configuration = configuration
        self.l10n = l10n
        ServerTaskStore.saveBody(body, for: id)
        if var existing = self.task(id) {
            if !existing.isActive {
                existing.state = .sending
                existing.error = nil
                existing.detail = ""
                existing.updatedAt = Date()
                put(existing)
            }
        } else {
            put(ServerTask(id: id, kind: kind, title: title, notificationID: notificationID, jobID: jobID,
                           state: jobID == nil ? .sending : .working, language: language, choice: choice,
                           summaryHome: summaryHome, summaryVariant: summaryVariant))
        }
        follow(id)
        return id
    }

    /// On launch and every time Basir comes back: every unfinished task carries on.
    func resumeAll(configuration: ServerConfiguration, l10n: L10n) {
        self.configuration = configuration
        self.l10n = l10n
        adoptEarlierRestyle()
        guard configuration.isConfigured else { return }
        for task in tasks where task.isActive { follow(task.id) }
        prune()
    }

    func retry(_ id: String, configuration: ServerConfiguration, l10n: L10n) {
        guard var task = self.task(id), ServerTaskStore.body(for: id) != nil else { return }
        self.configuration = configuration
        self.l10n = l10n
        task.state = .sending
        task.error = nil
        task.detail = ""
        task.updatedAt = Date()
        put(task)
        follow(id)
    }

    func cancel(_ id: String, configuration: ServerConfiguration) {
        running[id]?.cancel()
        running[id] = nil
        guard var task = self.task(id) else { return }
        if task.jobID != nil {
            Task { _ = try? await ProxyClient(configuration: configuration).cancelServerTask(requestID: id) }
        }
        JobWatcher.shared.stop(id: task.notificationID)
        task.state = .cancelled
        task.updatedAt = Date()
        put(task)
        ServerTaskStore.removeBody(for: id)
    }

    /// Takes a task off the list (an ended one).
    func remove(_ id: String) {
        guard let task = self.task(id), !task.isActive else { return }
        tasks.removeAll { $0.id == id }
        ServerTaskStore.save(tasks)
        ServerTaskStore.removeBody(for: id)
    }

    /// For a screen that asked for the task: waits for its result, telling it the progress.
    func outcome(of id: String, progress: (ServerTask) -> Void) async throws -> Data {
        while true {
            try Task.checkCancellation()
            guard let task = self.task(id) else { throw CancellationError() }
            switch task.state {
            case .finished:
                if let data = results[id] { return data }
                throw BasirError.invalidResponse("")
            case .failed:
                throw BasirError.conversionFailed(task.error ?? "")
            case .cancelled:
                throw CancellationError()
            case .sending, .working:
                progress(task)
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    // MARK: Following

    private func follow(_ id: String) {
        guard running[id] == nil, let configuration, configuration.isConfigured else { return }
        running[id] = Task { [weak self] in
            await self?.work(id, configuration: configuration)
            self?.running[id] = nil
        }
    }

    private func work(_ id: String, configuration: ServerConfiguration) async {
        let client = ProxyClient(configuration: configuration)
        var wait: UInt64 = 5
        var watched = false
        while !Task.isCancelled, var task = self.task(id), task.isActive {
            do {
                if task.jobID == nil {
                    guard let body = ServerTaskStore.body(for: id) else {
                        fail(id, l10n?.t("لم يعد نص الطلب على الجهاز. ابدأ المهمة مرة أخرى.",
                                         "The request is no longer on the phone. Start the task again.") ?? "")
                        return
                    }
                    update(id) { $0.detail = self.text("جارٍ الإرسال", "Sending") }
                    let jobID = try await withBackgroundTime("Basir send") {
                        switch task.kind {
                        case .restyle:
                            return try await client.startRestyleJob(body: body, requestID: id, title: task.title,
                                                                    language: task.language, choice: task.choice)
                        case .summary:
                            return try await client.startSummaryJob(body: body, requestID: id, title: task.title,
                                                                    language: task.language, choice: task.choice)
                        }
                    }
                    update(id) {
                        $0.jobID = jobID
                        $0.state = .working
                        $0.detail = ""
                    }
                    wait = 5
                    continue
                }
                guard let jobID = task.jobID else { continue }
                if !watched {
                    watch(task, jobID: jobID, configuration: configuration)
                    watched = true
                }
                let progress = try await client.summaryJobProgress(jobID: jobID, requestID: id)
                wait = 5
                if progress.isFinished {
                    try await finish(id, jobID: jobID, client: client)
                    return
                }
                if progress.isFailed {
                    if progress.status == "cancelled" || progress.status == "canceled" {
                        update(id) { $0.state = .cancelled }
                        JobWatcher.shared.stop(id: task.notificationID)
                        return
                    }
                    fail(id, progress.error ?? "")
                    return
                }
                update(id) {
                    $0.done = progress.current
                    $0.total = progress.total
                    $0.detail = self.stage(kind: task.kind, done: progress.current, total: progress.total)
                }
                try await Task.sleep(nanoseconds: 4_000_000_000)
            } catch is CancellationError {
                return
            } catch BasirError.authenticationFailed {
                fail(id, text("رمز الخادم غير صالح.", "The server token is not valid."))
                return
            } catch {
                if Self.isMissing(error), task.jobID != nil {
                    // The server no longer has the job: send it again (the body is still here).
                    if task.resent >= 2 {
                        fail(id, text("فقد الخادم المهمة أكثر من مرة. ابدأها مرة أخرى.",
                                      "The server lost the task more than once. Start it again."))
                        return
                    }
                    update(id) {
                        $0.jobID = nil
                        $0.state = .sending
                        $0.resent += 1
                    }
                    watched = false
                    continue
                }
                // No connection, a passing server error, Basir in the background: keep at it.
                update(id) { $0.detail = self.text("بانتظار الاتصال، وسيستمر تلقائيًا", "Waiting for the connection; it will carry on by itself") }
                try? await Task.sleep(nanoseconds: wait * 1_000_000_000)
                wait = min(60, wait * 2)
            }
        }
    }

    private func finish(_ id: String, jobID: String, client: ProxyClient) async throws {
        guard let task = self.task(id) else { return }
        let data = try await withBackgroundTime("Basir result") {
            try await client.jobSummary(jobID: jobID, requestID: id)
        }
        switch task.kind {
        case .restyle:
            let result = try RestyleResult.decode(data)
            let word = try? await withBackgroundTime("Basir result file") { try await client.jobResult(jobID: jobID, requestID: id) }
            RestyleRunner.save(result, word: word, id: id, title: task.title, l10n: l10n)
        case .summary:
            let summary = try DocumentSummary.decode(data)
            if let home = task.summaryHome, let variant = task.summaryVariant {
                if home.hasPrefix("output:"), let folder = try? FileAccess.outputDirectory() {
                    SummaryStore.save(summary, variant: variant,
                                      forOutput: folder.appendingPathComponent(String(home.dropFirst("output:".count))))
                } else if home.hasPrefix("key:") {
                    SummaryStore.save(summary, variant: variant, key: String(home.dropFirst("key:".count)))
                }
            }
            SummaryStore.setPendingJob(nil, for: id)
        }
        results[id] = data
        update(id) {
            $0.state = .finished
            $0.done = max($0.done, $0.total)
            $0.detail = ""
        }
        if task.kind == .restyle { ServerTaskStore.removeBody(for: id) }
        // The result is on the phone; the server copy goes, as the privacy setting asks (on by default).
        let deleteCopy = UserDefaults.standard.object(forKey: "privacy_delete_server_copy") as? Bool ?? true
        if deleteCopy { try? await client.deleteServerTask(requestID: id) }
        JobWatcher.shared.stop(id: task.notificationID)
        let work: JobNotifier.Work = task.kind == .restyle ? .restyle : .summary
        if UIApplication.shared.applicationState != .active {
            let partial = task.kind == .restyle && (try? RestyleResult.decode(data))?.isPartial == true
            JobNotifier.show(JobNotifier.finished(task: work, title: task.title, partial: partial,
                                                  arabic: task.language != "en"), id: task.notificationID)
        } else {
            JobNotifier.remove(task.notificationID)
        }
    }

    private func fail(_ id: String, _ reason: String) {
        update(id) {
            $0.state = .failed
            $0.error = reason
        }
        guard let task = self.task(id) else { return }
        JobWatcher.shared.stop(id: task.notificationID)
        if UIApplication.shared.applicationState != .active {
            JobNotifier.show(JobNotifier.failed(title: task.title, reason: reason, arabic: task.language != "en"),
                             id: task.notificationID)
        }
    }

    private func watch(_ task: ServerTask, jobID: String, configuration: ServerConfiguration) {
        // Followed while iOS suspends Basir (and by push where available), under one identifier.
        JobWatcher.shared.watch(id: task.notificationID, serverJobID: jobID,
                                work: task.kind == .restyle ? .restyle : .summary, title: task.title,
                                arabic: task.language != "en")
        if let clientJobID = UUID(uuidString: task.notificationID) {
            PushRegistrar.shared.serverJobCreated(clientJobID: clientJobID, serverJobID: jobID,
                                                  configuration: configuration, language: task.language)
        }
    }

    // MARK: Helpers

    private func put(_ task: ServerTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) { tasks[index] = task } else { tasks.append(task) }
        ServerTaskStore.save(tasks)
    }

    private func update(_ id: String, _ change: (inout ServerTask) -> Void) {
        guard var task = self.task(id) else { return }
        change(&task)
        task.updatedAt = Date()
        put(task)
    }

    private func prune() {
        let horizon = Date().addingTimeInterval(-30 * 86_400)
        let old = tasks.filter { !$0.isActive && $0.updatedAt < horizon }
        guard !old.isEmpty else { return }
        old.forEach { ServerTaskStore.removeBody(for: $0.id) }
        tasks.removeAll { task in old.contains { $0.id == task.id } }
        ServerTaskStore.save(tasks)
    }

    /// A natural-style text started by build 38 is taken over.
    private func adoptEarlierRestyle() {
        guard let pending = RestyleStore.pending(), task(pending.requestKey) == nil else { return }
        ServerTaskStore.saveBody(pending.body, for: pending.requestKey)
        put(ServerTask(id: pending.requestKey, kind: .restyle, title: pending.title,
                       notificationID: pending.notificationID, jobID: pending.jobID,
                       state: pending.jobID == nil ? .sending : .working, choice: "accurate"))
        RestyleStore.setPending(nil)
    }

    private func text(_ arabic: String, _ english: String) -> String {
        l10n?.t(arabic, english) ?? arabic
    }

    func stage(kind: ServerTask.Kind, done: Int, total: Int) -> String {
        let percent = total > 0 ? min(100, done * 100 / total) : 0
        switch kind {
        case .restyle:
            let parts = max(1, (total - 1) / 2)
            if done <= 0 || total <= 1 { return text("يقرأ بصير النص كاملًا", "Basir is reading the whole text") }
            if done <= parts { return text("التحرير: \(percent)٪ (يكتب المسودة)", "Editing: \(percent)% (drafting)") }
            return text("التحرير: \(percent)٪ (يراجع المسودة على الأصل)", "Editing: \(percent)% (reviewing against the original)")
        case .summary:
            if total > 1 && done < total - 1 {
                return text("جارٍ قراءة المستند، الجزء \(done) من \(total - 1)", "Reading the document, part \(done) of \(total - 1)")
            }
            return text("جارٍ كتابة الملخص", "Writing the summary")
        }
    }

    static func isMissing(_ error: Error) -> Bool {
        if let error = error as? BasirError, case .conversionFailed(let reason) = error {
            return reason.hasPrefix("Server HTTP 404")
        }
        return false
    }
}

/// Short work (sending a request, fetching a result) finishes even when the
/// person leaves Basir; when iOS's grace time ends it is ended properly, so
/// iOS never has to close Basir for it. The task then carries on next time.
@MainActor
func withBackgroundTime<T>(_ name: String, _ work: () async throws -> T) async throws -> T {
    let time = BackgroundTime()
    time.identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [time] in
        Task { @MainActor in time.end() }
    }
    defer { time.end() }
    return try await work()
}

@MainActor
final class BackgroundTime {
    var identifier: UIBackgroundTaskIdentifier = .invalid

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
