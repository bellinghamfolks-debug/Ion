import Foundation

actor VocabularyRepository: VocabularyRepositoryProtocol {
    private let store: FileStore
    private let key = "review_cards.json"
    private var cached: [ReviewCard]?

    init(store: FileStore) { self.store = store }

    func allCards() async -> [ReviewCard] {
        if let cached { return cached }
        let value = (try? await store.read([ReviewCard].self, from: key)) ?? []
        cached = value
        return value
    }

    func add(words: [VocabularyWord]) async {
        var cards = await allCards()
        let existing = Set(cards.map(\.id))
        cards.append(contentsOf: words.filter { !existing.contains($0.id) }.map { ReviewCard(word: $0) })
        await persist(cards)
    }

    func dueCards(on date: Date = .now) async -> [ReviewCard] {
        await allCards().filter { $0.dueDate <= date }.sorted { $0.dueDate < $1.dueDate }
    }

    func grade(cardID: String, grade: ReviewGrade, now: Date = .now) async {
        var cards = await allCards()
        guard let index = cards.firstIndex(where: { $0.id == cardID }) else { return }
        cards[index] = AdaptiveReviewEngine.reviewed(cards[index], grade: grade, now: now)
        await persist(cards)
    }

    func updateMetadata(cardID: String, isFavorite: Bool, tags: [String], note: String) async {
        var cards = await allCards()
        guard let index = cards.firstIndex(where: { $0.id == cardID }) else { return }
        cards[index].isFavorite = isFavorite
        cards[index].tags = Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        cards[index].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        await persist(cards)
    }

    func remove(cardID: String) async {
        var cards = await allCards()
        cards.removeAll { $0.id == cardID }
        await persist(cards)
    }

    func replace(with cards: [ReviewCard]) async {
        await persist(cards)
    }

    private func persist(_ cards: [ReviewCard]) async {
        cached = cards
        try? await store.write(cards, to: key)
    }
}
