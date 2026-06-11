import Foundation

enum PageAnalysisSource: String, Codable, Sendable {
    case gemini
    case geminiConsensus
    case nativeTextFallback
    case localBlankPage
    case visualPageFallback
}

enum PageContentKind: String, Codable, CaseIterable, Sendable {
    case printed
    case handwritten
    case mixed
    case imageOnly
    case unknown
}

enum TextDirection: String, Codable, CaseIterable, Sendable {
    case rtl
    case ltr
}

enum BaselineStyle: String, Codable, CaseIterable, Sendable {
    case normal
    case superscript
    case subscriptText = "subscript"
}

enum ListStyle: String, Codable, CaseIterable, Sendable {
    case bullet
    case decimal
    case arabicIndic
    case lowerLetter
    case upperLetter
    case lowerRoman
    case upperRoman
}

enum CellHorizontalAlignment: String, Codable, CaseIterable, Sendable {
    case start
    case center
    case end
    case justify
}

enum CellVerticalAlignment: String, Codable, CaseIterable, Sendable {
    case top
    case center
    case bottom
}

struct TextRun: Codable, Sendable, Equatable {
    var text: String
    var bold: Bool
    var italic: Bool
    var underline: Bool
    var strike: Bool
    var highlightColor: String
    var textColor: String
    var fontSize: Double
    var baseline: BaselineStyle
    var direction: TextDirection?
    var linkURL: String
    var internalLink: String
    var footnoteReferenceID: Int
    var preserveSpaces: Bool

    enum CodingKeys: String, CodingKey {
        case text, bold, italic, underline, strike, highlightColor, textColor
        case fontSize, baseline, direction, linkURL, internalLink
        case footnoteReferenceID, preserveSpaces
    }

    init(
        text: String,
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        strike: Bool = false,
        highlightColor: String = "",
        textColor: String = "",
        fontSize: Double = 0,
        baseline: BaselineStyle = .normal,
        direction: TextDirection? = nil,
        linkURL: String = "",
        internalLink: String = "",
        footnoteReferenceID: Int = 0,
        preserveSpaces: Bool = true
    ) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strike = strike
        self.highlightColor = highlightColor
        self.textColor = textColor
        self.fontSize = max(0, fontSize.isFinite ? fontSize : 0)
        self.baseline = baseline
        self.direction = direction
        self.linkURL = linkURL
        self.internalLink = internalLink
        self.footnoteReferenceID = max(0, footnoteReferenceID)
        self.preserveSpaces = preserveSpaces
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        bold = try container.decodeIfPresent(Bool.self, forKey: .bold) ?? false
        italic = try container.decodeIfPresent(Bool.self, forKey: .italic) ?? false
        underline = try container.decodeIfPresent(Bool.self, forKey: .underline) ?? false
        strike = try container.decodeIfPresent(Bool.self, forKey: .strike) ?? false
        highlightColor = try container.decodeIfPresent(String.self, forKey: .highlightColor) ?? ""
        textColor = try container.decodeIfPresent(String.self, forKey: .textColor) ?? ""
        let size = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 0
        fontSize = max(0, size.isFinite ? size : 0)
        baseline = try container.decodeIfPresent(BaselineStyle.self, forKey: .baseline) ?? .normal
        direction = try container.decodeIfPresent(TextDirection.self, forKey: .direction)
        linkURL = try container.decodeIfPresent(String.self, forKey: .linkURL) ?? ""
        internalLink = try container.decodeIfPresent(String.self, forKey: .internalLink) ?? ""
        footnoteReferenceID = max(0, try container.decodeIfPresent(Int.self, forKey: .footnoteReferenceID) ?? 0)
        preserveSpaces = try container.decodeIfPresent(Bool.self, forKey: .preserveSpaces) ?? true
    }
}

struct TableCell: Codable, Sendable, Equatable {
    var row: Int
    var column: Int
    var rowSpan: Int
    var columnSpan: Int
    var text: String
    var runs: [TextRun]
    var isHeader: Bool
    var horizontalAlignment: CellHorizontalAlignment
    var verticalAlignment: CellVerticalAlignment
    var boundingBox: [Double]

    enum CodingKeys: String, CodingKey {
        case row, column, rowSpan, columnSpan, text, runs, isHeader
        case horizontalAlignment, verticalAlignment, boundingBox
    }

