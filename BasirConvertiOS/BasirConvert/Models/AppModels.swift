import Foundation
import UniformTypeIdentifiers

enum InterfaceLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case arabic = "ar"
    case english = "en"

    var id: String { rawValue }
    var isArabic: Bool { self == .arabic }
}

enum OperationKind: String, Codable, Hashable, Sendable {
    case convert
    case translate
}

enum PDFQuality: String, CaseIterable, Identifiable, Codable, Sendable {
    case fast
    case balanced
    case accurate

    var id: String { rawValue }
    var maximumLongEdge: CGFloat {
        switch self {
        case .fast: return 1_600
        case .balanced: return 2_300
        case .accurate: return 3_200
        }
    }
}

enum ImportSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case files
    case photos
    case camera
    case scanner
    case clipboard

    var id: String { rawValue }
}

enum SoundTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case off
    case gentle
    case clear
    case tactile

    var id: String { rawValue }
}

enum SupportedInput {
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp"
    ]
    static let audioExtensions: Set<String> = [
        "m4a", "mp3", "wav", "aac", "flac", "ogg", "opus", "caf", "aif", "aiff", "mp4", "mov"
    ]

    static let conversionExtensions = Set(["pdf", "pptx", "ppt"])
        .union(imageExtensions)
        .union(audioExtensions)

    static let translationExtensions = Set(["pdf", "docx", "doc", "pptx", "ppt"])
        .union(imageExtensions)

    static func operations(for url: URL) -> Set<OperationKind> {
        let extensionName = url.pathExtension.lowercased()
        var result = Set<OperationKind>()
        if conversionExtensions.contains(extensionName) { result.insert(.convert) }
        if translationExtensions.contains(extensionName) { result.insert(.translate) }
        return result
    }
}

struct ExternalImportCandidate: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let containerURL: URL
    let operations: Set<OperationKind>
}

struct ExternalImportBatch: Identifiable, Sendable {
    let id: UUID
    let urls: [URL]
    let operations: Set<OperationKind>
}

struct RoutedExternalDocument: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let operation: OperationKind
}

struct RoutedExternalBatch: Identifiable, Sendable {
    let id: UUID
    let urls: [URL]
    let operation: OperationKind
}

enum OutputMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case full
    case simple
    case textOnly = "text_only"
    case descriptionsOnly = "descriptions_only"

    var id: String { rawValue }

    @MainActor
    func title(_ l10n: L10n) -> String {
        switch self {
        case .full:
            return l10n.t("كامل", "Full")
        case .simple:
            return l10n.t("مبسّط", "Simplified")
        case .textOnly:
            return l10n.t("نص وجداول", "Text and tables")
        case .descriptionsOnly:
            return l10n.t("صور وأوصاف", "Images and descriptions")
        }
    }

    @MainActor
    func detail(_ l10n: L10n) -> String {
        switch self {
        case .full:
            return l10n.t("يشمل النص والعناوين والجداول والصور وأوصافها.",
                          "Includes text, headings, tables, images, and image descriptions.")
        case .simple:
            return l10n.t("يعرض المحتوى الأساسي بتنسيق مبسط، دون الزخارف غير الضرورية.",
                          "Keeps the main content in a simple layout, without unnecessary decoration.")
        case .textOnly:
            return l10n.t("يشمل النص والجداول فقط، دون الصور أو أوصافها.",
                          "Includes text and tables only, without images or image descriptions.")
        case .descriptionsOnly:
            return l10n.t("يشمل الصور والشعارات وأوصافها فقط، دون بقية النص.",
                          "Includes images, logos, and their descriptions only, without the rest of the text.")
        }
    }
}

struct SupportedLanguage: Identifiable, Hashable, Codable, Sendable {
    let code: String
    let arabicName: String
    let englishName: String

    var id: String { code }

    func name(interface: InterfaceLanguage) -> String {
        interface.isArabic ? arabicName : englishName
    }

    var promptName: String {
        switch code.lowercased() {
        case "ar": return "Arabic"
        case "en": return "English"
        case "fr": return "French"
        case "es": return "Spanish"
        case "de": return "German"
        case "it": return "Italian"
        case "pt": return "Portuguese"
        case "tr": return "Turkish"
        case "ru": return "Russian"
        case "zh": return "Chinese"
        case "ja": return "Japanese"
        case "ko": return "Korean"
        case "hi": return "Hindi"
        case "ur": return "Urdu"
        case "fa": return "Persian"
        default: return code
        }
    }

