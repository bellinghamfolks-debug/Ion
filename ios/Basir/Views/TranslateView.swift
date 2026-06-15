import SwiftUI
import UniformTypeIdentifiers

struct TranslateView: View {
    @EnvironmentObject var settings: BasirSettings
    @State private var inputText = ""
    @State private var translation = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showDocPicker = false

    private let allLanguages = L10n.supportedTranslationLanguages
    private var targetLanguages: [(code: String, ar: String, en: String)] {
        allLanguages.filter { $0.code != "auto" }
    }

    var body: some View {
        BasirScreen {
            BasirPageIntro(
                text: L10n.t(
                    "اختر لغة النص ولغة الترجمة. يمكنك لصق النص أو استيراده من ملف، ثم مراجعة النتيجة قبل استخدامها.",
                    "Choose the source and target languages. Paste text or import it from a file, then review the result before using it."
                )
            )

            languageCard

            Button {
                showDocPicker = true
            } label: {
                Label(L10n.t("استيراد نص من ملف", "Import text from a file"),
                      systemImage: "doc.badge.plus")
            }
            .buttonStyle(BasirSecondaryButtonStyle())
            .disabled(isLoading)

            BasirTextEditor(
                title: L10n.t("النص المراد ترجمته", "Text to translate"),
                placeholder: L10n.t("اكتب النص أو الصقه هنا.", "Type or paste text here."),
                text: $inputText,
                minimumHeight: 170,
                characterLimit: 20_000
            )

            Button {
                Task { await translate() }
            } label: {
                HStack(spacing: 10) {
                    if isLoading { ProgressView().tint(.white) }
                    Label(
                        isLoading ? L10n.t("جاري الترجمة", "Translating")
                                  : L10n.t("ترجمة النص", "Translate text"),
                        systemImage: "character.book.closed.fill"
                    )
                }
            }
            .buttonStyle(BasirPrimaryButtonStyle())
            .disabled(isLoading || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let errorMessage {
                BasirStatusBanner(text: errorMessage, tone: .danger)
            }

            if !translation.isEmpty {
                BasirResultCard(title: L10n.t("الترجمة", "Translation"), text: translation) {
                    HStack(spacing: 4) {
                        CopyButton(text: translation)
                        ShareLink(item: translation) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(BasirIconButtonStyle())
                        .accessibilityLabel(L10n.t("مشاركة الترجمة", "Share translation"))
                    }
                }
                AskAboutResultLink(text: translation)
                BasirStatusBanner(text: BasirCopy.verifyImportantInformation, tone: .warning)
            }
        }
        .navigationTitle(L10n.t("الترجمة", "Translation"))
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
                        inputText = try await DocumentText.extractTextAsync(from: url)
                    } catch {
                        errorMessage = UserFriendlyErrorMapper.map(error)
                    }
                }
            }
        }
    }

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            BasirSectionHeader(
                title: L10n.t("اللغات", "Languages"),
                subtitle: L10n.t("يمكن لبصير اكتشاف لغة النص تلقائيًا.",
                                 "Basir can detect the source language automatically.")
            )

            Picker(L10n.t("لغة النص", "Source language"), selection: $settings.translateSource) {
                ForEach(allLanguages, id: \.code) { lang in
                    Text(settings.language == .arabic ? lang.ar : lang.en).tag(lang.code)
                }
            }
            .pickerStyle(.menu)

            Picker(L10n.t("لغة الترجمة", "Target language"), selection: $settings.translateTarget) {
                ForEach(targetLanguages, id: \.code) { lang in
                    Text(settings.language == .arabic ? lang.ar : lang.en).tag(lang.code)
                }
            }
            .pickerStyle(.menu)

            Button {
                swapLanguages()
            } label: {
                Label(L10n.t("تبديل اللغتين", "Swap languages"),
                      systemImage: "arrow.up.arrow.down")
            }
            .buttonStyle(BasirSecondaryButtonStyle(tone: .info))
        }
        .basirCardSurface()
    }

    private func swapLanguages() {
        let oldSource = settings.translateSource
        let oldTarget = settings.translateTarget
        guard oldSource != "auto" else {
            UIAccessibility.post(
                notification: .announcement,
                argument: L10n.t(
                    "اختر لغة محددة للنص قبل تبديل اللغتين.",
                    "Choose a specific source language before swapping."
                )
            )
            return
        }
        settings.translateSource = oldTarget
        settings.translateTarget = oldSource
        UIAccessibility.post(
            notification: .announcement,
            argument: L10n.t("تم تبديل اللغتين.", "Languages swapped.")
        )
    }

    private func translate() async {
        guard !isLoading else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        translation = ""
        defer { isLoading = false }

        let instruction = GeminiPrompts.translateInstruction(
            sourceCode: settings.translateSource,
            targetCode: settings.translateTarget
        )

        do {
            translation = try await AiProviderFactory.current().ask(
                task: .translate,
                input: text,
                instruction: instruction,
                language: settings.language,
                imageData: nil,
                mimeType: nil
            )
            UIAccessibility.post(notification: .announcement, argument: BasirCopy.resultReady)
        } catch {
            errorMessage = UserFriendlyErrorMapper.map(error)
        }
    }
}
