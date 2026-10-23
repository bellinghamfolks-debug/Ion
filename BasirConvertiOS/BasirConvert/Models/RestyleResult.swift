import Foundation

/// Natural style: a text written by a person and over-edited by a machine,
/// brought back to a natural human voice by the server (the whole text read
/// first, then every part with it in mind). This is what comes back.
struct RestyleResult: Codable, Equatable, Sendable {
    struct Profile: Codable, Equatable, Sendable {
        var language: String = ""
        var genre: String = ""
        var narration: String = ""
        var voice: String = ""
        var dialogue: String = ""
        var names: [String] = []
        var aiMarks: [String] = []
        var keep: [String] = []
    }

    struct Block: Codable, Equatable, Identifiable, Sendable {
        var id: String
        var kind: String = "paragraph"
        var level: Int = 0
        var text: String = ""
        /// The paragraph before editing, only when it changed.
        var original: String = ""

        var changed: Bool { !original.isEmpty }
    }

    struct Measure: Codable, Equatable, Sendable {
        var words = 0
        var semicolons = 0
        var dashes = 0
        var colons = 0
        var exclamations = 0
        var stockPhrases = 0
        var semicolonsPer1000: Double = 0
        var dashesPer1000: Double = 0
        var averageSentenceWords: Double = 0
        var sentenceLengthSpread: Double = 0
    }

    struct Report: Codable, Equatable, Sendable {
        var paragraphsTotal = 0
        var paragraphsChanged = 0
        var partsTotal = 0
        var partsKeptOriginal: [Int] = []
        var before = Measure()
        var after = Measure()
        var namesChecked = 0
        var notes: [String] = []
    }

    var title: String = ""
    var language: String = "ar"
    var strength: String = "full"
    var profile = Profile()
    var blocks: [Block] = []
    var report = Report()


    static func decode(_ data: Data) throws -> RestyleResult {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(RestyleResult.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(self)
    }

    /// The edited text as plain paragraphs, headings included, for copying.
    var plainText: String {
        blocks.map { $0.kind == "break" ? "" : $0.text }.joined(separator: "\n")
    }

    var isPartial: Bool { !report.partsKeptOriginal.isEmpty }

    /// For the reader: the edited text with its own headings.
    func readerBlocks() -> [ReaderBlock] {
        var items: [ReaderBlock] = []
        if !title.isEmpty { items.append(ReaderBlock(id: 0, kind: .heading(1), text: title)) }
        for block in blocks where block.kind != "break" && !block.text.isEmpty {
            let kind: ReaderBlock.Kind = block.kind == "heading" ? .heading(min(6, max(2, block.level + 1))) : .paragraph
            items.append(ReaderBlock(id: items.count, kind: kind, text: block.text))
        }
        return items
    }
}
