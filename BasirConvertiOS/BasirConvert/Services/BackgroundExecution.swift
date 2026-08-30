import UIKit
import BackgroundTasks

@MainActor
final class BackgroundExecution {
    static let shared = BackgroundExecution()
    static let processingIdentifier = "com.basir.convert.ios.processing"
    static let refreshIdentifier = "com.basir.convert.ios.refresh"

    private var identifier: UIBackgroundTaskIdentifier = .invalid
    var processingHandler: (@MainActor () async -> Void)?
    private var processingTask: Task<Void, Never>?

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
            Task { @MainActor in
                await self?.processingHandler?()
                refresh.setTaskCompleted(success: true)
            }
        }
    }

    func schedule(earliest: Date = Date(timeIntervalSinceNow: 60)) {
        let request = BGProcessingTaskRequest(identifier: Self.processingIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = earliest
        try? BGTaskScheduler.shared.submit(request)
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
        processingTask = Task { [weak self] in
            await self?.processingHandler?()
            guard !Task.isCancelled else {
                task.setTaskCompleted(success: false)
                return
            }
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { [weak self] in
            Task { @MainActor in self?.processingTask?.cancel() }
        }
    }
}