    static let all: [SupportedLanguage] = [
        .init(code: "ar", arabicName: "العربية", englishName: "Arabic"),
        .init(code: "en", arabicName: "الإنجليزية", englishName: "English"),
        .init(code: "fr", arabicName: "الفرنسية", englishName: "French"),
        .init(code: "es", arabicName: "الإسبانية", englishName: "Spanish"),
        .init(code: "de", arabicName: "الألمانية", englishName: "German"),
        .init(code: "it", arabicName: "الإيطالية", englishName: "Italian"),
        .init(code: "pt", arabicName: "البرتغالية", englishName: "Portuguese"),
        .init(code: "tr", arabicName: "التركية", englishName: "Turkish"),
        .init(code: "ru", arabicName: "الروسية", englishName: "Russian"),
        .init(code: "zh", arabicName: "الصينية", englishName: "Chinese"),
        .init(code: "ja", arabicName: "اليابانية", englishName: "Japanese"),
        .init(code: "ko", arabicName: "الكورية", englishName: "Korean"),
        .init(code: "hi", arabicName: "الهندية", englishName: "Hindi"),
        .init(code: "ur", arabicName: "الأردية", englishName: "Urdu"),
        .init(code: "fa", arabicName: "الفارسية", englishName: "Persian")
    ]

    static func language(code: String) -> SupportedLanguage {
        all.first(where: { $0.code == code }) ?? all[1]
    }
}

enum AIModelChoice: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic = "auto"
    case flash38 = "gemini-3.8-flash"
    case flash = "gemini-3.7-flash"
    case flash36 = "gemini-3.6-flash"
    case flash35 = "gemini-3.5-flash"
    case economy = "gemini-3.5-flash-lite"

    // Kept only so a preference written by the immediately previous app build
    // can still decode and migrate. It is never shown and never sent to Vertex.
    case pro = "gemini-3.1-pro-preview"

    static var allCases: [AIModelChoice] {
        [.automatic, .flash38, .flash, .flash36, .flash35, .economy]
    }

    var id: String { rawValue }

    var serverModelID: String {
        switch self {
        case .pro:
            return AIModelChoice.flash38.rawValue
        case .automatic, .flash38, .flash, .flash36, .flash35, .economy:
            return rawValue
        }
    }

    @MainActor
    func title(_ l10n: L10n) -> String {
        switch self {
        case .automatic:
            return l10n.t("تلقائي (موصى به)", "Automatic (recommended)")
        case .flash38:
            return "Gemini 3.8 Flash"
        case .flash:
            return "Gemini 3.7 Flash"
        case .flash36:
            return "Gemini 3.6 Flash"
        case .flash35:
            return "Gemini 3.5 Flash"
        case .economy:
            return "Gemini 3.5 Flash-Lite"
        case .pro:
            return "Gemini 3.8 Flash"
        }
    }

    @MainActor
    func detail(_ l10n: L10n) -> String {
        switch self {
        case .automatic:
            return l10n.t(
                "يختار بصير نموذج المعالجة الموصى به تلقائيًا.",
                "Basir automatically selects its recommended processing model."
            )
        case .flash38:
            return l10n.t(
                "خيار بصير الموصى به للتحويل. إذا لم يتوفر على الخادم، يُستخدم Gemini 3.7 Flash تلقائيًا.",
                "Basir’s recommended choice for conversion. If unavailable on the server, Gemini 3.7 Flash is used automatically."
            )
        case .flash:
            return l10n.t(
                "إصدار سابق من Flash لمعالجة المستندات.",
                "An earlier Flash version for document processing."
            )
        case .flash36:
            return l10n.t(
                "خيار من Flash لمعالجة المستندات ومهام التحويل العامة.",
                "A Flash option for document processing and general conversion tasks."
            )
        case .flash35:
            return l10n.t(
                "خيار من Flash يوازن بين سرعة المعالجة وتكلفتها.",
                "A Flash option that balances processing speed and cost."
            )
        case .economy:
            return l10n.t(
                "خيار اقتصادي للمستندات البسيطة.",
                "A lower-cost option for simple documents."
            )
        case .pro:
            return l10n.t(
                "يُستخدم Gemini 3.8 Flash بدلًا من هذا الخيار السابق.",
                "Gemini 3.8 Flash is used in place of this older option."
            )
        }
    }
}

