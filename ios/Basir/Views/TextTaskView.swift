// TextTaskView.swift
// Generic "paste text → Gemini" screen, the iOS counterpart to Android's
// showTextTaskScreen(). Used by Advanced tools (study cards, reply,
// table-as-text) and the "scene text" guidance tool.

import SwiftUI
import UniformTypeIdentifiers

struct TextTaskView: View {
    let title: String
    let hint: String
    /// The model directive (kept in English, like the Android calls).
    let instruction: String

    @State private var input = ""
    @State private var result = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showDocPicker = false
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                // Insert text from a document instead of pasting manually.
                Button {
                    showDocPicker = true
                } label: {
                    Label(L10n.t("إضافة نص من مستند", "Add text from a document"),
                          systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)

                TextEditor(text: $input)
                    .focused($focused)
                    .frame(minHeight: 150)
                    .padding(8)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.tertiary))
                    .accessibilityLabel(hint)

                Button {
                    Task { await run() }
                } label: {
                    HStack {
                        if isLoading { ProgressView().tint(.white) }
                        Text(isLoading
                             ? L10n.t("أجهّز النتيجة...", "Preparing your result...")
                             : L10n.t("إنشاء النتيجة", "Generate result"))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isLoading || input.trimmingCharacters(in: .whitespaces).isEmpty)

                if !result.isEmpty {
                    Divider().padding(.vertical, 4)
                    HStack {
                        Text(L10n.t("النتيجة", "Result"))
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        CopyButton(text: result)
                        ShareLink(item: result) {
                            Label(L10n.t("مشاركة", "Share"), systemImage: "square.and.arrow.up")
                        }
                    }
                    SelectableText(text: result)
                    AskAboutResultLink(text: result)
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
        .navigationTitle(title)
        .sheet(isPresented: $showDocPicker) {
            DocumentPicker(types: DocumentText.importTypes) { url in
                guard let url else { return }
                Task {
                    isLoading = true
                    errorMessage = nil
                    let text = await DocumentText.extractTextAsync(from: url)
                    isLoading = false
                    if let text, !text.isEmpty {
                        input = text
                    } else {
                        errorMessage = L10n.t("لم أتمكن من استخراج نص قابل للقراءة من هذا الملف.",
                                              "I couldn't extract readable text from this file.")
                    }
                }
            }
        }
    }

    private func run() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        result = ""
        ProcessingFeedback.start()
        defer { isLoading = false }
        do {
            result = try await AiProviderFactory.current().ask(
                task: .ask,
                input: text,
                instruction: instruction,
                language: BasirSettings.shared.language,
                imageData: nil,
                mimeType: nil
            )
            ProcessingFeedback.done()
            UIAccessibility.post(notification: .announcement,
                                 argument: L10n.t("النتيجة جاهزة.", "Your result is ready."))
        } catch {
            errorMessage = UserFriendlyErrorMapper.map(error)
            ProcessingFeedback.failed()
        }
    }
}
