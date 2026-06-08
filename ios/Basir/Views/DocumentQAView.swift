// DocumentQAView.swift
// Mirrors Android showDocumentQAScreen(): ask questions about the most
// recently converted document. Answered only from the cached text.

import SwiftUI

struct DocumentQAView: View {
    @ObservedObject private var store = LastDocumentStore.shared

    @State private var question = ""
    @State private var answer = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let name = store.sourceName, !name.isEmpty {
                    Text(L10n.t("الملف: ", "File: ") + name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(L10n.t(
                    "اسأل عن محتوى المستند الأخير. سيجيب بصير اعتمادًا على النص المستخرج منه فقط.",
                    "Ask about your last document. Basir answers using only the text extracted from it."
                ))
                .font(.callout)
                .foregroundStyle(.secondary)

                TextEditor(text: $question)
                    .focused($focused)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.tertiary))
                    .accessibilityLabel(L10n.t("اكتب سؤالك عن الملف",
                                                "Type your question about the file"))

                Button {
                    Task { await ask() }
                } label: {
                    HStack {
                        if isLoading { ProgressView().tint(.white) }
                        Text(isLoading ? L10n.t("أجهّز الإجابة...", "Preparing your answer...")
                                       : L10n.t("إرسال السؤال", "Send question"))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isLoading || question.trimmingCharacters(in: .whitespaces).isEmpty)

                if !answer.isEmpty {
                    Divider().padding(.vertical, 4)
                    Text(L10n.t("الإجابة", "Answer"))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(answer)
                        .textSelection(.enabled)
                        .accessibilityLabel(answer)
                    CopyButton(text: answer)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(20)
        }
        .navigationTitle(L10n.t("اسأل عن المستند الأخير", "Ask about your last document"))
    }

    private func ask() async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        // Cap the context so a very long document stays within a request.
        let document = String((store.text ?? "").prefix(12000))
        isLoading = true
        errorMessage = nil
        answer = ""
        ProcessingFeedback.start()
        defer { isLoading = false }
        do {
            let instruction = "Answer the user's question using ONLY the following document. "
                + "If the answer is not in the document, say so plainly.\n\nDOCUMENT:\n" + document
            answer = try await AiProviderFactory.current().ask(
                task: .askDocument,
                input: q,
                instruction: instruction,
                language: BasirSettings.shared.language,
                imageData: nil,
                mimeType: nil
            )
            question = ""        // clear the box once the answer arrives
            ProcessingFeedback.done()
            UIAccessibility.post(notification: .announcement,
                                 argument: L10n.t("الإجابة جاهزة.", "Your answer is ready."))
        } catch {
            errorMessage = UserFriendlyErrorMapper.map(error)
            ProcessingFeedback.failed()
        }
    }
}