struct ConversionOptions: Codable, Equatable, Sendable {
    let operation: OperationKind
    let outputMode: OutputMode
    let targetLanguage: SupportedLanguage?
    let embedVisuals: Bool
    let includeMath: Bool
    let preserveSymbols: Bool
    let interfaceLanguage: InterfaceLanguage
    let pdfQuality: PDFQuality
    let pageSelection: String
    let includeSpeakerNotes: Bool
    let includeHiddenSlides: Bool
    let preserveLinks: Bool
    let skipBlankPages: Bool
    let preferPDFText: Bool
    let concurrentPages: Int
    let rotationCorrection: Int
    let outputName: String?
    let preferredModel: String?

    init(
        operation: OperationKind,
        outputMode: OutputMode,
        targetLanguage: SupportedLanguage?,
        embedVisuals: Bool,
        includeMath: Bool,
        preserveSymbols: Bool = true,
        interfaceLanguage: InterfaceLanguage,
        pdfQuality: PDFQuality = .balanced,
        pageSelection: String = "",
        includeSpeakerNotes: Bool = true,
        includeHiddenSlides: Bool = false,
        preserveLinks: Bool = true,
        skipBlankPages: Bool = true,
        preferPDFText: Bool = true,
        concurrentPages: Int = 3,
        rotationCorrection: Int = 0,
        outputName: String? = nil,
        preferredModel: String? = nil
    ) {
        self.operation = operation
        self.outputMode = outputMode
        self.targetLanguage = targetLanguage
        self.embedVisuals = embedVisuals
        self.includeMath = includeMath
        self.preserveSymbols = preserveSymbols
        self.interfaceLanguage = interfaceLanguage
        self.pdfQuality = pdfQuality
        self.pageSelection = pageSelection
        self.includeSpeakerNotes = includeSpeakerNotes
        self.includeHiddenSlides = includeHiddenSlides
        self.preserveLinks = preserveLinks
        self.skipBlankPages = skipBlankPages
        self.preferPDFText = preferPDFText
        self.concurrentPages = max(1, min(3, concurrentPages))
        self.rotationCorrection = [0, 90, 180, 270].contains(rotationCorrection) ? rotationCorrection : 0
        self.outputName = outputName
        self.preferredModel = AIModelChoice(rawValue: preferredModel ?? "auto")?.rawValue ?? "auto"
    }

    var outputLanguageCode: String {
        targetLanguage?.code ?? "auto"
    }

    var effectiveEmbedVisuals: Bool {
        embedVisuals && outputMode != .textOnly
    }

    var effectivePreferredModel: String {
        AIModelChoice(rawValue: preferredModel ?? "auto")?.serverModelID ?? "auto"
    }

    var encodedMode: String {
        var value: String
        if operation == .translate, let targetLanguage {
            value = "translate:\(targetLanguage.code)"
        } else {
            value = outputMode.rawValue
        }
        if effectiveEmbedVisuals { value += "|visuals" }
        if includeMath { value += "|math" }
        if !preserveSymbols { value += "|symbols_off" }
        value += "|pdf:\(pdfQuality.rawValue)"
        if includeSpeakerNotes { value += "|speaker_notes" }
        if includeHiddenSlides { value += "|hidden_slides" }
        if preserveLinks { value += "|links" }
        if skipBlankPages { value += "|skip_blank" }
        if preferPDFText { value += "|pdf_text" }
        value += "|parallel:\(concurrentPages)"
        if rotationCorrection != 0 { value += "|rotate:\(rotationCorrection)" }
        return value
    }
}

struct ServerConfiguration: Sendable {
    let baseURL: String
    let clientToken: String

    var isConfigured: Bool {
        secureBaseURL != nil
            && !clientToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Only encrypted server addresses without embedded credentials or query
    /// strings are accepted. The build injects authentication separately.
    var secureBaseURL: URL? {
        let value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else { return nil }
        components.scheme = "https"
        return components.url
    }
}

enum ConversionStage: String, Codable, Sendable {
    case preparing
    case waitingForNetwork
    case uploading
    case processing
    case downloading
    case paused
    case finalising
    case done

    @MainActor
    func label(_ l10n: L10n) -> String {
        switch self {
        case .preparing: return l10n.t("جارٍ تجهيز الملف", "Preparing the file")
        case .waitingForNetwork: return l10n.t("بانتظار الاتصال", "Waiting for connection")
        case .uploading: return l10n.t("جارٍ رفع الملف", "Uploading the file")
        case .processing: return l10n.t("جارٍ معالجة المحتوى", "Processing the content")
        case .downloading: return l10n.t("جارٍ تنزيل النتيجة", "Downloading the result")
        case .paused: return l10n.t("المهمة متوقفة مؤقتًا", "Task paused")
        case .finalising: return l10n.t("جارٍ إنشاء ملف Word", "Creating the Word file")
        case .done: return l10n.t("اكتملت المهمة", "Task complete")
        }
    }
}

struct ConversionProgress: Codable, Equatable, Sendable {
    let current: Int
    let total: Int
    let stage: ConversionStage
    let detail: String?
    let transferredBytes: Int64
    let totalBytes: Int64
    let succeeded: Int
    let failed: Int
    let skipped: Int?
    /// While paused: the stage the task was in, so the percentage and the
    /// wording stay true ("downloading, 94%") instead of falling back to 0.
    let pausedFrom: ConversionStage?

