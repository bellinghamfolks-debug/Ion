import SwiftUI

struct DocumentQAView: View {
    @ObservedObject private var store = LastDocumentStore.shared

    @State private var question = ""
    @State private var answer = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        BasirScreen {
            if let name = store.sourceName, !name.isEmpty {
                BasirInfoRow(
                    label: L10n.t("المستند الحالي", "Current document"),
                    value: name,
                    systemImage: "doc.text.fill"
                )
            }

            BasirPageIntro(
                text: L10n.t(
                    "اكتب سؤالًا محددًا عن المستند الأخير. يفحص بصير كامل النص المحلي لاختيار المقاطع الأقرب لسؤالك، ولن يخمّن جوابًا غير موجود فيها.",
                    "Ask a specific question about the latest document. Basir scans the full local text to select the excerpts most relevant to your question and will not invent an answer that is not there."
                )
            )

            if store.wasTruncated {
                BasirStatusBanner(
                    text: L10n.t(
                        "كان المستند ضخمًا جدًا، لذلك حُفظ أول مليوني حرف فقط للأسئلة اللاحقة. استخدم أداة التحويل أو قسّم الملف للحصول على تغطية كاملة.",
                        "The document was extremely large, so only its first two million characters were kept for follow-up questions. Use the conversion tool or split the file for full coverage."
                    ),
                    tone: .warning
                )
            }

            BasirTextEditor(
                title: L10n.t("سؤالك عن المستند", "Question about the document"),
                placeholder: L10n.t("مثال: ما تاريخ انتهاء العقد؟",
                                    "Example: What is the contract expiry date?"),
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
                        isLoading ? L10n.t("جاري مراجعة المستند", "Reviewing the document")
                                  : L10n.t("البحث عن الإجابة", "Find the answer"),
                        systemImage: "doc.text.magnifyingglass"
                    )
                }
            }
            .buttonStyle(BasirPrimaryButtonStyle())
            .disabled(isLoading || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let errorMessage {
                BasirStatusBanner(text: errorMessage, tone: .danger)
            }

            if !answer.isEmpty {
                BasirResultCard(title: L10n.t("الإجابة من المستند", "Answer from the document"), text: answer) {
                    CopyButton(text: answer)
                }
            }
        }
        .navigationTitle(L10n.t("اسأل عن المستند", "Ask about document"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ask() async {
        guard !isLoading else { return }
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        let selection = DocumentContextSelector.select(
            document: store.text ?? "",
            question: q
        )
        guard !selection.isEmpty else {
            errorMessage = L10n.t(
                "لا يوجد نص مستند متاح للبحث. حوّل مستندًا أولًا ثم أعد المحاولة.",
                "No document text is available to search. Convert a document first, then try again."
            )
            return
        }
        isLoading = true
        errorMessage = nil
        answer = ""
        ProcessingFeedback.start()
        defer { isLoading = false }

        do {
            let groundedInput = GeminiPrompts.groundedQuestionInput(
                question: q,
                context: selection.context,
                contextLabel: "selected excerpts from the full document"
            )
            answer = try await AiProviderFactory.current().ask(
                task: .askDocument,
                input: groundedInput,
                instruction: GeminiPrompts.groundedQuestionInstruction(hasSourceImage: false),
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
}
