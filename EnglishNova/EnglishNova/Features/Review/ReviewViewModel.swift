import Foundation
import Combine

struct LessonReviewCandidate: Identifiable, Hashable {
    let id: String
    let lesson: Lesson
    let level: CEFRLevel
    let lastCompletedAt: Date
    let bestScore: Double
    let reviewIntervalDays: Int
    let daysSinceCompletion: Int
    let priority: Double

    var isDue: Bool { daysSinceCompletion >= reviewIntervalDays }

    var scorePercent: Int {
        Int((bestScore * 100).rounded())
    }

    var reviewLesson: Lesson {
        let graded = lesson.exercises.filter { $0.type != .explanation && $0.type != .flashcard }
        let productive = graded.filter { $0.type == .translation || $0.type == .speak }
        let controlled = graded.filter { $0.type == .fillBlank || $0.type == .arrangeWords }
        let receptive = graded.filter { $0.type == .multipleChoice || $0.type == .listenAndChoose }

        var selected: [Exercise] = []
        appendUnique(Array(productive.prefix(3)), to: &selected)
        appendUnique(Array(controlled.prefix(3)), to: &selected)
        appendUnique(Array(receptive.prefix(2)), to: &selected)

        if selected.count < 6 {
            appendUnique(Array(graded.prefix(8)), to: &selected)
        }

        let finalExercises = Array(selected.prefix(8))
        return Lesson(
            id: lesson.id,
            order: lesson.order,
            titleAr: lesson.titleAr,
            titleEn: lesson.titleEn,
            objectiveAr: lesson.objectiveAr,
            estimatedMinutes: min(8, max(4, finalExercises.count)),
            points: max(10, lesson.points / 3),
            vocabulary: lesson.vocabulary,
            exercises: finalExercises.isEmpty ? lesson.exercises : finalExercises
        )
    }

    private func appendUnique(_ exercises: [Exercise], to target: inout [Exercise]) {
        for exercise in exercises where !target.contains(where: { $0.id == exercise.id }) {
            target.append(exercise)
        }
    }
}

@MainActor
final class ReviewViewModel: ObservableObject {
    @Published var cards: [ReviewCard] = []
    @Published var currentIndex = 0
    @Published var showingAnswer = false
    @Published var isLoading = true
    @Published var lessonReviews: [LessonReviewCandidate] = []

    var current: ReviewCard? { cards.indices.contains(currentIndex) ? cards[currentIndex] : nil }
    var remaining: Int { max(0, cards.count - currentIndex) }
    var dueLessonReviews: [LessonReviewCandidate] { lessonReviews.filter(\.isDue) }
    var upcomingLessonReviews: [LessonReviewCandidate] { lessonReviews.filter { !$0.isDue } }

    func load(
        vocabularyRepository: VocabularyRepositoryProtocol,
        progressRepository: ProgressRepositoryProtocol,
        courseRepository: CourseRepositoryProtocol
    ) async {
        isLoading = true

        async let dueCards = vocabularyRepository.dueCards(on: .now)
        async let progress = progressRepository.snapshot()

        let catalog: CourseCatalog?
        do {
            catalog = try await courseRepository.catalog()
        } catch {
            catalog = nil
        }

        cards = await dueCards
        currentIndex = 0
        showingAnswer = false

        if let catalog {
            lessonReviews = buildLessonReviews(catalog: catalog, progress: await progress)
        } else {
            lessonReviews = []
        }

        isLoading = false
    }

    func grade(_ grade: ReviewGrade, repository: VocabularyRepositoryProtocol) async {
        guard let current else { return }
        await repository.grade(cardID: current.id, grade: grade, now: .now)
        currentIndex += 1
        showingAnswer = false
    }

    private func buildLessonReviews(catalog: CourseCatalog, progress: UserProgressSnapshot) -> [LessonReviewCandidate] {
        let calendar = Calendar.current
        let now = Date.now
        var candidates: [LessonReviewCandidate] = []

        for level in catalog.levels {
            for unit in level.units {
                for lesson in unit.lessons {
                    guard let lessonProgress = progress.lessons[lesson.id],
                          let completedAt = lessonProgress.completedAt else { continue }

                    let interval = reviewInterval(for: lessonProgress.bestScore, level: level.level)
                    let days = max(0, calendar.dateComponents([.day], from: completedAt.startOfDay, to: now.startOfDay).day ?? 0)
                    let overdue = Double(days - interval)
                    let weakness = max(0, 1 - lessonProgress.bestScore)
                    let priority = overdue * 0.16 + weakness * 8.0 + Double(max(0, lessonProgress.attempts - 1)) * 0.08

                    candidates.append(LessonReviewCandidate(
                        id: lesson.id,
                        lesson: lesson,
                        level: level.level,
                        lastCompletedAt: completedAt,
                        bestScore: lessonProgress.bestScore,
                        reviewIntervalDays: interval,
                        daysSinceCompletion: days,
                        priority: priority
                    ))
                }
            }
        }

        return candidates.sorted {
            if $0.isDue != $1.isDue { return $0.isDue && !$1.isDue }
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.bestScore < $1.bestScore
        }
    }

    private func reviewInterval(for score: Double, level: CEFRLevel) -> Int {
        let base: Int
        switch score {
        case ..<0.70: base = 1
        case ..<0.80: base = 3
        case ..<0.90: base = 7
        default: base = 14
        }

        switch level {
        case .a0, .a1: return base
        case .a2, .b1: return max(1, base - 1)
        case .b2, .c1: return max(1, base - 2)
        }
    }
}
