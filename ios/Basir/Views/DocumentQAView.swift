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
                    Text(L10n.t("المستند: ", "Document: ") + name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(L10n.t(
                    "اطرح سؤالًا عن المستند الذي حوّلته للتو. تأتي الإجابة من نص المستند فقط.",
                    "Ask a question about the document you just converted. Answers come only from the document text."
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
                    .accessibilityLabel(L10n.t("اكتب سؤالك عن المستند",
                                                "Type your question about the document"))

                Button {
                    Task { await ask() }
                } label: {
                    HStack {
                        if isLoading { ProgressView().tint(.white) }
                        Text(isLoading ? L10n.t("جارٍ المعالجة...", "Processing...")
                                       : L10n.t("اسأل", "Ask"))
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
        .navigationTitle(L10n.t("اسأل عن آخر مستند", "Ask about the latest document"))
    }

    private func ask() async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        // Cap the context so a very long document stays within a request.
        let document = String((store.text ?? "").prefix(12000))
        isLoading = true
        errorMessage = nil
        answer = ""
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
            UIAccessibility.post(notification: .announcement,
                                 argument: L10n.t("أصبحت الإجابة جاهزة.", "Answer ready."))
        } catch {
            errorMessage = UserFriendlyErrorMapper.map(error)
        }
    }
}
