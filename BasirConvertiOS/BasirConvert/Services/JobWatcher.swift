import Foundation
import UIKit

/// Follows tasks on the server while iOS has Basir suspended, without push.
///
/// iOS stops an app a few minutes after the person leaves it, so the app
/// itself cannot keep checking. Instead, as soon as the server has a task,
/// Basir hands iOS's background transfer service two requests to
/// GET /api/jobs/{id}/wait: one that the server answers when the task ends,
/// and one it answers at the next quarter of progress. iOS holds them open
/// while Basir sleeps, and wakes Basir only when one completes; Basir then
/// updates the task's one notification (and the Lock Screen activity) and
/// asks again. This works on any install, with or without push.
final class JobWatcher: NSObject, @unchecked Sendable {
    static let shared = JobWatcher()
    static let sessionIdentifier = "com.basir.convert.ios.watch"
    /// How long the server holds one request (it allows up to an hour).
    static let maximumWait = 3_300
    /// A task not finished after this long is no longer followed.
    static let lifetime: TimeInterval = 24 * 60 * 60
    private static let storeKey = "basir_job_watch"

    enum Mode: String, Sendable {
        case done
        case step
    }

    struct Entry: Codable, Equatable, Sendable {
        var id: String
        var serverJobID: String
        var work: JobNotifier.Work
        var title: String
        var arabic: Bool
        var percent: Int
        var uploading: Bool
        var startedAt: Date
        var finished: Bool
        /// The conversion's task in the app, opened when the notification is tapped.
        var appJobID: UUID?
    }

    struct Answer: Decodable, Equatable, Sendable {
        let outcome: String
        let status: String?
        let percent: Int?
        let error: String?
    }

    /// What a wake-up means, decided without side effects (tested).
    enum Decision: Equatable {
        case finished(status: String, percent: Int, error: String?)
        case progressed(percent: Int)
        case askAgain(percent: Int)
        case retryLater
        case forget
        case ignore
    }

    static func decide(entry: Entry?, httpStatus: Int, answer: Answer?, cancelled: Bool, now: Date) -> Decision {
        guard !cancelled, let entry, !entry.finished else { return .ignore }
        if now.timeIntervalSince(entry.startedAt) > lifetime { return .forget }
        if httpStatus == 404 || answer?.outcome == "missing" { return .forget }
        guard httpStatus == 200, let answer else { return .retryLater }
        let percent = max(entry.percent, min(100, answer.percent ?? entry.percent))
        switch answer.outcome {
        case "finished":
            return .finished(status: answer.status ?? "completed", percent: percent, error: answer.error)
        case "progress":
            return percent > entry.percent ? .progressed(percent: percent) : .askAgain(percent: percent)
        default:
            return .askAgain(percent: percent)
        }
    }

    /// Main-actor reactions, set by the app (notifications, Lock Screen, saving).
    @MainActor var onFinished: ((Entry, String, String?) -> Void)?

    private let lock = NSLock()
    private var answers: [Int: Data] = [:]
    private var backgroundCompletion: (() -> Void)?
    private var memoryPercents: [String: (percent: Int, uploading: Bool)] = [:]

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        // The server sends a byte every few seconds, so only a dead
        // connection reaches this.
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = TimeInterval(Self.maximumWait + 600)
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    // MARK: Following a task

    /// Starts following a server task. Called the moment the server has it,
    /// while Basir is open, so iOS treats the requests as urgent.
    func watch(id: String, serverJobID: String, work: JobNotifier.Work, title: String, arabic: Bool,
               appJobID: UUID? = nil) {
        var entries = load()
        if let existing = entries.first(where: { $0.id == id }), existing.serverJobID == serverJobID,
           !existing.finished {
            arm(existing)
            return
        }
        entries.removeAll { $0.id == id }
        let entry = Entry(id: id, serverJobID: serverJobID, work: work, title: title, arabic: arabic,
                          percent: 0, uploading: work == .conversion, startedAt: Date(), finished: false,
                          appJobID: appJobID)
        entries.append(entry)
        save(entries)
        JobNotifier.reset(id)
        cancelTasks(for: id) { [weak self] in self?.arm(entry) }
        DiagnosticLogger.recordGlobal("WATCH start id=\(id) work=\(work.rawValue)")
    }

