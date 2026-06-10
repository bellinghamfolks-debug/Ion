import SwiftUI
import PhotosUI

struct MathExtractView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var resultText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCamera = false
    @State private var lastImageData: Data?

    var body: some View {
        BasirScreen {
            BasirPageIntro(
                text: L10n.t(
                    "صوّر الصفحة كاملة وبشكل مستقيم. سيستخرج بصير المعادلات ويعرض طريقة نطقها، ثم يضيف صيغة LaTeX للمراجعة أو النسخ.",
                    "Capture the full page as straight as possible. Basir extracts each equation, explains how to read it aloud, and adds LaTeX for review or copying."
                )
            )

            if CameraPicker.isAvailable {
                Button { showCamera = true } label: {
                    Label(L10n.t("تصوير المعادلات الآن", "Photograph equations now"),
                          systemImage: "camera.fill")
                }
                .buttonStyle(BasirPrimaryButtonStyle())
                .disabled(isLoading)
            }

            if CameraPicker.isAvailable {
                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    Label(L10n.t("اختيار صورة من المكتبة", "Choose an image from Photos"),
                          systemImage: "photo.on.rectangle.angled")
                }
                .buttonStyle(BasirSecondaryButtonStyle())
                .disabled(isLoading)
            } else {
                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    Label(L10n.t("اختيار صورة من المكتبة", "Choose an image from Photos"),
                          systemImage: "photo.on.rectangle.angled")
                }
                .buttonStyle(BasirPrimaryButtonStyle())
                .disabled(isLoading)
            }

            if isLoading {
                BasirStatusBanner(
                    text: L10n.t("جاري استخراج المعادلات وتحويلها إلى صيغة قابلة للقراءة.",
                                 "Extracting equations and converting them into a readable format."),
                    tone: .info
                )
            }

            if let errorMessage {
                BasirStatusBanner(text: errorMessage, tone: .danger)
            }

            if !resultText.isEmpty {
                BasirResultCard(title: L10n.t("المعادلات المستخرجة", "Extracted equations"), text: resultText) {
                    HStack(spacing: 4) {
                        CopyButton(text: resultText)
                        ShareLink(item: resultText) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(BasirIconButtonStyle())
                        .accessibilityLabel(L10n.t("مشاركة المعادلات", "Share equations"))
                    }
                }
                AskAboutResultLink(text: resultText, imageData: lastImageData)
                BasirStatusBanner(
                    text: L10n.t("قارن الرموز والأسس والإشارات بالصورة الأصلية، خصوصًا في المعادلات المكتوبة بخط اليد.",
                                 "Compare symbols, exponents, and signs with the source image, especially for handwritten equations."),
                    tone: .warning
                )
            }
        }
        .navigationTitle(L10n.t("قراءة المعادلات", "Read equations"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw GeminiError.decode("could not open image")
                    }
                    await runExtraction(data: data)
                } catch {
                    errorMessage = UserFriendlyErrorMapper.map(error)
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in
                showCamera = false
                if let data { Task { await runExtraction(data: data) } }
            }
            .ignoresSafeArea()
        }
    }

    private func runExtraction(data: Data) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        resultText = ""
        defer { isLoading = false }

        do {
            guard let compressed = await Task.detached(priority: .userInitiated, operation: {
                ImagePreprocessor.jpeg(from: data)
            }).value else {
                throw GeminiError.decode("image could not be prepared safely")
            }
            lastImageData = compressed
            let isEnglish = BasirSettings.shared.language == .english
            let response = try await AiProviderFactory.current().ask(
                task: .mathExtract,
                input: "",
                instruction: GeminiPrompts.mathLatexInstruction(english: isEnglish),
                language: BasirSettings.shared.language,
                imageData: compressed,
                mimeType: "image/jpeg"
            )
            resultText = LatexToSpeech.renderDocument(response, arabic: !isEnglish)
            UIAccessibility.post(notification: .announcement, argument: BasirCopy.resultReady)
        } catch {
            errorMessage = UserFriendlyErrorMapper.map(error)
        }
    }
}
