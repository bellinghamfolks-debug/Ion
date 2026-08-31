import Foundation
import Combine

enum BundledServerConfiguration {
    static func current(bundle: Bundle = .main) -> ServerConfiguration {
        ServerConfiguration(
            baseURL: bundle.object(forInfoDictionaryKey: "BasirServerURL") as? String ?? "",
            clientToken: bundle.object(forInfoDictionaryKey: "BasirClientToken") as? String ?? ""
        )
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    private enum Key {
        static let outputMode = "convert_output_mode"
        static let embedVisuals = "convert_embed_visuals"
        static let includeMath = "convert_include_math"
        static let preserveSymbols = "convert_preserve_symbols"
        static let targetLanguage = "translate_target_language"
        static let pdfQuality = "pdf_quality"
        static let pageSelection = "pdf_page_selection"
        static let includeSpeakerNotes = "include_speaker_notes"
        static let includeHiddenSlides = "include_hidden_slides"
        static let preserveLinks = "preserve_links"
        static let wifiOnly = "network_wifi_only"
        static let allowLowData = "network_allow_low_data"
        static let automaticResume = "jobs_automatic_resume"
        static let soundTheme = "operation_sound_theme"
        static let notificationsEnabled = "completion_notifications"
        static let skipBlankPages = "skip_blank_pages"
        static let preferPDFText = "prefer_pdf_text_layer"
        static let concurrentPages = "concurrent_pdf_pages"
        static let rotationCorrection = "pdf_rotation_correction"
        static let preferredModel = "ai_preferred_model"
    }

    private let bundledConfiguration: ServerConfiguration

    @Published var outputMode: OutputMode
    @Published var embedVisuals: Bool
    @Published var includeMath: Bool
    @Published var preserveSymbols: Bool
    @Published var targetLanguageCode: String
    @Published var pdfQuality: PDFQuality
    @Published var pageSelection: String
    @Published var includeSpeakerNotes: Bool
    @Published var includeHiddenSlides: Bool
    @Published var preserveLinks: Bool
    @Published var wifiOnly: Bool
    @Published var allowLowData: Bool
    @Published var automaticResume: Bool
    @Published var soundTheme: SoundTheme
    @Published var notificationsEnabled: Bool
    @Published var skipBlankPages: Bool
    @Published var preferPDFText: Bool
    @Published var concurrentPages: Int
    @Published var rotationCorrection: Int
    @Published var preferredModel: AIModelChoice

    init(
        defaults: UserDefaults = .standard,
        configuration: ServerConfiguration = BundledServerConfiguration.current()
    ) {
        bundledConfiguration = configuration
        outputMode = OutputMode(rawValue: defaults.string(forKey: Key.outputMode) ?? "full") ?? .full
        embedVisuals = defaults.object(forKey: Key.embedVisuals) == nil
            ? true : defaults.bool(forKey: Key.embedVisuals)
        includeMath = defaults.bool(forKey: Key.includeMath)
        preserveSymbols = defaults.object(forKey: Key.preserveSymbols) == nil
            ? true : defaults.bool(forKey: Key.preserveSymbols)
        targetLanguageCode = defaults.string(forKey: Key.targetLanguage) ?? "en"
        pdfQuality = PDFQuality(rawValue: defaults.string(forKey: Key.pdfQuality) ?? "balanced") ?? .balanced
        pageSelection = defaults.string(forKey: Key.pageSelection) ?? ""
        includeSpeakerNotes = defaults.object(forKey: Key.includeSpeakerNotes) == nil
            ? true : defaults.bool(forKey: Key.includeSpeakerNotes)
        includeHiddenSlides = defaults.bool(forKey: Key.includeHiddenSlides)
        preserveLinks = defaults.object(forKey: Key.preserveLinks) == nil
            ? true : defaults.bool(forKey: Key.preserveLinks)
        wifiOnly = defaults.bool(forKey: Key.wifiOnly)
        allowLowData = defaults.bool(forKey: Key.allowLowData)
        automaticResume = defaults.object(forKey: Key.automaticResume) == nil
            ? true : defaults.bool(forKey: Key.automaticResume)
        soundTheme = SoundTheme(rawValue: defaults.string(forKey: Key.soundTheme) ?? "gentle") ?? .gentle
        notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled) == nil
            ? true : defaults.bool(forKey: Key.notificationsEnabled)
        skipBlankPages = defaults.object(forKey: Key.skipBlankPages) == nil
            ? true : defaults.bool(forKey: Key.skipBlankPages)
        preferPDFText = defaults.object(forKey: Key.preferPDFText) == nil
            ? true : defaults.bool(forKey: Key.preferPDFText)
        concurrentPages = max(1, min(3, defaults.object(forKey: Key.concurrentPages) == nil
                                    ? 3 : defaults.integer(forKey: Key.concurrentPages)))
        let savedRotation = defaults.integer(forKey: Key.rotationCorrection)
        rotationCorrection = [0, 90, 180, 270].contains(savedRotation) ? savedRotation : 0

        let storedModel = AIModelChoice(
            rawValue: defaults.string(forKey: Key.preferredModel) ?? "auto"
        ) ?? .automatic
        switch storedModel {
        case .economy, .pro:
            // Retired preview/lite selections from older app versions must not
            // remain as an invisible Picker value or be sent to the current
            // Vertex conversion engine. Migrate the persisted preference once.
            preferredModel = .flash
            defaults.set(AIModelChoice.flash.rawValue, forKey: Key.preferredModel)
        case .automatic, .flash:
            preferredModel = storedModel
        }
    }

    var targetLanguage: SupportedLanguage {
        SupportedLanguage.language(code: targetLanguageCode)
    }

    var configuration: ServerConfiguration { bundledConfiguration }
    var isConfigured: Bool { bundledConfiguration.isConfigured }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(outputMode.rawValue, forKey: Key.outputMode)
        defaults.set(embedVisuals, forKey: Key.embedVisuals)
        defaults.set(includeMath, forKey: Key.includeMath)
        defaults.set(preserveSymbols, forKey: Key.preserveSymbols)
        defaults.set(targetLanguageCode, forKey: Key.targetLanguage)
        defaults.set(pdfQuality.rawValue, forKey: Key.pdfQuality)
        defaults.set(pageSelection.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.pageSelection)
        defaults.set(includeSpeakerNotes, forKey: Key.includeSpeakerNotes)
        defaults.set(includeHiddenSlides, forKey: Key.includeHiddenSlides)
        defaults.set(preserveLinks, forKey: Key.preserveLinks)
        defaults.set(wifiOnly, forKey: Key.wifiOnly)
        defaults.set(allowLowData, forKey: Key.allowLowData)
        defaults.set(automaticResume, forKey: Key.automaticResume)
        defaults.set(soundTheme.rawValue, forKey: Key.soundTheme)
        defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled)
        defaults.set(skipBlankPages, forKey: Key.skipBlankPages)
        defaults.set(preferPDFText, forKey: Key.preferPDFText)
        defaults.set(max(1, min(3, concurrentPages)), forKey: Key.concurrentPages)
        defaults.set(rotationCorrection, forKey: Key.rotationCorrection)
        defaults.set(preferredModel.serverModelID, forKey: Key.preferredModel)
    }
}
