import Foundation
import Combine

@MainActor
final class TutorViewModel: ObservableObject {
    private static var greeting: TutorMessage {
        TutorMessage(
            role: .assistant,
            text: L("اكتب جملة أو سؤالًا. أستطيع تصحيح الإنجليزية، شرح القاعدة بالعربية، أو متابعة محادثة معك.")
        )
    }

    @Published var messages: [TutorMessage] = [TutorViewModel.greeting]
    @Published var draft = ""
    @Published var isSending = false
    @Published var errorMessage: String?
    @Published private(set) var savedConversations: [TutorConversation] = []

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
            let recent = messages
                .suffix(10)
                .map { message in
                    let speaker = message.role == .user ? "Learner" : "Tutor"
                    return "\(speaker): \(message.text)"
                }
                .joined(separator: "\n")

            let context = """
            Current EnglishNova tutor conversation. Continue naturally and do not restart the interaction.
            Recent turns:
            \(recent)
            """

            let reply = try await container.tutorRepository.reply(
                to: text,
                sessionID: sessionID,
                level: level,
                locale: container.settings.interfaceLanguage.rawValue,
                context: context
            )
            messages.append(reply)
            await persist(container: container)

            if container.settings.autoSpeakTutorReplies {
                speak(reply, container: container)
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("تعذر الحصول على رد من المدرّب.")
            await persist(container: container)
        }
    }

    func speak(_ message: TutorMessage, container: AppContainer) {
        let spoken = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return }
        container.textToSpeech.speak(
            spoken,
            accent: container.settings.accentVariant,
            rate: Float(container.settings.speechRate)
        )
    }

    func stopSpeaking(container: AppContainer) {
        container.textToSpeech.stop()
    }

    func loadHistory(container: AppContainer) async {
        savedConversations = await container.conversationRepository.all()
    }

    func startNewConversation(container: AppContainer) {
        container.textToSpeech.stop()
        conversation = TutorConversation(
            provider: container.settings.tutorProvider,
            messages: [Self.greeting]
        )
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
        if saved.id == conversation.id {
            startNewConversation(container: container)
        }
    }

    private func persist(container: AppContainer) async {
        conversation.messages = messages
        conversation.updatedAt = .now
        conversation.provider = container.settings.tutorProvider
        await container.conversationRepository.save(conversation)
        await loadHistory(container: container)
    }
}
