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

    /// Whether the app still has this task in flight. The app is the one
    /// that knows a task was finished, cancelled or deleted; a follow-up
    /// entry it no longer recognises is stale and must never speak again.
    /// Unset (iOS woke Basir before any screen exists): treated as active.
    @MainActor var isStillActive: (@MainActor (Entry) -> Bool)?

    /// Entries the app no longer recognises (tested).
    static func stale(_ entries: [Entry], isActive: (Entry) -> Bool) -> [Entry] {
        entries.filter { !$0.finished && !isActive($0) }
    }

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
        let entry = Entry(id: id, serverJobID: serverJobID, work: work, title: title, arabic: arabic,
                          percent: 0, uploading: work == .conversion, startedAt: Date(), finished: false,
                          appJobID: appJobID)
        var existing: Entry?
        mutate { entries in
            if let found = entries.first(where: { $0.id == id }), found.serverJobID == serverJobID, !found.finished {
                existing = found
                return
            }
            entries.removeAll { $0.id == id }
            entries.append(entry)
        }
        if let existing {
            arm(existing)
            return
        }
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
        var removed = false
        mutate { entries in
            removed = entries.contains(where: { $0.id == id })
            entries.removeAll { $0.id == id }
        }
        if removed { cancelTasks(for: id, then: nil) }
    }

    /// Drops every entry the app no longer recognises, with its requests and
    /// its notification. Called whenever Basir comes to or leaves the screen,
    /// so a finished or deleted task cannot keep announcing itself.
    @MainActor
    func prune() {
        guard let isStillActive else { return }
        let stale = load().filter { !$0.finished && !isStillActive($0) }
        for entry in stale {
            DiagnosticLogger.recordGlobal("WATCH prune id=\(entry.id) percent=\(entry.percent)")
            stop(id: entry.id)
            JobNotifier.remove(entry.id)
        }
    }

    var entries: [Entry] { load() }

    /// Basir is leaving the screen: write down the latest progress and tell
    /// the person, once, what really happens next.
    @MainActor
    func appWillLeave() {
        prune()
        lock.lock()
        let seen = memoryPercents
        lock.unlock()
        let entries = mutate { entries in
            for index in entries.indices {
                if let latest = seen[entries[index].id] {
                    entries[index].percent = max(entries[index].percent, latest.percent)
                    entries[index].uploading = latest.uploading
                }
            }
        }
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
        var expired: [Entry] = []
        let entries = mutate { entries in
            expired = entries.filter { now.timeIntervalSince($0.startedAt) > Self.lifetime || $0.finished }
            entries.removeAll { expired.contains($0) }
        }
        expired.forEach { cancelTasks(for: $0.id, then: nil) }
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
        let decision = Self.decide(entry: load().first(where: { $0.id == id }), httpStatus: httpStatus,
                                   answer: answer, cancelled: cancelled, now: Date())
        if decision != .ignore {
            DiagnosticLogger.recordGlobal("WATCH wake id=\(id) mode=\(mode.rawValue) http=\(httpStatus) decision=\(decision)")
        }
        // Every change is applied to the entry as it is *now*: if the app
        // stopped following the task meanwhile, there is nothing to update,
        // and the task must not come back to life.
        func update(_ change: (inout Entry) -> Void) -> Entry? {
            var updated: Entry?
            mutate { entries in
                guard let index = entries.firstIndex(where: { $0.id == id }), !entries[index].finished else { return }
                change(&entries[index])
                updated = entries[index]
            }
            return updated
        }
        switch decision {
        case .ignore:
            return
        case .forget:
            stop(id: id)
            Task { @MainActor in JobNotifier.remove(id) }
        case .retryLater:
            // No signal or a passing server error: ask again shortly. iOS
            // starts it when the connection is back.
            guard let entry = update({ _ in }) else { return }
            schedule(entry, mode: mode, delay: 30)
        case .askAgain(let percent):
            guard let entry = update({ $0.percent = percent }) else { return }
            if mode == .done || percent < 75 { schedule(entry, mode: mode) }
        case .progressed(let percent):
            guard let entry = update({ $0.percent = percent; $0.uploading = false }) else { return }
            if percent < 75 { schedule(entry, mode: .step) }
            Task { @MainActor in
                guard UIApplication.shared.applicationState != .active,
                      self.isStillActive?(entry) ?? true else { return }
                JobNotifier.show(JobNotifier.progress(task: entry.work, title: entry.title, percent: percent,
                                                      at: Date(), arabic: entry.arabic),
                                 id: entry.id, openJob: entry.appJobID)
                JobLiveActivityController.serverUpdate(title: entry.title, percent: percent, finished: false,
                                                       succeeded: false, arabic: entry.arabic,
                                                       startedAt: entry.startedAt)
            }
        case .finished(let status, let percent, let reason):
            guard let entry = update({ $0.percent = percent; $0.finished = true }) else { return }
            cancelTasks(for: id, then: nil)
            Task { @MainActor in self.finished(entry, status: status, reason: reason) }
        }
    }

    @MainActor
    private func finished(_ entry: Entry, status: String, reason: String?) {
        let succeeded = status == "completed" || status == "partial"
        if !(isStillActive?(entry) ?? true) {
            // Already finished, cancelled or deleted in the app: nothing to say.
            JobNotifier.remove(entry.id)
            stop(id: entry.id)
            return
        }
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
        return unlockedLoad()
    }

    /// Reads, changes and writes the list under one lock. A separate load
    /// and save let a background wake-up write back an entry the app had
    /// just removed — which is how a finished task kept announcing itself.
    @discardableResult
    private func mutate(_ change: (inout [Entry]) -> Void) -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        var entries = unlockedLoad()
        change(&entries)
        UserDefaults.standard.set(try? JSONEncoder().encode(entries), forKey: Self.storeKey)
        return entries
    }

    private func unlockedLoad() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: Self.storeKey) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
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
