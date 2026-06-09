import Foundation
import Combine

@MainActor
final class ReviewViewModel: ObservableObject {
    @Published var cards: [ReviewCard] = []
    @Published var currentIndex = 0
    @Published var showingAnswer = false
    @Published var isLoading = true

    var current: ReviewCard? { cards.indices.contains(currentIndex) ? cards[currentIndex] : nil }
    var remaining: Int { max(0, cards.count - currentIndex) }

    func load(repository: VocabularyRepositoryProtocol) async {
        isLoading = true
        cards = await repository.dueCards(on: .now)
        currentIndex = 0
        showingAnswer = false
        isLoading = false
    }

    func grade(_ grade: ReviewGrade, repository: VocabularyRepositoryProtocol) async {
        guard let current else { return }
        await repository.grade(cardID: current.id, grade: grade, now: .now)
        currentIndex += 1
        showingAnswer = false
    }
}
