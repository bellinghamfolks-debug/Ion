import Foundation

/// Daily streak with streak freezes. A freeze covers one missed day; the
/// learner earns one at every 7-day milestone and can hold at most two.
enum StreakCalculator {
    static let maximumFreezes = 2
    static let freezeMilestone = 7

    struct State: Equatable {
        var streak: Int
        var freezes: Int
        var lastStudyDate: Date?
    }

    struct Outcome: Equatable {
        var state: State
        var freezesUsed: Int
        var freezeEarned: Bool
    }

    static func recordStudy(_ state: State, on date: Date, calendar: Calendar = .current) -> Outcome {
        var next = state
        var used = 0

        if let last = state.lastStudyDate {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: date)).day ?? 0
            if days <= 0 { return Outcome(state: state, freezesUsed: 0, freezeEarned: false) }
            let missed = days - 1
            if missed == 0 {
                next.streak += 1
            } else if missed <= state.freezes {
                used = missed
                next.freezes -= missed
                next.streak += 1
            } else {
                next.streak = 1
            }
        } else {
            next.streak = 1
        }
        next.lastStudyDate = date

        var earned = false
        if next.streak > state.streak, next.streak % freezeMilestone == 0, next.freezes < maximumFreezes {
            next.freezes += 1
            earned = true
        }
        return Outcome(state: next, freezesUsed: used, freezeEarned: earned)
    }

    /// Whether today's streak is still alive but needs study today to continue.
    static func isAtRisk(_ state: State, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard state.streak > 0, let last = state.lastStudyDate else { return false }
        return !calendar.isDate(last, inSameDayAs: now)
    }
}
