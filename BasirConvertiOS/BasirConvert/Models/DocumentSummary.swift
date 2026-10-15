import Foundation

/// A verified summary of one or several documents, as the server returns it
/// (POST /api/summaries, GET /api/jobs/{id}/summary). Every point says where
/// it is in the document and whether Basir found it in the text itself.
struct DocumentSummary: Codable, Equatable, Sendable {
    struct Location: Codable, Equatable, Hashable, Sendable {
        var file: Int = 0
        var page: Int
    }

    struct Point: Codable, Equatable, Identifiable, Sendable {
        var text: String
        var kind: String = "idea"
        var locations: [Location] = []
        var quote: String = ""
        var verified: Bool = false
        var flaggedNumbers: [String] = []
        var owner: String = ""
        var deadline: String = ""
        var id: String { text + "|" + locations.map { "\($0.file):\($0.page)" }.joined(separator: ",") }
    }

    struct Group: Codable, Equatable, Identifiable, Sendable {
        var heading: String
        var points: [Point] = []
        var id: String { heading }
    }

    struct Section: Codable, Equatable, Identifiable, Sendable {
        var title: String
        var file: Int = 0
        var firstPage: Int = 0
        var lastPage: Int = 0
        var summary: String
        var flaggedNumbers: [String] = []
        var points: [Point] = []
        var id: String { "\(file)|\(firstPage)|\(title)" }
    }

    struct Card: Codable, Equatable, Identifiable, Sendable {
        var front: String
        var back: String
        var locations: [Location] = []
        var id: String { front }
    }

    struct Question: Codable, Equatable, Identifiable, Sendable {
        var question: String
        var choices: [String]
        var answerIndex: Int
        var explanation: String = ""
        var locations: [Location] = []
        var id: String { question }
    }

    struct Overview: Codable, Equatable, Sendable {
        var text: String
        var flaggedNumbers: [String] = []
    }

    struct FileInfo: Codable, Equatable, Sendable {
        var name: String
        var pageKind: String
        var pages: Int
    }

    struct Verification: Codable, Equatable, Sendable {
        var pointsTotal: Int = 0
        var pointsVerified: Int = 0
        var numbersFlagged: Int = 0
        var pagesTotal: Int = 0
        var pagesCovered: Int = 0
    }

    var language: String
    var template: String
    var documentType: String
    var oneLine: Overview
    var short: Overview
    var easyRead: Overview
    var keyPoints: [Point] = []
    var groups: [Group] = []
    var sections: [Section] = []
    var cards: [Card] = []
    var quiz: [Question] = []
    var notice: String = ""
    var files: [FileInfo] = []
    var verification: Verification = Verification()

    static func decode(_ data: Data) throws -> DocumentSummary {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(DocumentSummary.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(self)
    }

    /// True when pages are real source pages (Basir's Word results), false
    /// when the text had none and was cut into numbered parts.
    func usesPages(file: Int) -> Bool {
        files.indices.contains(file) ? files[file].pageKind == "page" : true
    }

    /// Everything the summary says, for search in My Files (ت15).
    var searchableText: String {
        var pieces = [documentType, oneLine.text, short.text]
        pieces += keyPoints.map(\.text)
        pieces += groups.flatMap { $0.points.map(\.text) }
        pieces += sections.map { $0.title + " " + $0.summary }
        return pieces.joined(separator: "\n")
    }
}

/// The kinds of documents the summary is organized for (ت7).
enum SummaryTemplate: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic = "auto"
    case general, contract, financial, letter, medical, study, report, meeting, multi

    var id: String { rawValue }

    @MainActor
    func title(_ l10n: L10n) -> String {
        switch self {
        case .automatic: return l10n.t("تلقائي حسب نوع المستند", "Automatic, by document type")
        case .general: return l10n.t("عام", "General")
        case .contract: return l10n.t("عقد أو اتفاقية", "Contract or agreement")
        case .financial: return l10n.t("فاتورة أو كشف حساب", "Bill or statement")
        case .letter: return l10n.t("خطاب رسمي", "Official letter")
        case .medical: return l10n.t("تقرير طبي", "Medical report")
        case .study: return l10n.t("مادة دراسية", "Study material")
        case .report: return l10n.t("تقرير أو بحث", "Report or research")
        case .meeting: return l10n.t("اجتماع أو تسجيل", "Meeting or recording")
        case .multi: return l10n.t("مقارنة عدة ملفات", "Several files compared")
        }
    }

    /// The choices offered for one document (several-file comparison is
    /// chosen automatically when several files are summarized together).
    static var singleDocumentChoices: [SummaryTemplate] {
        [.automatic, .general, .contract, .financial, .letter, .medical, .study, .report, .meeting]
    }
}

/// What the app sends to POST /api/summaries, and as a summary job's source.
struct SummaryRequestBody: Codable, Equatable, Sendable {
    struct File: Codable, Equatable, Sendable {
        var name: String
        var text: String
    }

    var text: String = ""
    var files: [File] = []
    var title: String = ""
    var language: String = "ar"
    var template: String = "auto"
    var includeStudy: Bool = false
    var choice: String = "auto"

    var totalCharacters: Int { text.count + files.reduce(0) { $0 + $1.text.count } }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// Identifies the same request (text and options), so a summary already
    /// made is opened at once instead of asked for again.
    var variantKey: String {
        "\(language)|\(template)|\(includeStudy ? "study" : "plain")"
    }
}
