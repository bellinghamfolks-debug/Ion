import Foundation
import Combine

@MainActor
final class TutorViewModel: ObservableObject {
    private static var greeting: TutorMessage {
        TutorMessage(
            role: .assistant,
            text: L("مرحبًا. تحدث معي بالإنجليزية، وسأتابع السياق وأركز على الأخطاء التي تتكرر معك.")
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
            let context = await learningContext(container: container)
            let reply = try await container.tutorRepository.reply(
                to: text,
                sessionID: sessionID,
                level: level,
                locale: container.settings.interfaceLanguage.rawValue,
                context: context
            )
            messages.append(reply)
            await rememberCorrections(reply, learnerMessage: text, container: container)
            await persist(container: container)
            if container.settings.autoSpeakTutorReplies {
                speak(reply, container: container)
            }
        } catch {
            errorMessage = error.localizedDescription
            await persist(container: container)
        }
    }

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

    // MARK: - Adaptive context

    private func learningContext(container: AppContainer) async -> String {
        async let progressValue = container.progressRepository.snapshot()
        async let memoryValue = container.learningMemoryRepository.snapshot()
        let progress = await progressValue
        let memory = await memoryValue

        let recentChat = messages.suffix(10).map { message in
            let role = message.role == .user ? "Learner" : "Tutor"
            return "\(role): \(String(message.text.prefix(500)))"
        }.joined(separator: "\n")

        let weakSkills = progress.skills.values
            .filter { $0.attempts > 0 }
            .sorted { lhs, rhs in
                lhs.accuracy == rhs.accuracy ? lhs.attempts > rhs.attempts : lhs.accuracy < rhs.accuracy
            }
            .prefix(4)
            .map { "\($0.skill.rawValue)=\(Int($0.accuracy * 100))%/\($0.attempts) attempts" }
            .joined(separator: ", ")

        let unresolved = memory.mistakes
            .filter { !$0.resolved }
            .prefix(6)
            .map { "\($0.category): \($0.learnerAnswer) -> \($0.correction)" }
            .joined(separator: " | ")

        return [
            "Study mode: \(container.settings.studyMode.rawValue)",
            "Learning pathway: \(container.settings.selectedLearningPathway.rawValue)",
            weakSkills.isEmpty ? nil : "Weak skill signals: \(weakSkills)",
            unresolved.isEmpty ? nil : "Recent unresolved mistakes: \(unresolved)",
            "Recent conversation:\n\(recentChat)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }

    private func rememberCorrections(_ reply: TutorMessage, learnerMessage: String, container: AppContainer) async {
        guard !reply.corrections.isEmpty else { return }
        for correction in reply.corrections.prefix(8) {
            let original = correction.original.trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = correction.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !original.isEmpty, !replacement.isEmpty else { continue }
            await container.learningMemoryRepository.recordMistake(.init(
                id: UUID().uuidString,
                category: L("المدرس التفاعلي"),
                source: L("محادثة ذكية"),
                prompt: learnerMessage,
                learnerAnswer: original,
                correction: replacement,
                explanationAr: correction.reason,
                createdAt: .now,
                reviewCount: 0,
                resolved: false
            ))
        }
        if container.accountService.isAuthenticated {
            _ = await container.progressSyncService.push(showFeedback: false)
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
