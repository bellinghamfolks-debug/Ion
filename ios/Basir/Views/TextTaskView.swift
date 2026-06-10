import SwiftUI
import UniformTypeIdentifiers

struct TextTaskView: View {
    let title: String
    let hint: String
    let instruction: String
    let task: TaskKind

    init(title: String, hint: String, instruction: String, task: TaskKind = .ask) {
        self.title = title
        self.hint = hint
        self.instruction = instruction
        self.task = task
    }

    @State private var input = ""
    @State private var result = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showDocPicker = false

    var body: some View {
        BasirScreen {
            BasirPageIntro(text: hint)

            Button {
                showDocPicker = true
            } label: {
                Label(L10n.t("استيراد النص من ملف", "Import text from a file"),
                      systemImage: "doc.badge.plus")
            }
            .buttonStyle(BasirSecondaryButtonStyle())
            .disabled(isLoading)

            BasirTextEditor(
                title: L10n.t("النص الأصلي", "Source text"),
                placeholder: L10n.t("ألصق النص هنا أو استورده من ملف.",
                                    "Paste the text here or import it from a file."),
                text: $input,
                minimumHeight: 170,
                characterLimit: 20_000
            )

            Button {
                Task { await run() }
            } label: {
                HStack(spacing: 10) {
                    if isLoading { ProgressView().tint(.white) }
                    Label(
                        isLoading ? L10n.t("جاري إعداد النتيجة", "Preparing result")
                                  : L10n.t("بدء المعالجة", "Start processing"),
                        systemImage: "sparkles"
                    )
                }
            }
            .buttonStyle(BasirPrimaryButtonStyle())
            .disabled(isLoading || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let errorMessage {
                BasirStatusBanner(text: errorMessage, tone: .danger)
            }

            if !result.isEmpty {
                BasirResultCard(title: L10n.t("النتيجة", "Result"), text: result) {
                    HStack(spacing: 4) {
                        CopyButton(text: result)
                        ShareLink(item: result) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(BasirIconButtonStyle())
                        .accessibilityLabel(L10n.t("مشاركة النتيجة", "Share result"))
                    }
                }
                AskAboutResultLink(text: result)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDocPicker) {
            DocumentPicker(types: DocumentText.importTypes) { url in
                guard let url else { return }
                Task {
                    guard !isLoading else { return }
                    isLoading = true
                    errorMessage = nil
                    defer { isLoading = false }
                    do {
                        input = try await DocumentText.extractTextAsync(from: url)
                        UIAccessibility.post(
                            notification: .announcement,
                            argument: L10n.t("تم إدراج نص الملف.", "The file text was inserted.")
                        )
                    } catch {
                        errorMessage = UserFriendlyErrorMapper.map(error)
                    }
                }
            }
        }
    }

    private func run() async {
        guard !isLoading else { return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        result = ""
        ProcessingFeedback.start()
        defer { isLoading = false }

        do {
            result = try await AiProviderFactory.current().ask(
                task: task,
                input: text,
                instruction: instruction,
                language: BasirSettings.shared.language,
                imageData: nil,
                mimeType: nil
            )
            ProcessingFeedback.done()
            UIAccessibility.post(notification: .announcement, argument: BasirCopy.resultReady)
        } catch {
            errorMessage = UserFriendlyErrorMapper.map(error)
            ProcessingFeedback.failed()
        }
    }
}