    init(
        current: Int,
        total: Int,
        stage: ConversionStage,
        detail: String?,
        transferredBytes: Int64 = 0,
        totalBytes: Int64 = 0,
        succeeded: Int = 0,
        failed: Int = 0,
        skipped: Int? = nil,
        pausedFrom: ConversionStage? = nil
    ) {
        self.current = current
        self.total = total
        self.stage = stage
        self.detail = detail
        self.transferredBytes = transferredBytes
        self.totalBytes = totalBytes
        self.succeeded = succeeded
        self.failed = failed
        self.skipped = skipped
        self.pausedFrom = stage == .paused ? pausedFrom : nil
    }

    /// The same progress in another stage. Pausing remembers where the task
    /// was; resuming forgets it.
    func replacingStage(_ newStage: ConversionStage, keepingBytes: Bool = true) -> ConversionProgress {
        ConversionProgress(
            current: current,
            total: total,
            stage: newStage,
            detail: detail,
            transferredBytes: keepingBytes ? transferredBytes : 0,
            totalBytes: keepingBytes ? totalBytes : 0,
            succeeded: succeeded,
            failed: failed,
            skipped: skipped,
            pausedFrom: newStage == .paused ? (stage == .paused ? pausedFrom : stage) : nil
        )
    }

    /// The stage that describes the work: the real stage, or for a paused
    /// task the stage it was paused in.
    var effectiveStage: ConversionStage {
        if stage == .paused, let pausedFrom, pausedFrom != .paused { return pausedFrom }
        return stage
    }

    var fraction: Double? {
        guard total > 0 else { return nil }
        return min(1, max(0, Double(current) / Double(total)))
    }
}

enum JobStatus: String, Codable, Equatable, Sendable {
    case idle
    case queued
    case waitingForNetwork
    case running
    case paused
    case partial
    case completed
    case failed
    case cancelled
}

struct DocumentMetadata: Codable, Hashable, Sendable {
    let filename: String
    let contentType: String
    let byteCount: Int64
    let itemCount: Int?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let checksum: String?

    var humanReadableSize: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

/// The server quality manifest and the app's own Word-package check,
/// reduced to the facts a person needs to trust the result.
struct QualityReport: Codable, Equatable, Hashable, Sendable {
    var score: Double?
    var warnings: [String]
    var sourcePages: Int?
    var retainedPages: Int
    var skippedBlankPages: Int
    var fallbackPages: Int
    var tables: Int
    var images: Int
    var imagesMissingDescription: Int
    var textCharacters: Int
    var wordPackageVerified: Bool

    /// Score on a 0–100 scale whether the server reports 0–1 or 0–100.
    var percentScore: Int? {
        guard let score, score >= 0 else { return nil }
        return Int((score <= 1 ? score * 100 : score).rounded())
    }

    var hasConcerns: Bool {
        fallbackPages > 0 || imagesMissingDescription > 0 || !warnings.isEmpty
    }
}

struct ConversionOutcome: Sendable {
    let succeededItems: Int
    let failedItems: [Int]
    let skippedBlankItems: [Int]
    let requestedModel: String?
    let executedModel: String?
    let quality: QualityReport?

    init(
        succeededItems: Int,
        failedItems: [Int],
        skippedBlankItems: [Int],
        requestedModel: String? = nil,
        executedModel: String? = nil,
        quality: QualityReport? = nil
    ) {
        self.succeededItems = succeededItems
        self.failedItems = failedItems
        self.skippedBlankItems = skippedBlankItems
        self.requestedModel = requestedModel
        self.executedModel = executedModel
        self.quality = quality
    }

