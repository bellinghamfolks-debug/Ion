import SwiftUI

struct AskBasirView: View {
    @State private var question = ""
    @State private var answer = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        BasirScreen {
            BasirPageIntro(
                text: L10n.t(
                    "اكتب السؤال كما يخطر في بالك، أو استخدم الإملاء. يمكنك مراجعة النص قبل الإرسال ومتابعة النقاش بعد ظهور الإجابة.",
                    "Write the question naturally or use dictation. You can review it before sending and continue the discussion after the answer appears."
                )
            )

            BasirTextEditor(
                title: L10n.t("سؤالك", "Your question"),
                placeholder: L10n.t("مثال: لخّص لي الفرق بين العقد الباطل والعقد القابل للإبطال.",
                                    "Example: Summarize the difference between a void and voidable contract."),
                text: $question,
                minimumHeight: 150,
                characterLimit: 8_000
            )

            HStack(spacing: 12) {
                Button {
                    Task { await dictate() }
                } label: {
                    Label(L10n.t("إملاء", "Dictate"), systemImage: "mic.fill")
                }
                .buttonStyle(BasirSecondaryButtonStyle())
                .disabled(isLoading)

                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: 10) {
                        if isLoading { ProgressView().tint(.white) }
                        Label(
                            isLoading ? L10n.t("جاري إعداد الإجابة", "Preparing answer")
                                      : L10n.t("إرسال", "Send"),
                            systemImage: isLoading ? "hourglass" : "paperplane.fill"
                        )
                    }
                }
                .buttonStyle(BasirPrimaryButtonStyle())
                .disabled(isLoading || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let errorMessage {
                BasirStatusBanner(
                    text: errorMessage,
                    tone: .danger,
                    title: L10n.t("تعذّر إرسال السؤال", "Could not send the question")
                )
            }

            if !answer.isEmpty {
                BasirResultCard(title: L10n.t("إجابة بصير", "Basir's answer"), text: answer) {
                    HStack(spacing: 4) {
                        CopyButton(text: answer)
                        ShareLink(item: answer) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(BasirIconButtonStyle())
                        .accessibilityLabel(L10n.t("مشاركة الإجابة", "Share answer"))
                    }
                }

                AskAboutResultLink(text: answer)
            }

            BasirStatusBanner(text: BasirCopy.verifyImportantInformation, tone: .warning)
        }
        .navigationTitle(L10n.t("اسأل بصير", "Ask Basir"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() async {
        guard !isLoading else { return }
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        answer = ""
        ProcessingFeedback.start()
        defer { isLoading = false }

        do {
            answer = try await AiProviderFactory.current().ask(
                task: .ask,
                input: q,
                instruction: GeminiPrompts.generalAskInstruction,
                language: BasirSettings.shared.language,
                imageData: nil,
                mimeType: nil
            )
            question = ""
            ProcessingFeedback.done()
            UIAccessibility.post(notification: .announcement, argument: BasirCopy.resultReady)
        } catch {
            errorMessage = UserFriendlyErrorMapper.map(error)
            ProcessingFeedback.failed()
        }
    }

    private func dictate() async {
        let auth = await SpeechRecognizer.shared.requestAuthorization()
        guard auth == .granted else {
            errorMessage = L10n.t(
                "اسمح لبصير باستخدام الميكروفون والتعرّف على الكلام من إعدادات iPhone، ثم جرّب الإملاء مرة أخرى.",
                "Allow Basir to use the microphone and Speech Recognition in iPhone Settings, then try dictation again."
            )
            return
        }
        SpeechRecognizer.shared.startDictation(language: BasirSettings.shared.language) { final in
            question = final
        }
    }
}
