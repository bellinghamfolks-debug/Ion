import Foundation
import Combine

@MainActor
final class TutorViewModel: ObservableObject {
    private static let greeting = TutorMessage(
        role: .assistant,
        text: "مرحبًا. اكتب جملة إنجليزية أو اسأل عن قاعدة، وسأشرحها بالعربية خطوة بخطوة."
    )

    @Published var messages: [TutorMessage] = [TutorViewModel.greeting]
    @Published var draft = ""
    @Published var isSending = false
    @Published var errorMessage: String?
    @Published private(set) var savedConversations: [TutorConversation] = []

    /// The conversation currently on screen. Persisted once the learner writes.
    private var conversation = TutorConversation(messages: [TutorViewModel.greeting])

    var sessionID: String { conversation.id.uuidString }

    func send(container: AppContainer, level: CEFRLevel) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        let userMessage = TutorMessage(role: .user, text: text)
        messages.append(userMessage)
        draft = ""
        isSending = true
        defer { isSending = false }
        do {
            let reply = try await container.tutorRepository.reply(
                to: text,
                sessionID: sessionID,
                level: level,
                locale: container.settings.interfaceLanguage.rawValue,
                context: "general English tutoring"
            )
            messages.append(reply)
            await persist(container: container)
            if container.settings.autoSpeakTutorReplies {
                speak(reply, container: container)
            }
        } catch {
            errorMessage = error.localizedDescription
            await persist(container: container)
        }
    }

    /// Reads an assistant message aloud (the English reply) so a screen-reader
    /// user or anyone can hear what the tutor said.
    func speak(_ message: TutorMessage, container: AppContainer) {
        let spoken = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return }
        container.textToSpeech.speak(spoken, accent: container.settings.accentVariant, rate: Float(container.settings.speechRate))
    }

    func stopSpeaking(container: AppContainer) {
        container.textToSpeech.stop()
    }

    // MARK: - Conversation history

    func loadHistory(container: AppContainer) async {
        savedConversations = await container.conversationRepository.all()
    }

    func startNewConversation(container: AppContainer) {
        container.textToSpeech.stop()
        conversation = TutorConversation(provider: container.settings.tutorProvider, messages: [Self.greeting])
        messages = conversation.messages
        draft = ""
        errorMessage = nil
    }

    func open(_ saved: TutorConversation, container: AppContainer) {
        container.textToSpeech.stop()
        conversation = saved
        messages = saved.messages.isEmpty ? [Self.greeting] : saved.messages
        draft = ""
        errorMessage = nil
    }

    func delete(_ saved: TutorConversation, container: AppContainer) async {
        await container.conversationRepository.delete(id: saved.id)
        await loadHistory(container: container)
        if saved.id == conversation.id { startNewConversation(container: container) }
    }

    private func persist(container: AppContainer) async {
        conversation.messages = messages
        conversation.updatedAt = .now
        conversation.provider = container.settings.tutorProvider
        await container.conversationRepository.save(conversation)
        await loadHistory(container: container)
    }
}