    static let complete = ConversionOutcome(
        succeededItems: 1,
        failedItems: [],
        skippedBlankItems: []
    )
}

struct BasirJob: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var sourcePath: String
    var sourceName: String
    var sourceMetadata: DocumentMetadata?
    var options: ConversionOptions
    var status: JobStatus
    var progress: ConversionProgress
    var resultPath: String?
    var diagnosticPath: String?
    var errorMessage: String?
    var failedItems: [Int]
    var skippedBlankItems: [Int]
    var requestID: String
    var createdAt: Date
    var updatedAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var automaticResumePending: Bool?
    var executedModel: String?
    var qualityReport: QualityReport?
    /// The person cancelled and the server has not confirmed it yet. Kept on
    /// disk so the request is sent again after a relaunch or reconnection.
    var serverCancelPending: Bool?

    var sourceURL: URL { URL(fileURLWithPath: sourcePath) }
    var resultURL: URL? { resultPath.map(URL.init(fileURLWithPath:)) }
    var diagnosticURL: URL? { diagnosticPath.map(URL.init(fileURLWithPath:)) }
}

extension BasirJob {
    /// iOS stopped Basir in the background after the server already had the
    /// file. Nothing is paused: the server keeps converting (or has finished)
    /// and Basir picks the task up again on its own. Shown as "running on the
    /// server", never as "paused".
    var isContinuingOnServer: Bool {
        guard status == .paused, automaticResumePending == true, let stage = progress.pausedFrom else { return false }
        return [.processing, .finalising, .downloading].contains(stage)
    }

    /// The server has finished; only saving the file to the iPhone remains.
    var isReadyOnServer: Bool {
        isContinuingOnServer && progress.pausedFrom == .downloading
    }

    @MainActor
    func serverContinuationText(_ l10n: L10n) -> String {
        if isReadyOnServer {
            return l10n.t("ملف Word جاهز. افتح بصير لتنزيله وحفظه على جهازك",
                          "Your Word file is ready. Open Basir to download and save it")
        }
        let percent = JobStep.overallPercent(for: progress)
        return l10n.t("المعالجة مستمرة على خادم بصير. التقدم: \(percent) بالمئة", "Processing continues on Basir’s server. Progress: \(percent) percent")
    }
}

enum BasirError: LocalizedError {
    case notConfigured
    case unsupportedFile(String)
    case invalidFileContent
    case emptyDocument
    case noReadablePages
    case invalidServerURL
    case invalidResponse(String)
    case fileTooLarge(Int64)
    case networkUnavailable
    case wifiRequired
    case constrainedNetwork
    case authenticationFailed
    case rateLimited(TimeInterval?)
    case invalidServerContentType(String)
    case checksumMismatch
    case passwordProtectedPDF
    case invalidPageSelection
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "The processing service is not available."
        case .unsupportedFile(let extensionName):
            return "Unsupported file type: \(extensionName)."
        case .invalidFileContent:
            return "The file’s content does not match its file type."
        case .emptyDocument:
            return "The document does not contain readable content."
        case .noReadablePages:
            return "No PDF pages could be converted."
        case .invalidServerURL:
            return "Basir could not connect to the processing service."
        case .invalidResponse(let message):
            return "The processing service returned an invalid response. \(message)"
        case .fileTooLarge(let size):
            return "The file exceeds the size limit. File size: \(size) bytes."
        case .networkUnavailable:
            return "No internet connection is available."
        case .wifiRequired:
            return "This task is set to run on Wi-Fi only."
        case .constrainedNetwork:
            return "Low Data Mode is active for this network."
        case .authenticationFailed:
            return "Basir could not verify access to the service."
        case .rateLimited(let retryAfter):
            if let retryAfter { return "Too many requests. Try again in \(Int(retryAfter)) seconds." }
            return "Too many requests. Please try again later."
        case .invalidServerContentType(let type):
            return "The server returned an unexpected content type: \(type)."
        case .checksumMismatch:
            return "The downloaded file failed its integrity check. Please try downloading it again."
        case .passwordProtectedPDF:
            return "This PDF is protected by a password."
        case .invalidPageSelection:
            return "The selected PDF page range is invalid."
        case .conversionFailed(let message):
            return message
        }
    }
}

extension UTType {
    static let basirPDF = UTType.pdf
    static let basirPPTX = UTType(filenameExtension: "pptx") ?? .presentation
    static let basirPPT = UTType(filenameExtension: "ppt") ?? .presentation
    static let basirDOCX = UTType(filenameExtension: "docx") ?? .data
    static let basirDOC = UTType(filenameExtension: "doc") ?? .data

    static var basirSupportedDocuments: [UTType] {
        [.pdf, .basirPPTX, .basirPPT, .basirDOCX, .basirDOC, .image, .audio, .movie]
    }
}
