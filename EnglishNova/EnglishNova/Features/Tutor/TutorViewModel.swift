import Foundation
import Combine

@MainActor
final class TutorViewModel: ObservableObject {
    @Published var messages: [TutorMessage] = [TutorMessage(role: .assistant, text: "مرحبًا. اكتب جملة إنجليزية أو اسأل عن قاعدة، وسأشرحها بالعربية خطوة بخطوة.")]
    @Published var draft = ""
    @Published var isSending = false
    @Published var errorMessage: String?
    let sessionID = UUID().uuidString

    func send(container: AppContainer, level: CEFRLevel) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        messages.append(TutorMessage(role: .user, text: text))
        draft = ""
        isSending = true
        defer { isSending = false }
        do {
            let reply = try await container.tutorRepository.reply(to: text, sessionID: sessionID, level: level, locale: container.settings.interfaceLanguage.rawValue, context: "general English tutoring")
            messages.append(reply)
        } catch { errorMessage = error.localizedDescription }
    }
}
