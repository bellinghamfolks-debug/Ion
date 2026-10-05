import ActivityKit
import Foundation

/// Mirrors the running task on the Lock Screen and in the Dynamic Island.
/// It is driven from AppViewModel.persist(), so every state change (progress,
/// pause, completion, failure) reaches the activity without extra wiring.
@MainActor
final class JobLiveActivityController {
    private var trackedJobID: UUID?
    private var activity: Any?
    private var lastState: AnyHashable?
    private var lastUpdate = Date.distantPast
    private var cleanedUpStaleActivities = false

    func sync(jobs: [BasirJob], l10n: L10n) {
        guard #available(iOS 16.2, *) else { return }
        syncActivity(jobs: jobs, l10n: l10n)
    }

    @available(iOS 16.2, *)
    private func syncActivity(jobs: [BasirJob], l10n: L10n) {
        if !cleanedUpStaleActivities {
            cleanedUpStaleActivities = true
            // Activities left over from a previous launch can no longer be updated.
            for stale in Activity<BasirJobActivityAttributes>.activities {
                Task { await stale.end(nil, dismissalPolicy: .immediate) }
            }
        }

        let running = jobs.first(where: { $0.status == .running })
        if let tracked = trackedJobID, tracked != running?.id {
            let job = jobs.first(where: { $0.id == tracked })
            if let job, [.paused, .waitingForNetwork, .queued].contains(job.status) {
                push(state(for: job, l10n: l10n), force: true)
                if running == nil { return }
            }
            finish(job.map { state(for: $0, l10n: l10n) })
        }

        guard let running else { return }
        if trackedJobID != running.id {
            start(job: running, l10n: l10n)
        } else {
            push(state(for: running, l10n: l10n), force: false)
        }
    }

    @available(iOS 16.2, *)
    private func start(job: BasirJob, l10n: L10n) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = BasirJobActivityAttributes(
            fileName: job.sourceName,
            isArabic: l10n.isArabic,
            stepNames: JobStep.allCases.map { $0.title(l10n) }
        )
        let initial = state(for: job, l10n: l10n)
        let content = ActivityContent(state: initial, staleDate: nil)
        let started: Activity<BasirJobActivityAttributes>
        do {
            // A push token lets the server keep the activity current while
            // iOS has suspended the app.
            started = try Activity.request(attributes: attributes, content: content, pushType: .token)
        } catch {
            do {
                started = try Activity.request(attributes: attributes, content: content, pushType: nil)
            } catch {
                DiagnosticLogger.recordGlobal("LIVE_ACTIVITY start failed description=\(error.localizedDescription)")
                return
            }
        }
        activity = started
        trackedJobID = job.id
        lastState = initial
        lastUpdate = Date()
        let jobID = job.id
        Task { @MainActor in
            for await token in started.pushTokenUpdates {
                PushRegistrar.shared.liveActivityTokenChanged(clientJobID: jobID, token: token)
            }
        }
    }

    @available(iOS 16.2, *)
    private func push(_ newState: BasirJobActivityAttributes.ContentState, force: Bool) {
        guard let activity = activity as? Activity<BasirJobActivityAttributes> else { return }
        guard AnyHashable(newState) != lastState else { return }
        let previousStep = (lastState?.base as? BasirJobActivityAttributes.ContentState)?.stepIndex
        let stepChanged = previousStep != newState.stepIndex
        guard force || stepChanged || Date().timeIntervalSince(lastUpdate) >= 2 else { return }
        lastState = newState
        lastUpdate = Date()
        Task { await activity.update(ActivityContent(state: newState, staleDate: nil)) }
    }

    @available(iOS 16.2, *)
    private func finish(_ finalState: BasirJobActivityAttributes.ContentState?) {
        guard let activity = activity as? Activity<BasirJobActivityAttributes> else {
            trackedJobID = nil
            return
        }
        self.activity = nil
        trackedJobID = nil
        lastState = nil
        let content = finalState.map { ActivityContent(state: $0, staleDate: nil) }
        Task {
            await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(10 * 60)))
        }
    }

    @available(iOS 16.2, *)
    private func state(for job: BasirJob, l10n: L10n) -> BasirJobActivityAttributes.ContentState {
        let step = JobStep.current(for: job.progress)
        if job.isContinuingOnServer {
            // The server is still working (and updates this activity by push);
            // never show it as paused.
            let text = job.serverContinuationText(l10n)
            return .init(stepIndex: step?.rawValue ?? 5,
                         stepTitle: step?.activeTitle(l10n) ?? text,
                         statusText: text,
                         percent: JobStep.overallPercent(for: job.progress),
                         isPaused: false, isFinished: false, succeeded: false)
        }
        switch job.status {
        case .running:
            return .init(stepIndex: step?.rawValue ?? 5,
                         stepTitle: step?.activeTitle(l10n) ?? l10n.t("اكتملت", "Complete"),
                         statusText: JobStep.spokenStatus(for: job.progress, l10n: l10n),
                         percent: JobStep.overallPercent(for: job.progress),
                         isPaused: false, isFinished: false, succeeded: false)
        case .paused, .queued, .waitingForNetwork:
            let text = job.status == .waitingForNetwork
                ? l10n.t("بانتظار الشبكة", "Waiting for network")
                : l10n.t("متوقفة مؤقتًا", "Paused")
            return .init(stepIndex: step?.rawValue ?? 0, stepTitle: text, statusText: text,
                         percent: JobStep.overallPercent(for: job.progress),
                         isPaused: true, isFinished: false, succeeded: false)
        case .completed, .partial:
            let text = job.status == .completed
                ? l10n.t("ملف Word جاهز", "Word file ready")
                : l10n.t("نتيجة جزئية جاهزة", "Partial result ready")
            return .init(stepIndex: 5, stepTitle: text, statusText: text, percent: 100,
                         isPaused: false, isFinished: true, succeeded: true)
        case .failed, .cancelled, .idle:
            let text = job.status == .cancelled
                ? l10n.t("أُلغيت المهمة", "Task cancelled")
                : l10n.t("لم تكتمل المهمة", "Task did not complete")
            return .init(stepIndex: step?.rawValue ?? 0, stepTitle: text, statusText: text,
                         percent: JobStep.overallPercent(for: job.progress),
                         isPaused: false, isFinished: true, succeeded: false)
        }
    }
}