    init(
        row: Int,
        column: Int,
        rowSpan: Int = 1,
        columnSpan: Int = 1,
        text: String = "",
        runs: [TextRun] = [],
        isHeader: Bool = false,
        horizontalAlignment: CellHorizontalAlignment = .start,
        verticalAlignment: CellVerticalAlignment = .top,
        boundingBox: [Double] = [0, 0, 0, 0]
    ) {
        self.row = max(0, row)
        self.column = max(0, column)
        self.rowSpan = max(1, rowSpan)
        self.columnSpan = max(1, columnSpan)
        self.text = text
        self.runs = runs
        self.isHeader = isHeader
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.boundingBox = boundingBox
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        row = max(0, try container.decodeIfPresent(Int.self, forKey: .row) ?? 0)
        column = max(0, try container.decodeIfPresent(Int.self, forKey: .column) ?? 0)
        rowSpan = max(1, try container.decodeIfPresent(Int.self, forKey: .rowSpan) ?? 1)
        columnSpan = max(1, try container.decodeIfPresent(Int.self, forKey: .columnSpan) ?? 1)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        runs = try container.decodeIfPresent([TextRun].self, forKey: .runs) ?? []
        isHeader = try container.decodeIfPresent(Bool.self, forKey: .isHeader) ?? false
        horizontalAlignment = try container.decodeIfPresent(CellHorizontalAlignment.self, forKey: .horizontalAlignment) ?? .start
        verticalAlignment = try container.decodeIfPresent(CellVerticalAlignment.self, forKey: .verticalAlignment) ?? .top
        boundingBox = try container.decodeIfPresent([Double].self, forKey: .boundingBox) ?? [0, 0, 0, 0]
    }
}

struct PageAnalysis: Codable, Sendable {
    var pageNumber: Int
    var detectedLanguage: String
    var direction: TextDirection
    var blocks: [DocumentBlock]
    var source: PageAnalysisSource
    var warnings: [String]
    var contentKind: PageContentKind
    var qualityScore: Double
    var agreementScore: Double
    var verificationPasses: Int
    var preserveWholePageImage: Bool
    var wholePageAltText: String
    var readingOrderConfidence: Double
    var criticalTokens: [String]

    enum CodingKeys: String, CodingKey {
        case pageNumber, detectedLanguage, direction, blocks, source, warnings
        case contentKind, qualityScore, agreementScore, verificationPasses
        case preserveWholePageImage, wholePageAltText, readingOrderConfidence, criticalTokens
    }

    init(
        pageNumber: Int,
        detectedLanguage: String,
        direction: TextDirection,
        blocks: [DocumentBlock],
        source: PageAnalysisSource = .gemini,
        warnings: [String] = [],
        contentKind: PageContentKind = .unknown,
        qualityScore: Double = 0,
        agreementScore: Double = 0,
        verificationPasses: Int = 1,
        preserveWholePageImage: Bool = false,
        wholePageAltText: String = "",
        readingOrderConfidence: Double = 1,
        criticalTokens: [String] = []
    ) {
        self.pageNumber = pageNumber
        self.detectedLanguage = detectedLanguage
        self.direction = direction
        self.blocks = blocks
        self.source = source
        self.warnings = warnings
        self.contentKind = contentKind
        self.qualityScore = Self.clamp(qualityScore)
        self.agreementScore = Self.clamp(agreementScore)
        self.verificationPasses = max(1, verificationPasses)
        self.preserveWholePageImage = preserveWholePageImage
        self.wholePageAltText = wholePageAltText
        self.readingOrderConfidence = Self.clamp(readingOrderConfidence)
        self.criticalTokens = criticalTokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pageNumber = try container.decode(Int.self, forKey: .pageNumber)
        detectedLanguage = try container.decodeIfPresent(String.self, forKey: .detectedLanguage) ?? "und"
        direction = try container.decodeIfPresent(TextDirection.self, forKey: .direction) ?? .ltr
        blocks = try container.decodeIfPresent([DocumentBlock].self, forKey: .blocks) ?? []
        source = try container.decodeIfPresent(PageAnalysisSource.self, forKey: .source) ?? .gemini
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        contentKind = try container.decodeIfPresent(PageContentKind.self, forKey: .contentKind) ?? .unknown
        qualityScore = Self.clamp(try container.decodeIfPresent(Double.self, forKey: .qualityScore) ?? 0)
        agreementScore = Self.clamp(try container.decodeIfPresent(Double.self, forKey: .agreementScore) ?? 0)
        verificationPasses = max(1, try container.decodeIfPresent(Int.self, forKey: .verificationPasses) ?? 1)
        preserveWholePageImage = try container.decodeIfPresent(Bool.self, forKey: .preserveWholePageImage) ?? false
        wholePageAltText = try container.decodeIfPresent(String.self, forKey: .wholePageAltText) ?? ""
        readingOrderConfidence = Self.clamp(try container.decodeIfPresent(Double.self, forKey: .readingOrderConfidence) ?? 1)
        criticalTokens = try container.decodeIfPresent([String].self, forKey: .criticalTokens) ?? []
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value.isFinite ? value : 0))
    }
}

