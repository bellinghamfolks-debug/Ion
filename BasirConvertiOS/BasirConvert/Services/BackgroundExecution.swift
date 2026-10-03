import UIKit
import BackgroundTasks

@MainActor
final class BackgroundExecution {
    static let shared = BackgroundExecution()
    static let processingIdentifier = "com.basir.convert.ios.processing"
    static let refreshIdentifier = "com.basir.convert.ios.refresh"

    private var identifier: UIBackgroundTaskIdentifier = .invalid
    /// Resumes queued work and returns only when the queue is idle.
    var processingHandler: (@MainActor () async -> Void)?
    /// Called when iOS is about to take back background time, so the running
    /// job can be checkpointed and marked for automatic resume.
    var expirationHandler: (@MainActor () -> Void)?
    private var processingTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.processingIdentifier,
            using: nil
        ) { [weak self] task in
            guard let processing = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in self?.handle(processing) }
        }
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshIdentifier,
            using: nil
        ) { [weak self] task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in self?.handle(refresh) }
        }
    }

    /// Asks iOS for both kinds of background time. The app-refresh task is
    /// the one iOS grants regularly (a short window every so often); the
    /// processing task tends to run when the phone is idle or charging.
    func schedule(earliest: Date = Date(timeIntervalSinceNow: 60)) {
        let request = BGProcessingTaskRequest(identifier: Self.processingIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = earliest
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            DiagnosticLogger.recordGlobal("BACKGROUND processing schedule failed description=\(error.localizedDescription)")
        }
        scheduleRefresh(earliest: earliest)
    }

    func scheduleRefresh(earliest: Date = Date(timeIntervalSinceNow: 60)) {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshIdentifier)
        request.earliestBeginDate = earliest
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            DiagnosticLogger.recordGlobal("BACKGROUND refresh schedule failed description=\(error.localizedDescription)")
        }
    }

    func begin(expiration: @escaping @MainActor () -> Void) {
        end()
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Basir document conversion") { [weak self] in
            Task { @MainActor in
                expiration()
                self?.end()
            }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }

    private func handle(_ task: BGProcessingTask) {
        schedule(earliest: Date(timeIntervalSinceNow: 15 * 60))
        processingTask?.cancel()
        processingTask = run(task) { [weak self] in self?.processingTask = nil }
    }

    private func handle(_ task: BGAppRefreshTask) {
        // Keep asking: each refresh window is short, so long conversions are
        // followed across several wake-ups until they finish.
        scheduleRefresh(earliest: Date(timeIntervalSinceNow: 15 * 60))
        refreshTask?.cancel()
        refreshTask = run(task) { [weak self] in self?.refreshTask = nil }
    }

    private func run(_ task: BGTask, finished: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        var completed = false
        let complete: @MainActor (Bool) -> Void = { success in
            guard !completed else { return }
            completed = true
            task.setTaskCompleted(success: success)
            finished()
        }
        let work = Task { @MainActor [weak self] in
            await self?.processingHandler?()
            complete(!Task.isCancelled)
        }
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.expirationHandler?()
                work.cancel()
                complete(false)
            }
        }
        return work
    }
}

