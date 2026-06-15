import Foundation

protocol ConversationRepositoryProtocol {
    /// All saved conversations, newest first.
    func all() async -> [TutorConversation]
    /// Insert or update a conversation (keyed by id), keeping the list sorted.
    func save(_ conversation: TutorConversation) async
    func delete(id: UUID) async
    func deleteAll() async
}

/// Stores interactive-tutor conversations on the device via `FileStore`
/// (Application Support, protected by file-level encryption). Conversations
/// persist across launches so the learner can return to any past chat.
actor ConversationRepository: ConversationRepositoryProtocol {
    private let store: FileStore
    private let key = "tutor_conversations.json"
    private var cached: [TutorConversation]?

    init(store: FileStore) { self.store = store }

    func all() async -> [TutorConversation] {
        if let cached { return cached }
        let value = (try? await store.read([TutorConversation].self, from: key)) ?? []
        let sorted = value.sorted { $0.updatedAt > $1.updatedAt }
        cached = sorted
        return sorted
    }

    func save(_ conversation: TutorConversation) async {
        // Only persist conversations the learner actually contributed to, so
        // an opened-but-unused screen does not litter the history.
        guard conversation.hasLearnerContent else { return }
        var list = await all()
        if let index = list.firstIndex(where: { $0.id == conversation.id }) {
            list[index] = conversation
        } else {
            list.append(conversation)
        }
        list.sort { $0.updatedAt > $1.updatedAt }
        await persist(list)
    }

    func delete(id: UUID) async {
        var list = await all()
        list.removeAll { $0.id == id }
        await persist(list)
    }

    func deleteAll() async {
        await persist([])
    }

    private func persist(_ list: [TutorConversation]) async {
        cached = list
        try? await store.write(list, to: key)
    }
}