    /// The app saw progress itself (cheap; kept in memory until Basir leaves).
    func noteProgress(id: String, percent: Int, uploading: Bool) {
        lock.lock()
        memoryPercents[id] = (percent, uploading)
        lock.unlock()
    }

    /// The app finished the task itself (saved, failed or cancelled).
    func stop(id: String) {
        var entries = load()
        guard entries.contains(where: { $0.id == id }) else { return }
        entries.removeAll { $0.id == id }
        save(entries)
        cancelTasks(for: id, then: nil)
    }

    var entries: [Entry] { load() }

    /// Basir is leaving the screen: write down the latest progress and tell
    /// the person, once, what really happens next.
    @MainActor
    func appWillLeave() {
        var entries = load()
        lock.lock()
        let seen = memoryPercents
        lock.unlock()
        for index in entries.indices {
            if let latest = seen[entries[index].id] {
                entries[index].percent = max(entries[index].percent, latest.percent)
                entries[index].uploading = latest.uploading
            }
        }
        save(entries)
        for entry in entries where !entry.finished {
            JobNotifier.show(JobNotifier.working(task: entry.work, title: entry.title, percent: entry.percent,
                                                 uploading: entry.uploading, arabic: entry.arabic),
                             id: entry.id, openJob: entry.appJobID)
        }
        resume()
    }

    /// On launch and on return: re-arm anything iOS dropped, forget old tasks.
    func resume() {
        let now = Date()
        var entries = load()
        let expired = entries.filter { now.timeIntervalSince($0.startedAt) > Self.lifetime || $0.finished }
        if !expired.isEmpty {
            entries.removeAll { expired.contains($0) }
            save(entries)
            expired.forEach { cancelTasks(for: $0.id, then: nil) }
        }
        entries.forEach(arm)
    }

    // MARK: Background session plumbing

    func reconnect(identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == Self.sessionIdentifier else { return }
        lock.lock()
        backgroundCompletion = completionHandler
        lock.unlock()
        _ = session
    }

