import SwiftUI
import UIKit

struct SharedItemView: View {
    let incoming: ShareInbox.Incoming
    @Environment(\.dismiss) private var dismiss

    @State private var result = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var preparedImageData: Data?
    @State private var sharedText: String?

    private var isImage: Bool {
        ["jpg", "jpeg", "png", "heic", "heif", "gif"].contains(incoming.fileExtension)
    }
    private var isText: Bool { incoming.fileExtension == "txt" }
    private var isDocument: Bool { incoming.fileExtension == "pdf" }

    var body: some View {
        NavigationStack {
            BasirScreen {
                BasirPageIntro(
                    text: L10n.t(
                        "وصل هذا المحتوى من تطبيق آخر. راجع الاسم والمعاينة، ثم اختر الإجراء المناسب.",
                        "This content came from another app. Review the name and preview, then choose the appropriate action."
                    )
                )

                preview

                if isDocument {
                    NavigationLink {
                        DocumentConvertView(initialURL: incoming.fileURL)
                    } label: {
                        Label(L10n.t("فتح أداة تحويل المستند", "Open document conversion"),
                              systemImage: "doc.badge.gearshape.fill")
                    }
                    .buttonStyle(BasirPrimaryButtonStyle())
                } else if isImage || isText {
                    Button { Task { await run() } } label: {
                        HStack(spacing: 10) {
                            if isLoading { ProgressView().tint(.white) }
                            Label(isLoading ? L10n.t("جاري تجهيز النتيجة", "Preparing result") : actionTitle,
                                  systemImage: isImage ? "photo.fill" : "sparkles")
                        }
                    }
                    .buttonStyle(BasirPrimaryButtonStyle())
                    .disabled(isLoading || (isImage && preparedImageData == nil) || (isText && sharedText == nil))
                }

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
                    AskAboutResultLink(text: result, imageData: preparedImageData)
                }
            }
            .navigationTitle(L10n.t("فتح في بصير", "Open in Basir"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("إغلاق", "Close")) {
                        ShareInbox.shared.clear(incoming)
                        dismiss()
                    }
                }
            }
            .task { await prepareSharedContent() }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if isImage, let data = preparedImageData, let image = UIImage(data: data) {
            VStack(alignment: .leading, spacing: 10) {
                BasirSectionHeader(title: L10n.t("معاينة الصورة", "Image preview"))
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: BasirTheme.controlRadius))
                    .accessibilityLabel(L10n.t(
                        "معاينة للصورة المستلمة. استخدم زر وصف الصورة للحصول على وصف نصي.",
                        "Preview of the received image. Use Describe image for a text description."
                    ))
            }
            .basirCardSurface()
        } else if isText, let sharedText {
            VStack(alignment: .leading, spacing: 10) {
                BasirSectionHeader(title: L10n.t("النص المستلم", "Received text"))
                SelectableText(text: String(sharedText.prefix(4_000)))
            }
            .basirCardSurface()
        } else if isDocument {
            BasirInfoRow(
                label: L10n.t("ملف PDF مستلم", "Received PDF"),
                value: incoming.fileURL.lastPathComponent,
                systemImage: "doc.richtext.fill"
            )
        } else {
            BasirStatusBanner(
                text: L10n.t("صيغة هذا الملف غير مدعومة في المشاركة المباشرة.",
                             "This file format is not supported through direct sharing."),
                tone: .warning
            )
        }
    }

    private var actionTitle: String {
        isImage ? L10n.t("وصف الصورة", "Describe image")
                : L10n.t("تحليل النص", "Analyze text")
    }

    private func prepareSharedContent() async {
        if isImage {
            preparedImageData = await Task.detached(priority: .userInitiated) {
                ImagePreprocessor.jpeg(fromFileURL: incoming.fileURL)
            }.value
            if preparedImageData == nil {
                errorMessage = L10n.t("تعذّر فتح الصورة المستلمة.",
                                      "The received image could not be opened.")
            }
        } else if isText {
            let text = await Task.detached(priority: .userInitiated) { () -> String? in
                guard let values = try? incoming.fileURL.resourceValues(forKeys: [.fileSizeKey]),
                      (values.fileSize ?? 0) <= 2 * 1_024 * 1_024 else { return nil }
                return try? String(contentsOf: incoming.fileURL, encoding: .utf8)
            }.value
            guard let text else {
                errorMessage = L10n.t("تعذّرت قراءة النص المستلم، أو كان حجمه أكبر من الحد المسموح.",
                                      "The received text could not be read or exceeded the allowed size.")
                return
            }
            sharedText = text
        }
    }

    private func run() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        result = ""
        defer { isLoading = false }

        let language = BasirSettings.shared.language
        do {
            if isImage, let preparedImageData {
                result = try await AiProviderFactory.current().ask(
                    task: .describeImage,
                    input: "",
                    instruction: GeminiPrompts.imageTaskInstruction(.describeImage, english: language == .english),
                    language: language,
                    imageData: preparedImageData,
                    mimeType: "image/jpeg"
                )
            } else if isText, let sharedText {
                result = try await AiProviderFactory.current().ask(
                    task: .ask,
                    input: sharedText,
                    instruction: GeminiPrompts.generalAskInstruction,
                    language: language,
                    imageData: nil,
                    mimeType: nil
                )
            } else {
                errorMessage = L10n.t("تعذّر تجهيز المحتوى المستلم.",
                                      "The received content could not be prepared.")
                return
            }
            UIAccessibility.post(notification: .announcement, argument: BasirCopy.resultReady)
        } catch {
            errorMessage = UserFriendlyErrorMapper.map(error)
        }
    }
}
