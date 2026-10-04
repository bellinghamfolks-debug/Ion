import SwiftUI
import PhotosUI
import Vision
import UIKit

/// "Explain any text": photograph a sign, a page or a message, pick a photo,
/// or paste text. Text is read on the device with Vision; only the text you
/// confirm is sent to the tutor for the explanation.
struct ExplainTextView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession

    @State private var text = ""
    @State private var result: ExplainTextResult?
    @State private var loading = false
    @State private var recognizing = false
    @State private var errorMessage: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var savedTerms: Set<String> = []

    private let service = AIStudioService()
    private let maximumCharacters = 3000

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                InfoCard(title: LE("اشرح أي نص", "Explain any text"), systemImage: "text.viewfinder") {
                    Text(LE("صوّر لافتة أو صفحة أو رسالة، أو اختر صورة، أو الصق نصًا. تُقرأ الصورة على جهازك، ثم يُرسل النص فقط للشرح.",
                            "Photograph a sign, a page or a message, pick a photo, or paste text. The photo is read on your device; only the text is sent for the explanation."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { sourceButtons }
                        VStack(spacing: 10) { sourceButtons }
                    }

                    if recognizing {
                        ProgressView(LE("جارٍ قراءة النص من الصورة", "Reading text from the photo"))
                    }

                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                        .environment(\.layoutDirection, .leftToRight)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel(LE("النص المراد شرحه", "Text to explain"))
                        .onChange(of: text) { _, newValue in
                            if newValue.count > maximumCharacters { text = String(newValue.prefix(maximumCharacters)) }
                        }

                    HStack {
                        Text(LfE("%@ / %@ حرف", "%@ / %@ characters", "\(text.count)", "\(maximumCharacters)"))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !trimmed.isEmpty {
                            Button {
                                container.textToSpeech.speak(trimmed)
                            } label: {
                                Label(LE("استمع", "Listen"), systemImage: "speaker.wave.2.fill")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    PrimaryButton(title: LE("اشرح النص", "Explain the text"), systemImage: "sparkles",
                                  isLoading: loading, isDisabled: trimmed.isEmpty) { explain() }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let result { resultCards(result) }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle(LE("اشرح أي نص", "Explain any text"))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in recognize(image) }
                .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    recognize(image)
                } else {
                    errorMessage = LE("تعذر فتح الصورة.", "Couldn't open the photo.")
                }
                photoItem = nil
            }
        }
    }

    @ViewBuilder
    private var sourceButtons: some View {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            Button { showCamera = true } label: {
                Label(LE("صوّر نصًا", "Photograph text"), systemImage: "camera.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        PhotosPicker(selection: $photoItem, matching: .images) {
            Label(LE("اختر صورة", "Choose photo"), systemImage: "photo.on.rectangle")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        Button {
            if let pasted = UIPasteboard.general.string, !pasted.isEmpty {
                text = String(pasted.prefix(maximumCharacters))
                result = nil
            } else {
                errorMessage = LE("لا يوجد نص منسوخ.", "There is no copied text.")
            }
        } label: {
            Label(LE("الصق", "Paste"), systemImage: "doc.on.clipboard")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func resultCards(_ result: ExplainTextResult) -> some View {
        if !result.summaryAr.isEmpty {
            InfoCard(title: LE("الفكرة باختصار", "In short"), systemImage: "text.alignright", tint: AppTheme.accentTeal) {
                Text(result.summaryAr)
            }
        }
        if !result.translationAr.isEmpty {
            InfoCard(title: LE("الترجمة", "Translation"), systemImage: "character.bubble.fill", tint: AppTheme.brand) {
                Text(result.translationAr).textSelection(.enabled)
            }
        }
        if let simple = result.simplifiedEn, !simple.isEmpty {
            InfoCard(title: LfE("بإنجليزية أبسط (%@)", "In simpler English (%@)", session.selectedLevel.rawValue),
                     systemImage: "textformat.size.smaller", tint: AppTheme.success) {
                Text(simple)
                    .environment(\.layoutDirection, .leftToRight)
                    .textSelection(.enabled)
                Button {
                    container.textToSpeech.speak(simple)
                } label: {
                    Label(LE("استمع", "Listen"), systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        if !result.vocabulary.isEmpty {
            InfoCard(title: LE("كلمات مفيدة", "Useful words"), systemImage: "character.book.closed.fill", tint: AppTheme.warning) {
                ForEach(result.vocabulary) { item in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.term).font(.headline).environment(\.layoutDirection, .leftToRight)
                            Text(item.meaningAr).foregroundStyle(.secondary)
                            if let example = item.exampleEn, !example.isEmpty {
                                Text(example).font(.caption).environment(\.layoutDirection, .leftToRight)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        Spacer(minLength: 6)
                        Button {
                            save(item)
                        } label: {
                            Image(systemName: savedTerms.contains(item.term) ? "checkmark.circle.fill" : "plus.circle")
                                .font(.title3)
                        }
                        .disabled(savedTerms.contains(item.term))
                        .accessibilityLabel(savedTerms.contains(item.term)
                                            ? LfE("%@ محفوظة في دفتر المفردات", "%@ saved to your wordbook", item.term)
                                            : LfE("احفظ %@ في دفتر المفردات", "Save %@ to your wordbook", item.term))
                    }
                    if item.id != result.vocabulary.last?.id { Divider() }
                }
            }
        }
        if !result.grammar.isEmpty {
            InfoCard(title: LE("قواعد في النص", "Grammar in the text"), systemImage: "function", tint: AppTheme.brandSecondary) {
                ForEach(result.grammar) { point in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(point.pointAr)
                        if let example = point.exampleEn, !example.isEmpty {
                            Text(example).font(.callout.weight(.semibold)).environment(\.layoutDirection, .leftToRight)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func recognize(_ image: UIImage) {
        errorMessage = nil
        result = nil
        recognizing = true
        Task {
            let recognized = await TextRecognizer.recognize(image)
            recognizing = false
            if recognized.isEmpty {
                errorMessage = LE("لم يُعثر على نص واضح في الصورة. جرّب صورة أقرب وإضاءة أفضل.",
                                  "No clear text found. Try a closer photo with better light.")
            } else {
                text = String(recognized.prefix(maximumCharacters))
                AccessibilityNotification.Announcement(LE("قُرئ النص. راجعه ثم اضغط اشرح النص.", "Text read. Check it, then tap Explain the text.")).post()
            }
        }
    }

    private func explain() {
        let value = trimmed
        guard !value.isEmpty, !loading else { return }
        loading = true
        errorMessage = nil
        Task {
            do {
                result = try await service.explainText(value, level: session.selectedLevel.rawValue)
                AccessibilityNotification.Announcement(LE("الشرح جاهز.", "The explanation is ready.")).post()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? LE("تعذر شرح النص.", "Couldn't explain the text.")
            }
            loading = false
        }
    }

    private func save(_ item: ExplainTextVocabulary) {
        let slug = item.term.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }.replacingOccurrences(of: " ", with: "-")
        let word = VocabularyWord(
            id: "explain-\(slug)",
            english: item.term,
            arabic: item.meaningAr,
            example: item.exampleEn ?? "",
            exampleArabic: "",
            partOfSpeech: "",
            phonetic: nil
        )
        savedTerms.insert(item.term)
        Task { await container.vocabularyRepository.add(words: [word]) }
        ToastCenter.shared.show(LfE("حُفظت «%@» في دفتر المفردات", "Saved “%@” to your wordbook", item.term))
    }
}

/// On-device text recognition with Vision (no network).
enum TextRecognizer {
    static func recognize(_ image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) {
            // Read results after `perform` instead of in a completion handler,
            // so a failure can never resume twice.
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]
            do {
                try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
            } catch {
                return ""
            }
            return (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