struct LocalOCRReference: Sendable {
    var text: String
    var averageConfidence: Double

    static let empty = LocalOCRReference(text: "", averageConfidence: 0)

    init(text: String, averageConfidence: Double) {
        self.text = text
        self.averageConfidence = min(1, max(0, averageConfidence.isFinite ? averageConfidence : 0))
    }
}

struct DocumentBlock: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var type: BlockType
    var text: String
    var runs: [TextRun]
    var rows: [[String]]
    var tableRowCount: Int
    var tableColumnCount: Int
    var tableCells: [TableCell]
    var repeatHeaderRows: Int
    var boundingBox: [Double]
    var altText: String
    var isDecorative: Bool
    var confidence: Double
    var direction: TextDirection?
    var listLevel: Int
    var listStyle: ListStyle
    var listStart: Int
    var rotationDegrees: Double
    var bookmark: String
    var keepWithNext: Bool
    var footnoteID: Int

    enum CodingKeys: String, CodingKey {
        case type, text, runs, rows, tableRowCount, tableColumnCount, tableCells
        case repeatHeaderRows, boundingBox, altText, isDecorative, confidence
        case direction, listLevel, listStyle, listStart, rotationDegrees
        case bookmark, keepWithNext, footnoteID
    }

    init(
        type: BlockType,
        text: String = "",
        runs: [TextRun] = [],
        rows: [[String]] = [],
        tableRowCount: Int = 0,
        tableColumnCount: Int = 0,
        tableCells: [TableCell] = [],
        repeatHeaderRows: Int = 0,
        boundingBox: [Double] = [0, 0, 0, 0],
        altText: String = "",
        isDecorative: Bool = false,
        confidence: Double = 1,
        direction: TextDirection? = nil,
        listLevel: Int = 0,
        listStyle: ListStyle = .bullet,
        listStart: Int = 1,
        rotationDegrees: Double = 0,
        bookmark: String = "",
        keepWithNext: Bool = false,
        footnoteID: Int = 0
    ) {
        self.type = type
        self.text = text
        self.runs = runs
        self.rows = rows
        self.tableRowCount = max(0, tableRowCount)
        self.tableColumnCount = max(0, tableColumnCount)
        self.tableCells = tableCells
        self.repeatHeaderRows = max(0, repeatHeaderRows)
        self.boundingBox = boundingBox
        self.altText = altText
        self.isDecorative = isDecorative
        self.confidence = min(1, max(0, confidence.isFinite ? confidence : 0))
        self.direction = direction
        self.listLevel = max(0, min(8, listLevel))
        self.listStyle = listStyle
        self.listStart = max(1, listStart)
        self.rotationDegrees = rotationDegrees.isFinite ? rotationDegrees : 0
        self.bookmark = bookmark
        self.keepWithNext = keepWithNext
        self.footnoteID = max(0, footnoteID)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        // Lenient: a missing or unrecognized block type must not fail the whole
        // page decode (the model isn't always constrained by a response schema).
        // Unknown/absent types fall back to a plain paragraph.
        type = (try? container.decode(BlockType.self, forKey: .type)) ?? .paragraph
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        runs = try container.decodeIfPresent([TextRun].self, forKey: .runs) ?? []
        rows = try container.decodeIfPresent([[String]].self, forKey: .rows) ?? []
        tableRowCount = max(0, try container.decodeIfPresent(Int.self, forKey: .tableRowCount) ?? rows.count)
        tableColumnCount = max(0, try container.decodeIfPresent(Int.self, forKey: .tableColumnCount) ?? (rows.map(\.count).max() ?? 0))
        tableCells = try container.decodeIfPresent([TableCell].self, forKey: .tableCells) ?? []
        repeatHeaderRows = max(0, try container.decodeIfPresent(Int.self, forKey: .repeatHeaderRows) ?? 0)
        boundingBox = try container.decodeIfPresent([Double].self, forKey: .boundingBox) ?? [0, 0, 0, 0]
        altText = try container.decodeIfPresent(String.self, forKey: .altText) ?? ""
        isDecorative = try container.decodeIfPresent(Bool.self, forKey: .isDecorative) ?? false
        let decodedConfidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 1
        confidence = min(1, max(0, decodedConfidence.isFinite ? decodedConfidence : 0))
        direction = try container.decodeIfPresent(TextDirection.self, forKey: .direction)
        listLevel = max(0, min(8, try container.decodeIfPresent(Int.self, forKey: .listLevel) ?? 0))
        listStyle = try container.decodeIfPresent(ListStyle.self, forKey: .listStyle) ?? (type == .numbered ? .decimal : .bullet)
        listStart = max(1, try container.decodeIfPresent(Int.self, forKey: .listStart) ?? 1)
        let decodedRotation = try container.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0
        rotationDegrees = decodedRotation.isFinite ? decodedRotation : 0
        bookmark = try container.decodeIfPresent(String.self, forKey: .bookmark) ?? ""
        keepWithNext = try container.decodeIfPresent(Bool.self, forKey: .keepWithNext) ?? false
        footnoteID = max(0, try container.decodeIfPresent(Int.self, forKey: .footnoteID) ?? 0)
    }
}

