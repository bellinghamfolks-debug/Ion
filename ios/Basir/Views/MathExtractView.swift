// MathExtractView.swift
// Math extraction. Photograph a textbook page, a whiteboard, or
// handwritten equations; Basir returns each expression in spoken
// Arabic / English followed by the LaTeX source.
//
// Economical pipeline (ports Android v3.0): Gemini emits ONLY compact
// LaTeX (small output, deterministic, cheaper) and the spoken Arabic /
// English form is rendered on-device by LatexToSpeech. See
// GeminiPrompts.mathLatexInstruction + LatexToSpeech.renderDocument.

import SwiftUI
import PhotosUI

struct MathExtractView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var resultText: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.t(
                    "صوّر معادلات من ورقة أو سبورة أو كتاب. سيعرضها بصير بصيغة منطوقة، ويضيف LaTeX للمراجعة.",
                    "Photograph equations on a page, whiteboard, or textbook. Basir presents them in spoken form and adds LaTeX for review."
                ))
                .font(.callout)
                .foregroundStyle(.secondary)

                PhotosPicker(
                    selection: $pickerItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text(L10n.t("التقاط أو اختيار صورة",
                                     "Take or pick an image"))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityLabel(L10n.t(
                    "اختيار صورة لقراءة المعادلات",
                    "Choose an image to analyze equations"
                ))

                if isLoading {
                    HStack {
                        ProgressView()
                        Text(L10n.t("أقرأ المعادلات...",
                                     "Reading equations..."))
                    }
                    .padding(.top, 8)
                }

                if !resultText.isEmpty {
                    Divider().padding(.vertical, 8)
                    Text(L10n.t("النتيجة", "Result"))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    SelectableText(text: resultText)
                    CopyButton(text: resultText)
                    AskAboutResultLink(text: resultText)
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
        .navigationTitle(L10n.t("قراءة معادلات من صورة", "Read equations from an image"))
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await runExtraction(item: item) }
        }
    }

    private func runExtraction(item: PhotosPickerItem) async {
        isLoading = true
        errorMessage = nil
        resultText = ""
        defer { isLoading = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw GeminiError.decode(L10n.t(
                    "لم أتمكن من فتح الصورة.",
                    "I couldn't open the image."
                ))
            }
            // Compress to ~1600px long edge + JPEG quality 85 — matches
            // the Android ImageCompressor and the same Gemini cost win.
            let compressed = compressForAi(data: data) ?? data
            let mime = "image/jpeg"
            let isEnglish = BasirSettings.shared.language == .english
            // Economical: the model returns ONLY compact LaTeX; we render
            // the spoken Arabic / English on-device with LatexToSpeech.
            // Smaller output tokens + a deterministic local read.
            let instruction = GeminiPrompts.mathLatexInstruction(english: isEnglish)
            let response = try await AiProviderFactory.current().ask(
                task: .mathExtract,
                input: "",
                instruction: instruction,
                language: BasirSettings.shared.language,
                imageData: compressed,
                mimeType: mime
            )
            resultText = LatexToSpeech.renderDocument(
                response, arabic: !isEnglish)
            UIAccessibility.post(notification: .announcement,
                                  argument: L10n.t("اكتمل تحليل الرياضيات.",
                                                    "Math analysis complete."))
        } catch {
            errorMessage = UserFriendlyErrorMapper.map(error)
        }
    }

    // MARK: - Image compression (port of Android ImageCompressor)

    /// Down-scales the long edge to 1600 px and re-encodes as JPEG 85.
    /// Returns nil if decoding fails (caller falls back to raw data).
    private func compressForAi(data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxLongEdge: CGFloat = 1600
        let w = image.size.width, h = image.size.height
        let longEdge = max(w, h)
        guard longEdge > 0 else { return nil }
        let scale = min(1.0, maxLongEdge / longEdge)
        let newSize = CGSize(width: w * scale, height: h * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return scaled.jpegData(compressionQuality: 0.85)
    }
}
