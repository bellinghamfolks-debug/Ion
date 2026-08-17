import Foundation
import Combine

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
            lessonReviews = LessonReviewEngine.allCandidates(
                catalog: catalog,
                snapshot: await progress,
                now: .now
            )
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
}
