import Foundation

/// The four building blocks of "Today's session", in the order they run.
enum DailyStepKind: String, Codable, CaseIterable, Hashable {
    case review
    case lesson
    case mistakes
    case speaking
}

struct DailyStep: Identifiable, Hashable {
    let kind: DailyStepKind
    let minutes: Int
    let isDone: Bool
    /// For `.review`: due items; for `.mistakes`: open mistakes.
    let count: Int
    var id: DailyStepKind { kind }
}

struct DailySession: Hashable {
    let steps: [DailyStep]

    var completedCount: Int { steps.filter(\.isDone).count }
    var isComplete: Bool { !steps.isEmpty && steps.allSatisfy(\.isDone) }
    var progress: Double { steps.isEmpty ? 0 : Double(completedCount) / Double(steps.count) }
    var totalMinutes: Int { steps.reduce(0) { $0 + $1.minutes } }
    var remainingMinutes: Int { steps.filter { !$0.isDone }.reduce(0) { $0 + $1.minutes } }
    /// The first step still to do — what the big "Start" button opens.
    var nextStep: DailyStep? { steps.first { !$0.isDone } }
}

/// What the engine needs to know about today. Plain values only, so the
/// engine is pure and easy to test.
struct DailySessionInput: Hashable {
    var hasNextLesson: Bool
    var lessonMinutes: Int
    var lessonCompletedToday: Bool
    var dueReviewCount: Int
    var openMistakeCount: Int
    /// Steps that were part of today's session earlier today. A step that was
    /// planned stays visible after its work is done, so it shows as finished
    /// instead of silently disappearing.
    var plannedToday: Set<DailyStepKind>
    var completedToday: Set<DailyStepKind>
    var dailyGoalMinutes: Int
}

enum DailySessionEngine {
    static func makeSession(_ input: DailySessionInput) -> DailySession {
        var steps: [DailyStep] = []

        let reviewPlanned = input.plannedToday.contains(.review)
        if input.dueReviewCount > 0 || reviewPlanned {
            let done = input.completedToday.contains(.review) || (reviewPlanned && input.dueReviewCount == 0)
            steps.append(DailyStep(kind: .review, minutes: reviewMinutes(input.dueReviewCount), isDone: done, count: input.dueReviewCount))
        }

        if input.hasNextLesson || input.lessonCompletedToday {
            let done = input.lessonCompletedToday || input.completedToday.contains(.lesson)
            steps.append(DailyStep(kind: .lesson, minutes: max(3, input.lessonMinutes), isDone: done, count: 1))
        }

        let mistakesPlanned = input.plannedToday.contains(.mistakes)
        if input.openMistakeCount > 0 || mistakesPlanned {
            let done = input.completedToday.contains(.mistakes) || (mistakesPlanned && input.openMistakeCount == 0)
            steps.append(DailyStep(kind: .mistakes, minutes: 3, isDone: done, count: input.openMistakeCount))
        }

        // A short speaking turn closes every session; on light days (goal of
        // five minutes or less with a full plan) it is left out to keep it short.
        let light = input.dailyGoalMinutes <= 5 && steps.count >= 3
        if !light || input.plannedToday.contains(.speaking) {
            steps.append(DailyStep(kind: .speaking, minutes: 2, isDone: input.completedToday.contains(.speaking), count: 1))
        }

        return DailySession(steps: steps)
    }

    static func reviewMinutes(_ dueCount: Int) -> Int {
        min(8, max(2, Int((Double(max(dueCount, 1)) * 0.4).rounded(.up))))
    }
}

/// Remembers which steps were planned and finished today. Resets each day.
/// Used from the main thread only (views and their callbacks).
final class DailySessionStore: ObservableObject {
    static let shared = DailySessionStore()

    private struct State: Codable {
        var day: String
        var planned: Set<DailyStepKind>
        var completed: Set<DailyStepKind>
    }

    @Published private(set) var planned: Set<DailyStepKind> = []
    @Published private(set) var completed: Set<DailyStepKind> = []

    private let defaults: UserDefaults
    private let key = "englishnova.dailySession.v1"
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        reload()
    }

    func reload() {
        let today = Self.dayKey(now())
        if let data = defaults.data(forKey: key),
           let state = try? JSONDecoder().decode(State.self, from: data),
           state.day == today {
            planned = state.planned
            completed = state.completed
        } else {
            planned = []
            completed = []
        }
    }

    func markPlanned(_ kinds: [DailyStepKind]) {
        reload()
        let merged = planned.union(kinds)
        guard merged != planned else { return }
        planned = merged
        persist()
    }

    func markDone(_ kind: DailyStepKind) {
        reload()
        guard !completed.contains(kind) else { return }
        completed.insert(kind)
        planned.insert(kind)
        persist()
    }

    private func persist() {
        let state = State(day: Self.dayKey(now()), planned: planned, completed: completed)
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: key) }
    }

    static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
