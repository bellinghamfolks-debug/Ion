import Foundation
import Combine

struct SessionSnapshot: Codable {
    var hasCompletedOnboarding: Bool
    var displayName: String
    var selectedLevel: CEFRLevel
    var points: Int
    var streak: Int
    var lastStudyDate: Date?
    /// Added in 2.0; optional so older backups still decode.
    var streakFreezes: Int?
}

@MainActor
final class UserSession: ObservableObject {
    @Published var hasCompletedOnboarding = false
    @Published var displayName = ""
    @Published var selectedLevel: CEFRLevel = .a0
    @Published var points = 0
    @Published var streak = 0
    @Published private(set) var lastStudyDate: Date?
    @Published private(set) var streakFreezes = 0

    private let store: FileStore
    private let key = "session.json"
    private var loaded = false

    init(store: FileStore) { self.store = store }

    func load() async {
        guard !loaded else { return }
        loaded = true
        guard let snapshot: SessionSnapshot = try? await store.read(SessionSnapshot.self, from: key) else { return }
        apply(snapshot)
    }

    func completeOnboarding(name: String, level: CEFRLevel) async {
        displayName = name
        selectedLevel = level
        hasCompletedOnboarding = true
        await save()
        FeedbackSoundEngine.shared.play(.milestone)
    }

    func award(points newPoints: Int) async {
        let previousStreak = streak
        points += newPoints
        updateStreak(for: .now)
        await save()
        if previousStreak > 0, streak > previousStreak {
            FeedbackSoundEngine.shared.play(.streak)
        }
    }

    private func updateStreak(for date: Date) {
        let outcome = StreakCalculator.recordStudy(
            .init(streak: streak, freezes: streakFreezes, lastStudyDate: lastStudyDate),
            on: date
        )
        streak = outcome.state.streak
        streakFreezes = outcome.state.freezes
        lastStudyDate = outcome.state.lastStudyDate
        if outcome.freezesUsed > 0 {
            ToastCenter.shared.show(LfE("حمت حماية السلسلة سلسلتك (%@ يوم فائت).", "A streak freeze saved your streak (%@ missed day).", "\(outcome.freezesUsed)"), style: .info)
        }
        if outcome.freezeEarned {
            ToastCenter.shared.show(LE("ربحت حماية سلسلة: تحفظ سلسلتك إذا فاتك يوم.", "You earned a streak freeze: it saves your streak if you miss a day."), style: .success)
        }
    }

    /// The streak that will still count today (it resets visually only once
    /// it can no longer be saved by study plus freezes).
    var streakState: StreakCalculator.State {
        .init(streak: streak, freezes: streakFreezes, lastStudyDate: lastStudyDate)
    }

    func exportSnapshot() -> SessionSnapshot {
        SessionSnapshot(
            hasCompletedOnboarding: hasCompletedOnboarding,
            displayName: displayName,
            selectedLevel: selectedLevel,
            points: points,
            streak: streak,
            lastStudyDate: lastStudyDate,
            streakFreezes: streakFreezes
        )
    }

    func importSnapshot(_ snapshot: SessionSnapshot) async {
        apply(snapshot)
        await save()
    }

    private func apply(_ snapshot: SessionSnapshot) {
        hasCompletedOnboarding = snapshot.hasCompletedOnboarding
        displayName = String(snapshot.displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        selectedLevel = snapshot.selectedLevel
        points = max(0, snapshot.points)
        streak = max(0, snapshot.streak)
        lastStudyDate = snapshot.lastStudyDate
        streakFreezes = min(StreakCalculator.maximumFreezes, max(0, snapshot.streakFreezes ?? 0))
    }

    func save() async {
        try? await store.write(exportSnapshot(), to: key)
    }
}