enum BlockType: String, Codable, CaseIterable, Sendable {
    case heading1
    case heading2
    case heading3
    case paragraph
    case bullet
    case numbered
    case table
    case image
    case pageImage
    case caption
    case header
    case footer
    case footnote
    case quote
    case textBox
    case equation
    case formField
    case watermark
    case separator
    case blank
}

struct ConversionOptions: Codable, Sendable, Equatable {
    var model: String
    var thinkingLevel: String
    var describeImages: Bool
    var embedImages: Bool
    var includeDecorativeImages: Bool
    var showImageDescriptions: Bool
    var preserveHeadersAndFooters: Bool
    var preservePageBreaks: Bool
    var preservePageSizeAndOrientation: Bool
    var addPageNumbers: Bool
    var bodyFontArabic: String
    var bodyFontLatin: String
    var bodyFontSize: Double
    var headingFontSize: Double
    var pageMarginPoints: Double
    var concurrency: Int
    var retryCount: Int
    var useNativeTextFallback: Bool
    var strictCompletenessCheck: Bool
    var minimumCoverageRatio: Double
    var promptAddendum: String
}

enum JobStatus: String, Codable, Sendable {
    case queued
    case preparing
    case analyzing
    case building
    case completed
    case failed
    case cancelled

    var localizedTitle: String {
        switch self {
        case .queued: return L10n.text("في الانتظار")
        case .preparing: return L10n.text("تجهيز المستند")
        case .analyzing: return L10n.text("تحليل الصفحات")
        case .building: return L10n.text("إنشاء ملف Word")
        case .completed: return L10n.text("اكتمل")
        case .failed: return L10n.text("تعذر التحويل")
        case .cancelled: return L10n.text("أُلغي")
        }
    }
}

struct ConversionJobRecord: Codable, Identifiable, Sendable {
    var id: UUID
    var sourceName: String
    var createdAt: Date
    var updatedAt: Date
    var totalPages: Int
    var completedPages: Int
    var status: JobStatus
    var outputPath: String?
    var workspacePath: String
    var errorMessage: String?

    var formatVersion: Int?
    var sourceSHA256: String?
    var optionsSnapshot: ConversionOptions?
    var fallbackPages: [Int]?
    var warnings: [String]?
    var outputSHA256: String?
    var outputByteCount: Int64?
    var minimumQualityScore: Double?
    var handwrittenPages: [Int]?

    var progress: Double {
        guard totalPages > 0 else { return 0 }
        return min(1, Double(completedPages) / Double(totalPages))
    }

    var normalizedFallbackPages: [Int] { Array(Set(fallbackPages ?? [])).sorted() }
    var normalizedWarnings: [String] { Array(Set(warnings ?? [])).sorted() }
    var normalizedHandwrittenPages: [Int] { Array(Set(handwrittenPages ?? [])).sorted() }
}

struct ConversionProgress: Sendable {
    var status: JobStatus
    var currentPage: Int
    var totalPages: Int
    var message: String

    var fraction: Double {
        guard totalPages > 0 else { return 0 }
        return min(1, Double(currentPage) / Double(totalPages))
    }
}

struct GeminiModelInfo: Codable, Sendable, Identifiable {
    var name: String
    var displayName: String?
    var supportedGenerationMethods: [String]

    enum CodingKeys: String, CodingKey {
        case name, displayName, supportedGenerationMethods
    }

    init(name: String, displayName: String? = nil, supportedGenerationMethods: [String] = []) {
        self.name = name
        self.displayName = displayName
        self.supportedGenerationMethods = supportedGenerationMethods
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        supportedGenerationMethods = try container.decodeIfPresent([String].self, forKey: .supportedGenerationMethods) ?? []
    }

    var id: String { name }
    var shortName: String { name.replacingOccurrences(of: "models/", with: "") }
    var supportsGenerateContent: Bool { supportedGenerationMethods.contains("generateContent") }
}
