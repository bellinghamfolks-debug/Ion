import SwiftUI

struct AskAboutResultLink: View {
    let text: String
    var imageData: Data? = nil

    var body: some View {
        NavigationLink {
            ResultChatView(contextText: text, imageData: imageData)
        } label: {
            Label(L10n.t("اسأل سؤالًا إضافيًا", "Ask a follow-up question"),
                  systemImage: "bubble.left.and.text.bubble.right.fill")
        }
        .buttonStyle(BasirSecondaryButtonStyle())
        .accessibilityHint(L10n.t(
            "يفتح محادثة جديدة مرتبطة بهذه النتيجة.",
            "Opens a new conversation grounded in this result."
        ))
    }
}

struct ResultChatView: View {
    let contextText: String
    var imageData: Data? = nil

    @State private var question = ""
    @State private var answer = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        BasirScreen {
            BasirPageIntro(
                text: imageData == nil
                    ? L10n.t(
                        "اسأل عن النتيجة السابقة. ستكون الإجابة محصورة في النص المعروض حتى لا تختلط بمعلومات خارجية.",
                        "Ask about the previous result. The answer stays grounded in the displayed text to avoid mixing in unrelated information."
                    )
                    : L10n.t(
                        "اسأل عن النتيجة أو عن تفاصيل إضافية في الصورة الأصلية.",
                        "Ask about the result or request more detail from the original image."
                    )
            )

            BasirTextEditor(
                title: L10n.t("سؤالك الإضافي", "Follow-up question"),
                placeholder: L10n.t("مثال: ما الرقم المذكور في السطر الأخير؟",
                                    "Example: What number appears in the last line?"),
                text: $question,
                minimumHeight: 130,
                characterLimit: 4_000
            )

            Button {
                Task { await ask() }
            } label: {
                HStack(spacing: 10) {
                    if isLoading { ProgressView().tint(.white) }
                    Label(
                        isLoading ? L10n.t("جاري البحث في النتيجة", "Reviewing the result")
                                  : L10n.t("إرسال السؤال", "Send question"),
                        systemImage: "paperplane.fill"
                    )
                }
            }
            .buttonStyle(BasirPrimaryButtonStyle())
            .disabled(isLoading || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let errorMessage {
                BasirStatusBanner(text: errorMessage, tone: .danger)
            }

            if !answer.isEmpty {
                BasirResultCard(title: L10n.t("الإجابة", "Answer"), text: answer) {
                    CopyButton(text: answer)
                }
            }
        }
        .navigationTitle(L10n.t("سؤال إضافي", "Follow-up question"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ask() async {
        guard !isLoading else { return }
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        let content = String(contextText.prefix(12_000))
        isLoading = true
        errorMessage = nil
        answer = ""
        ProcessingFeedback.start()
        defer { isLoading = false }

        do {
            let image = imageData
            let groundedInput = GeminiPrompts.groundedQuestionInput(
                question: q,
                context: content,
                contextLabel: "previous_result"
            )
            answer = try await AiProviderFactory.current().ask(
                task: .ask,
                input: groundedInput,
                instruction: GeminiPrompts.groundedQuestionInstruction(hasSourceImage: image != nil),
                language: BasirSettings.shared.language,
                imageData: image,
                mimeType: image != nil ? "image/jpeg" : nil
            )
            question = ""
            ProcessingFeedback.done()
            UIAccessibility.post(notification: .announcement, argument: BasirCopy.resultReady)
        } catch {
            errorMessage = UserFriendlyErrorMapper.map(error)
            ProcessingFeedback.failed()
        }
    }
}
