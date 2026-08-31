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
            return l10n.t("النص والعناوين والجداول والصور مع وصفها.",
                          "Text, headings, tables, and described images.")
        case .simple:
            return l10n.t("محتوى مباشر مع حذف الزخارف غير المهمة.",
                          "Direct content with nonessential decoration removed.")
        case .textOnly:
            return l10n.t("يحذف الصور وأوصافها ويحتفظ بالنص والجداول.",
                          "Keeps text and tables and omits images and their descriptions.")
        case .descriptionsOnly:
            return l10n.t("يحتفظ بالصور والشعارات ووصفها دون بقية النص.",
                          "Keeps images, logos, and their descriptions without the remaining text.")
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
    case flash = "gemini-3.7-flash"
    // Legacy values remain decodable so existing saved settings migrate cleanly.
    case economy = "gemini-3.5-flash-lite"
    case pro = "gemini-3.1-pro-preview"

    static var allCases: [AIModelChoice] { [.automatic, .flash] }

    var id: String { rawValue }

    /// The current server conversion engine runs on Gemini 3.7 Flash. Old saved
    /// model selections are migrated at the network boundary instead of sending
    /// retired preview/lite identifiers back to Vertex AI.
    var serverModelID: String {
        switch self {
        case .automatic:
            return "auto"
        case .flash, .economy, .pro:
            return "gemini-3.7-flash"
        }
    }

    @MainActor
    func title(_ l10n: L10n) -> String {
        switch self {
        case .automatic: return l10n.t("تلقائي موصى به", "Automatic (recommended)")
        case .flash: return "Gemini 3.7 Flash"
        case .economy, .pro: return "Gemini 3.7 Flash"
        }
    }

    @MainActor
    func detail(_ l10n: L10n) -> String {
        switch self {
        case .automatic:
            return l10n.t("يستخدم الخادم النموذج الإنتاجي الأنسب للمحرك الحالي.", "The server uses the production model appropriate for the current engine.")
        case .flash, .economy, .pro:
            return l10n.t("النموذج الإنتاجي الحالي للتحويل السريع والدقيق.", "Current production model for fast, faithful conversion.")
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
        case .waitingForNetwork: return l10n.t("بانتظار الشبكة", "Waiting for network")
        case .uploading: return l10n.t("جارٍ رفع الملف", "Uploading the file")
        case .processing: return l10n.t("جارٍ معالجة المحتوى", "Processing the content")
        case .downloading: return l10n.t("جارٍ تنزيل النتيجة", "Downloading the result")
        case .paused: return l10n.t("المهمة متوقفة مؤقتًا", "Task paused")
        case .finalising: return l10n.t("جارٍ إنشاء ملف Word", "Creating the Word file")
        case .done: return l10n.t("اكتملت العملية", "Completed")
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

    init(
        current: Int,
        total: Int,
        stage: ConversionStage,
        detail: String?,
        transferredBytes: Int64 = 0,
        totalBytes: Int64 = 0,
        succeeded: Int = 0,
        failed: Int = 0,
        skipped: Int? = nil
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

struct ConversionOutcome: Sendable {
    let succeededItems: Int
    let failedItems: [Int]
    let skippedBlankItems: [Int]
    let requestedModel: String?
    let executedModel: String?

    init(
        succeededItems: Int,
        failedItems: [Int],
        skippedBlankItems: [Int],
        requestedModel: String? = nil,
        executedModel: String? = nil
    ) {
        self.succeededItems = succeededItems
        self.failedItems = failedItems
        self.skippedBlankItems = skippedBlankItems
        self.requestedModel = requestedModel
        self.executedModel = executedModel
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

    var sourceURL: URL { URL(fileURLWithPath: sourcePath) }
    var resultURL: URL? { resultPath.map(URL.init(fileURLWithPath:)) }
    var diagnosticURL: URL? { diagnosticPath.map(URL.init(fileURLWithPath:)) }
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
            return "The selected file content does not match its filename."
        case .emptyDocument:
            return "The document does not contain readable content."
        case .noReadablePages:
            return "No PDF pages could be converted."
        case .invalidServerURL:
            return "The processing service address is invalid."
        case .invalidResponse(let message):
            return "The processing service returned an invalid response. \(message)"
        case .fileTooLarge(let size):
            return "The selected file is too large (\(size) bytes)."
        case .networkUnavailable:
            return "No internet connection is available."
        case .wifiRequired:
            return "This task is set to run on Wi-Fi only."
        case .constrainedNetwork:
            return "Low Data Mode is active for this network."
        case .authenticationFailed:
            return "The service rejected the authentication details."
        case .rateLimited(let retryAfter):
            if let retryAfter { return "The service rate limit was reached. Retry after \(Int(retryAfter)) seconds." }
            return "The service rate limit was reached."
        case .invalidServerContentType(let type):
            return "The server returned an unexpected content type: \(type)."
        case .checksumMismatch:
            return "The downloaded file checksum does not match the server checksum."
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
