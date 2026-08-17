import Foundation

struct LessonReviewCandidate: Identifiable, Hashable {
    var id: String { lesson.id }
    let lesson: Lesson
    let progress: LessonProgress
    let state: LessonReviewState?
    let dueDate: Date
    let priority: Double
    let isDue: Bool
}

enum LessonReviewEngine {
    private static let day: TimeInterval = 86_400

    static func allCandidates(
        catalog: CourseCatalog,
        snapshot: UserProgressSnapshot,
        now: Date = .now
    ) -> [LessonReviewCandidate] {
        var lessonsByID: [String: Lesson] = [:]
        for level in catalog.levels {
            for unit in level.units {
                for lesson in unit.lessons {
                    lessonsByID[lesson.id] = lesson
                }
            }
        }

        return snapshot.lessons.values.compactMap { progress in
            guard let completedAt = progress.completedAt,
                  let lesson = lessonsByID[progress.lessonID] else { return nil }

            let state = snapshot.lessonReviews[progress.lessonID]
            let dueDate = state?.dueDate ?? initialDueDate(completedAt: completedAt)
            let isDue = dueDate <= now
            let interval = max(1, state?.intervalDays ?? 1)
            let referenceScore = min(1, max(0, state?.lastScore ?? progress.bestScore))
            let overdueDays = max(0, now.timeIntervalSince(dueDate) / day)
            let weakness = 1 - referenceScore
            let repeatDifficulty = min(0.6, Double(max(0, progress.attempts - 1)) * 0.08)
            let lapsePenalty = min(0.8, Double(state?.lapses ?? 0) * 0.12)
            let priority = (overdueDays / Double(interval)) + (weakness * 2.2) + repeatDifficulty + lapsePenalty

            return LessonReviewCandidate(
                lesson: lesson,
                progress: progress,
                state: state,
                dueDate: dueDate,
                priority: priority,
                isDue: isDue
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDue != rhs.isDue { return lhs.isDue && !rhs.isDue }
            if abs(lhs.priority - rhs.priority) > 0.0001 { return lhs.priority > rhs.priority }
            return lhs.dueDate < rhs.dueDate
        }
    }

    static func dueCandidates(
        catalog: CourseCatalog,
        snapshot: UserProgressSnapshot,
        now: Date = .now
    ) -> [LessonReviewCandidate] {
        allCandidates(catalog: catalog, snapshot: snapshot, now: now).filter(\.isDue)
    }

    static func initialDueDate(completedAt: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: completedAt)
            ?? completedAt.addingTimeInterval(day)
    }

    static func updatedState(
        lessonID: String,
        current: LessonReviewState?,
        score: Double,
        now: Date = .now
    ) -> LessonReviewState {
        let normalized = min(1, max(0, score))
        var state = current ?? LessonReviewState(lessonID: lessonID, dueDate: now)
        let previous = max(1, state.intervalDays)
        let nextInterval: Int

        switch normalized {
        case ..<0.55:
            nextInterval = 1
        case ..<0.70:
            nextInterval = min(3, max(1, previous))
        case ..<0.85:
            nextInterval = state.repetitions == 0 ? 3 : max(3, Int((Double(previous) * 1.6).rounded()))
        case ..<0.95:
            nextInterval = state.repetitions == 0 ? 7 : max(5, Int((Double(previous) * 2.1).rounded()))
        default:
            nextInterval = state.repetitions == 0 ? 14 : max(7, Int((Double(previous) * 2.7).rounded()))
        }

        state.repetitions += 1
        state.intervalDays = min(90, nextInterval)
        state.lastReviewedAt = now
        state.lastScore = normalized
        state.bestScore = max(state.bestScore, normalized)
        if normalized < 0.60 {
            state.lapses += 1
            state.successfulStreak = 0
        } else if normalized >= 0.70 {
            state.successfulStreak += 1
        } else {
            state.successfulStreak = 0
        }
        state.dueDate = Calendar.current.date(byAdding: .day, value: state.intervalDays, to: now)
            ?? now.addingTimeInterval(Double(state.intervalDays) * day)
        return state
    }

    static func reviewExercises(
        for lesson: Lesson,
        reviewCount: Int,
        limit: Int = 6
    ) -> [Exercise] {
        let graded = lesson.exercises.filter { $0.type != .explanation && $0.type != .flashcard }
        guard !graded.isEmpty else { return [] }

        let productive = graded.filter { $0.type == .translation || $0.type == .speak }
        let controlled = graded.filter { $0.type == .fillBlank || $0.type == .arrangeWords }
        let receptive = graded.filter { $0.type == .multipleChoice || $0.type == .listenAndChoose }

        let target = max(3, min(limit, graded.count))
        let plan: (productive: Int, controlled: Int, receptive: Int)
        switch lesson.reviewLevel {
        case .a0, .a1:
            plan = (1, 2, 3)
        case .a2, .b1:
            plan = (2, 2, 2)
        case .b2, .c1:
            plan = (3, 2, 1)
        }

        var selected: [Exercise] = []
        var selectedIDs = Set<String>()

        func append(from source: [Exercise], count: Int, offset: Int) {
            guard count > 0 else { return }
            for exercise in rotated(source, offset: offset).prefix(count) where !selectedIDs.contains(exercise.id) {
                selected.append(exercise)
                selectedIDs.insert(exercise.id)
            }
        }

        append(from: productive, count: min(plan.productive, target), offset: reviewCount)
        append(from: controlled, count: min(plan.controlled, max(0, target - selected.count)), offset: reviewCount + 1)
        append(from: receptive, count: min(plan.receptive, max(0, target - selected.count)), offset: reviewCount + 2)

        if selected.count < target {
            let remaining = rotated(graded.filter { !selectedIDs.contains($0.id) }, offset: reviewCount + 3)
            append(from: remaining, count: target - selected.count, offset: 0)
        }

        return Array(selected.prefix(target))
    }

    private static func rotated(_ source: [Exercise], offset: Int) -> [Exercise] {
        let sorted = source.sorted { $0.id < $1.id }
        guard !sorted.isEmpty else { return [] }
        let shift = abs(offset) % sorted.count
        guard shift > 0 else { return sorted }
        return Array(sorted[shift...]) + Array(sorted[..<shift])
    }
}

extension Lesson {
    var reviewLevel: CEFRLevel {
        let lower = id.lowercased()
        if lower.contains("c1") { return .c1 }
        if lower.contains("b2") { return .b2 }
        if lower.contains("b1") { return .b1 }
        if lower.contains("a2") { return .a2 }
        if lower.contains("a1") { return .a1 }
        return .a0
    }
}
