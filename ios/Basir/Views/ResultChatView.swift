// ResultChatView.swift
// "Ask about the result" — a generic follow-up Q&A over any piece of text
// Basir just produced (a description, translation, answer, or converted
// document). Answers are grounded in that text.

import SwiftUI

/// Reusable "Ask about the result" link placed under a result on any
/// screen. Opens ResultChatView grounded in that result text. If image
/// data is supplied, follow-up questions re-examine the image (so the
/// user can ask about details the first description didn't mention).
struct AskAboutResultLink: View {
    let text: String
    var imageData: Data? = nil
    var body: some View {
        NavigationLink {
            ResultChatView(contextText: text, imageData: imageData)
        } label: {
            Label(L10n.t("اسأل عن هذه النتيجة", "Ask about this result"),
                  systemImage: "bubble.left.and.text.bubble.right.fill")
                .font(.callout.weight(.medium))
        }
    }
}

struct ResultChatView: View {
    let contextText: String
    var imageData: Data? = nil

    @State private var question = ""
    @State private var answer = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.t(
                    "اطرح سؤالًا عن النتيجة السابقة. سيجيب بصير اعتمادًا على محتواها فقط.",
                    "Ask a question about the previous result. Basir answers using only that content."
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
                    .accessibilityLabel(L10n.t("اكتب سؤالك عن هذه النتيجة",
                                                "Type your question about this result"))

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
                    SelectableText(text: answer)
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
        .navigationTitle(L10n.t("اسأل عن هذه النتيجة", "Ask about this result"))
    }

    private func ask() async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        let content = String(contextText.prefix(12000))
        isLoading = true
        errorMessage = nil
        answer = ""
        ProcessingFeedback.start()
        defer { isLoading = false }
        do {
            // If we still have the source image, let the model RE-EXAMINE
            // it for the follow-up (e.g. "what's written on their shirt?")
            // instead of being limited to the earlier text. Otherwise stay
            // grounded in the produced text.
            let instruction: String
            let image: Data?
            if let imageData {
                instruction = "The user is asking a follow-up about the SAME image, "
                    + "described earlier as:\n\(content)\n\nRe-examine the image and answer "
                    + "the question directly. If it truly isn't visible, say so."
                image = imageData
            } else {
                instruction = "Answer the user's question using ONLY the following content "
                    + "that Basir produced earlier. If the answer is not in it, say so plainly.\n\nCONTENT:\n"
                    + content
                image = nil
            }
            answer = try await AiProviderFactory.current().ask(
                task: .ask,
                input: q,
                instruction: instruction,
                language: BasirSettings.shared.language,
                imageData: image,
                mimeType: image != nil ? "image/jpeg" : nil
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
