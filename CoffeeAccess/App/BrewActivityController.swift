import ActivityKit
import Foundation

/// The Live Activity and Dynamic Island while a drink is made.
@MainActor
final class BrewActivityController {
    static let shared = BrewActivityController()
    private var activity: Activity<BrewActivityAttributes>?
    private var lastPercent = -1

    func start(recipe: Recipe, enabled: Bool) {
        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endNow()
        let attributes = BrewActivityAttributes(drinkName: recipe.displayName, isArabic: AppLanguage.current == .arabic)
        let state = BrewActivityAttributes.ContentState(phase: L("brew.preparing", recipe.displayName), percent: 0, finished: false, failed: false)
        activity = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil))
        lastPercent = 0
    }

    func update(_ session: BrewSession) {
        guard let activity, session.isRunning else { return }
        let percent = Int(session.progress * 100)
        // Updates are throttled by the system; send meaningful changes only.
        guard percent - lastPercent >= 5 || percent == 0 else { return }
        lastPercent = percent
        let phase = session.activity == .idle ? L("brew.preparing", session.recipe.displayName) : session.activity.title
        let state = BrewActivityAttributes.ContentState(phase: phase, percent: percent, finished: false, failed: false)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end(_ session: BrewSession) {
        guard let activity else { return }
        let finished = session.outcome == .finished
        let phase: String
        switch session.outcome {
        case .finished: phase = L("brew.finished", session.recipe.displayName)
        case .stopped: phase = L("brew.stopped")
        case .failed(let reason): phase = L("brew.failed", reason)
        case .running: phase = ""
        }
        let state = BrewActivityAttributes.ContentState(phase: phase, percent: finished ? 100 : lastPercent, finished: finished, failed: !finished)
        self.activity = nil
        Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(120))) }
    }

    private func endNow() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
