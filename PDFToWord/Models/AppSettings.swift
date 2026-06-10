import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let customModelIdentifier = "__custom__"
    private let defaults: UserDefaults

    private enum Key {
        static let model = "settings.model"
        static let customModel = "settings.customModel"
        static let thinkingLevel = "settings.thinkingLevel"
        static let describeImages = "settings.describeImages"
        static let embedImages = "settings.embedImages"
        static let includeDecorativeImages = "settings.includeDecorativeImages"
        static let showImageDescriptions = "settings.showImageDescriptions"
        static let preserveHeadersAndFooters = "settings.preserveHeadersAndFooters"
        static let preservePageBreaks = "settings.preservePageBreaks"
        static let preservePageSizeAndOrientation = "settings.preservePageSizeAndOrientation"
        static let addPageNumbers = "settings.addPageNumbers"
        static let bodyFontArabic = "settings.bodyFontArabic"
        static let bodyFontLatin = "settings.bodyFontLatin"
        static let bodyFontSize = "settings.bodyFontSize"
        static let headingFontSize = "settings.headingFontSize"
        static let pageMarginPoints = "settings.pageMarginPoints"
        static let concurrency = "settings.concurrency"
        static let retryCount = "settings.retryCount"
        static let useNativeTextFallback = "settings.useNativeTextFallback"
        static let strictCompletenessCheck = "settings.strictCompletenessCheck"
        static let minimumCoverageRatio = "settings.minimumCoverageRatio"
        static let promptAddendum = "settings.promptAddendum"
    }

    let availableModels = [
        "gemini-3.5-flash",
        "gemini-3.1-flash-lite",
        "gemini-3.1-pro-preview",
        AppSettings.customModelIdentifier
    ]

    @Published var model: String { didSet { save(model, Key.model) } }
    @Published var customModel: String { didSet { save(customModel, Key.customModel) } }
    @Published var thinkingLevel: String { didSet { save(thinkingLevel, Key.thinkingLevel) } }
    @Published var describeImages: Bool { didSet { save(describeImages, Key.describeImages) } }
    @Published var embedImages: Bool { didSet { save(embedImages, Key.embedImages) } }
    @Published var includeDecorativeImages: Bool { didSet { save(includeDecorativeImages, Key.includeDecorativeImages) } }
    @Published var showImageDescriptions: Bool { didSet { save(showImageDescriptions, Key.showImageDescriptions) } }
    @Published var preserveHeadersAndFooters: Bool { didSet { save(preserveHeadersAndFooters, Key.preserveHeadersAndFooters) } }
    @Published var preservePageBreaks: Bool { didSet { save(preservePageBreaks, Key.preservePageBreaks) } }
    @Published var preservePageSizeAndOrientation: Bool { didSet { save(preservePageSizeAndOrientation, Key.preservePageSizeAndOrientation) } }
    @Published var addPageNumbers: Bool { didSet { save(addPageNumbers, Key.addPageNumbers) } }
    @Published var bodyFontArabic: String { didSet { save(bodyFontArabic, Key.bodyFontArabic) } }
    @Published var bodyFontLatin: String { didSet { save(bodyFontLatin, Key.bodyFontLatin) } }
    @Published var bodyFontSize: Double { didSet { save(bodyFontSize, Key.bodyFontSize) } }
    @Published var headingFontSize: Double { didSet { save(headingFontSize, Key.headingFontSize) } }
    @Published var pageMarginPoints: Double { didSet { save(pageMarginPoints, Key.pageMarginPoints) } }
    @Published var concurrency: Int { didSet { save(concurrency, Key.concurrency) } }
    @Published var retryCount: Int { didSet { save(retryCount, Key.retryCount) } }
    @Published var useNativeTextFallback: Bool { didSet { save(useNativeTextFallback, Key.useNativeTextFallback) } }
    @Published var strictCompletenessCheck: Bool { didSet { save(strictCompletenessCheck, Key.strictCompletenessCheck) } }
    @Published var minimumCoverageRatio: Double { didSet { save(minimumCoverageRatio, Key.minimumCoverageRatio) } }
    @Published var promptAddendum: String { didSet { save(promptAddendum, Key.promptAddendum) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedModel = defaults.string(forKey: Key.model) ?? "gemini-3.5-flash"
        model = storedModel == "مخصص" ? Self.customModelIdentifier : storedModel
        customModel = defaults.string(forKey: Key.customModel) ?? ""
        thinkingLevel = defaults.string(forKey: Key.thinkingLevel) ?? "high"
        describeImages = defaults.object(forKey: Key.describeImages) as? Bool ?? true
        embedImages = defaults.object(forKey: Key.embedImages) as? Bool ?? true
        includeDecorativeImages = defaults.object(forKey: Key.includeDecorativeImages) as? Bool ?? false
        showImageDescriptions = defaults.object(forKey: Key.showImageDescriptions) as? Bool ?? true
        preserveHeadersAndFooters = defaults.object(forKey: Key.preserveHeadersAndFooters) as? Bool ?? true
        preservePageBreaks = defaults.object(forKey: Key.preservePageBreaks) as? Bool ?? true
        preservePageSizeAndOrientation = defaults.object(forKey: Key.preservePageSizeAndOrientation) as? Bool ?? true
        addPageNumbers = defaults.object(forKey: Key.addPageNumbers) as? Bool ?? true
        bodyFontArabic = defaults.string(forKey: Key.bodyFontArabic) ?? "Arial"
        bodyFontLatin = defaults.string(forKey: Key.bodyFontLatin) ?? "Aptos"
        bodyFontSize = defaults.object(forKey: Key.bodyFontSize) as? Double ?? 12
        headingFontSize = defaults.object(forKey: Key.headingFontSize) as? Double ?? 18
        pageMarginPoints = defaults.object(forKey: Key.pageMarginPoints) as? Double ?? 54
        concurrency = defaults.object(forKey: Key.concurrency) as? Int ?? 2
        retryCount = defaults.object(forKey: Key.retryCount) as? Int ?? 3
        useNativeTextFallback = false
        strictCompletenessCheck = defaults.object(forKey: Key.strictCompletenessCheck) as? Bool ?? true
        minimumCoverageRatio = max(0.90, defaults.object(forKey: Key.minimumCoverageRatio) as? Double ?? 0.90)
        promptAddendum = defaults.string(forKey: Key.promptAddendum) ?? ""
    }

    func displayName(forModel model: String) -> String {
        model == Self.customModelIdentifier ? L10n.text("مخصص") : model
    }

    var resolvedModel: String {
        model == Self.customModelIdentifier ? customModel.trimmingCharacters(in: .whitespacesAndNewlines) : model
    }

    var options: ConversionOptions {
        ConversionOptions(
            model: resolvedModel.isEmpty ? "gemini-3.5-flash" : resolvedModel,
            thinkingLevel: thinkingLevel,
            describeImages: describeImages,
            embedImages: embedImages,
            includeDecorativeImages: includeDecorativeImages,
            showImageDescriptions: showImageDescriptions,
            preserveHeadersAndFooters: preserveHeadersAndFooters,
            preservePageBreaks: preservePageBreaks,
            preservePageSizeAndOrientation: preservePageBreaks && preservePageSizeAndOrientation,
            addPageNumbers: addPageNumbers,
            bodyFontArabic: bodyFontArabic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Arial" : bodyFontArabic,
            bodyFontLatin: bodyFontLatin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Aptos" : bodyFontLatin,
            bodyFontSize: max(9, min(20, bodyFontSize)),
            headingFontSize: max(14, min(32, headingFontSize)),
            pageMarginPoints: max(24, min(90, pageMarginPoints)),
            concurrency: max(1, min(3, concurrency)),
            retryCount: max(0, min(6, retryCount)),
            useNativeTextFallback: false,
            strictCompletenessCheck: true,
            minimumCoverageRatio: max(0.90, min(0.98, minimumCoverageRatio)),
            promptAddendum: promptAddendum
        )
    }

    func restoreDefaults() {
        model = "gemini-3.5-flash"
        customModel = ""
        thinkingLevel = "high"
        describeImages = true
        embedImages = true
        includeDecorativeImages = false
        showImageDescriptions = true
        preserveHeadersAndFooters = true
        preservePageBreaks = true
        preservePageSizeAndOrientation = true
        addPageNumbers = true
        bodyFontArabic = "Arial"
        bodyFontLatin = "Aptos"
        bodyFontSize = 12
        headingFontSize = 18
        pageMarginPoints = 54
        concurrency = 2
        retryCount = 3
        useNativeTextFallback = false
        strictCompletenessCheck = true
        minimumCoverageRatio = 0.90
        promptAddendum = ""
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