    /// Makes sure both requests exist for the task.
    private func arm(_ entry: Entry) {
        guard !entry.finished else { return }
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            let modes = Set(tasks.compactMap { task -> Mode? in
                guard task.state == .running || task.state == .suspended,
                      let parsed = Self.parse(task.taskDescription), parsed.id == entry.id else { return nil }
                return parsed.mode
            })
            if !modes.contains(.done) { self.schedule(entry, mode: .done) }
            if !modes.contains(.step), entry.percent < 75 { self.schedule(entry, mode: .step) }
        }
    }

    private func schedule(_ entry: Entry, mode: Mode, delay: TimeInterval = 0) {
        let configuration = BundledServerConfiguration.current()
        guard let request = try? ProxyClient(configuration: configuration).waitRequest(
            serverJobID: entry.serverJobID, after: entry.percent, until: mode.rawValue,
            maxSeconds: Self.maximumWait) else { return }
        let task = session.downloadTask(with: request)
        task.taskDescription = "\(entry.id)|\(mode.rawValue)"
        task.countOfBytesClientExpectsToSend = 512
        task.countOfBytesClientExpectsToReceive = 8 * 1024
        if delay > 0 { task.earliestBeginDate = Date().addingTimeInterval(delay) }
        task.resume()
    }

    private func cancelTasks(for id: String, then: (() -> Void)?) {
        session.getAllTasks { tasks in
            tasks.filter { Self.parse($0.taskDescription)?.id == id }.forEach { $0.cancel() }
            then?()
        }
    }

    static func parse(_ description: String?) -> (id: String, mode: Mode)? {
        guard let description, let bar = description.lastIndex(of: "|"),
              let mode = Mode(rawValue: String(description[description.index(after: bar)...])) else { return nil }
        return (String(description[..<bar]), mode)
    }

    private func handle(id: String, mode: Mode, httpStatus: Int, data: Data?, error: Error?) {
        let cancelled = (error as? URLError)?.code == .cancelled
        let answer = data.flatMap { try? JSONDecoder().decode(Answer.self, from: $0) }
        var entries = load()
        let index = entries.firstIndex(where: { $0.id == id })
        let decision = Self.decide(entry: index.map { entries[$0] }, httpStatus: httpStatus, answer: answer,
                                   cancelled: cancelled, now: Date())
        if decision != .ignore {
            DiagnosticLogger.recordGlobal("WATCH wake id=\(id) mode=\(mode.rawValue) http=\(httpStatus) decision=\(decision)")
        }
        switch decision {
        case .ignore:
            return
        case .forget:
            stop(id: id)
        case .retryLater:
            // No signal or a passing server error: ask again shortly. iOS
            // starts it when the connection is back.
            guard let index else { return }
            schedule(entries[index], mode: mode, delay: 30)
        case .askAgain(let percent):
            guard let index else { return }
            entries[index].percent = percent
            save(entries)
            if mode == .done || percent < 75 { schedule(entries[index], mode: mode) }
        case .progressed(let percent):
            guard let index else { return }
            entries[index].percent = percent
            entries[index].uploading = false
            save(entries)
            let entry = entries[index]
            if percent < 75 { schedule(entry, mode: .step) }
            Task { @MainActor in
                guard UIApplication.shared.applicationState != .active else { return }
                JobNotifier.show(JobNotifier.progress(task: entry.work, title: entry.title, percent: percent,
                                                      at: Date(), arabic: entry.arabic),
                                 id: entry.id, openJob: entry.appJobID)
                JobLiveActivityController.serverUpdate(title: entry.title, percent: percent, finished: false,
                                                       succeeded: false, arabic: entry.arabic,
                                                       startedAt: entry.startedAt)
            }
        case .finished(let status, let percent, let reason):
            guard let index else { return }
            entries[index].percent = percent
            entries[index].finished = true
            save(entries)
            let entry = entries[index]
            cancelTasks(for: id, then: nil)
            Task { @MainActor in self.finished(entry, status: status, reason: reason) }
        }
    }

    @MainActor
    private func finished(_ entry: Entry, status: String, reason: String?) {
        let succeeded = status == "completed" || status == "partial"
        if status == "cancelled" {
            JobNotifier.remove(entry.id)
        } else if UIApplication.shared.applicationState != .active {
            // With Basir open, its own screen and completion notice say this.
            let message = succeeded
                ? JobNotifier.ready(task: entry.work, title: entry.title, arabic: entry.arabic)
                : JobNotifier.failed(title: entry.title, reason: reason, arabic: entry.arabic)
            JobNotifier.show(message, id: entry.id, openJob: entry.appJobID)
        }
        if UIApplication.shared.applicationState != .active {
            JobLiveActivityController.serverUpdate(title: entry.title, percent: succeeded ? 100 : entry.percent,
                                                   finished: true, succeeded: succeeded, arabic: entry.arabic,
                                                   startedAt: entry.startedAt)
        }
        onFinished?(entry, status, reason)
        stop(id: entry.id)
    }

    // MARK: Storage

    private func load() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        guard let data = UserDefaults.standard.data(forKey: Self.storeKey) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func save(_ entries: [Entry]) {
        lock.lock()
        defer { lock.unlock() }
        UserDefaults.standard.set(try? JSONEncoder().encode(entries), forKey: Self.storeKey)
    }
}

extension JobWatcher: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The file is gone when this returns: read it now.
        let data = try? Data(contentsOf: location)
        lock.lock()
        answers[downloadTask.taskIdentifier] = data
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let data = answers.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        guard let parsed = Self.parse(task.taskDescription) else { return }
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        handle(id: parsed.id, mode: parsed.mode, httpStatus: status, data: data, error: error)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        lock.lock()
        let completion = backgroundCompletion
        backgroundCompletion = nil
        lock.unlock()
        // Give the notification and activity updates a moment to be handed
        // to iOS before Basir is suspended again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { completion?() }
    }
}
