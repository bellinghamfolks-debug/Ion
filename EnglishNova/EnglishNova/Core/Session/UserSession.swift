import Foundation
import Combine

struct SessionSnapshot: Codable {
    var hasCompletedOnboarding: Bool
    var displayName: String
    var selectedLevel: CEFRLevel
    var points: Int
    var streak: Int
    var lastStudyDate: Date?
}

@MainActor
final class UserSession: ObservableObject {
    @Published var hasCompletedOnboarding = false
    @Published var displayName = ""
    @Published var selectedLevel: CEFRLevel = .a0
    @Published var points = 0
    @Published var streak = 0
    @Published private(set) var lastStudyDate: Date?

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
    }

    func award(points newPoints: Int) async {
        points += newPoints
        updateStreak(for: .now)
        await save()
    }

    private func updateStreak(for date: Date) {
        let calendar = Calendar.current
        if let lastStudyDate {
            if calendar.isDate(lastStudyDate, inSameDayAs: date) { return }
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: date),
               calendar.isDate(lastStudyDate, inSameDayAs: yesterday) {
                streak += 1
            } else {
                streak = 1
            }
        } else {
            streak = 1
        }
        lastStudyDate = date
    }

    func exportSnapshot() -> SessionSnapshot {
        SessionSnapshot(
            hasCompletedOnboarding: hasCompletedOnboarding,
            displayName: displayName,
            selectedLevel: selectedLevel,
            points: points,
            streak: streak,
            lastStudyDate: lastStudyDate
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
    }

    func save() async {
        try? await store.write(exportSnapshot(), to: key)
    }
}
