import Foundation

/// Human style: a text the server turned from machine-made prose into a
/// person's prose (or, in "restore", brought back to its author's voice).
/// The server measures every window of the text against human writing of
/// the same kind, writes several candidates per part, chooses by measurement,
/// and checks the meaning. This is what comes back. Every field added after
/// the first version is optional, so texts saved before still open.
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
        var kind: String?
        var synopsis: String?
    }

    struct Edit: Codable, Equatable, Sendable, Hashable {
        var category: String = "other"
        var before: String = ""
        var after: String = ""
        var reason: String = ""
    }

    struct Block: Codable, Equatable, Identifiable, Sendable {
        var id: String
        var kind: String = "paragraph"
        var level: Int = 0
        var text: String = ""
        /// The paragraph before editing, only when it changed.
        var original: String = ""
        var edits: [Edit]?
        /// Why the paragraph went back to its original ("meaning", "gates").
        var restored: String?
        /// What the measurement asked for: keep, edit or rewrite.
        var plan: String?

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

    /// The independent measure (never used to choose the wording), with its known error rates.
    struct Machine: Codable, Equatable, Sendable {
        var available = false
        var domain = ""
        var windows = 0
        var judgeFlaggedBefore = 0
        var judgeFlaggedAfter = 0
        var judgeMeanBefore: Double = 0
        var judgeMeanAfter: Double = 0
        var inRangeBefore: Double = 0
        var inRangeAfter: Double = 0
        var judgeFalsePositiveRate: Double = 0
        var judgeTruePositiveRate: Double = 0
        var judgeLiteraryFalsePositiveRate: Double?
        var uniformSignals: [String] = []
    }

    struct WindowScore: Codable, Equatable, Sendable {
        var paragraphs: [String] = []
        var before: Double = 0
        var after: Double = 0
        var flaggedBefore = false
        var flaggedAfter = false
        var inRangeBefore = 0
        var inRangeAfter = 0
        var signals = 0
        var reasons: [String] = []
    }

    struct Distance: Codable, Equatable, Sendable {
        var available = false
        var reason = ""
        var reliable = false
        var deltaBefore: Double = 0
        var deltaAfter: Double = 0
        var deltaAuthor: Double = 0
    }

    /// The book as a whole (deep strength): how alike its pieces are built, before and after.
    struct Structure: Codable, Equatable, Sendable {
        var available = false
        var pieces = 0
        var endingsBefore: [String: Int] = [:]
        var endingsAfter: [String: Int] = [:]
        var topTemplateShareBefore: Double = 0
        var topTemplateShareAfter: Double = 0
        var reflectionShareBefore: Double = 0
        var reflectionShareAfter: Double = 0
        var asideShareBefore: Double = 0
        var asideShareAfter: Double = 0
        var hedgesPer1000Before: Double = 0
        var hedgesPer1000After: Double = 0
        var hedgesPer1000Human: Double = 0
        var operations: [String: Int] = [:]
        var piecesReshaped = 0
        var piecesRejected = 0
        /// The deep strength may invent, at the author's request.
        var creative: Bool?
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
        var mode: String?
        var wordsChangedPercent: Double?
        var sentencesRestored: Int?
        var meaningChecked: Int?
        var meaningFailed: Int?
        var editCategories: [String: Int]?
        var distance: Distance?
        var machine: Machine?
        var structure: Structure?
        var windows: [WindowScore]?
        var paragraphsKept: Int?
        var paragraphsRewritten: Int?
        var sampleSource: String?
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
        blocks.filter { !($0.kind == "paragraph" && $0.text.isEmpty) }
            .map { $0.kind == "break" ? "" : $0.text }.joined(separator: "\n")
    }

    var isPartial: Bool { !report.partsKeptOriginal.isEmpty }

    /// The text with the author's choices: a refused paragraph is its original.
    func applying(refused: Set<String>) -> RestyleResult {
        var copy = self
        copy.blocks = blocks.map { block in
            guard refused.contains(block.id), block.changed else { return block }
            var kept = block
            kept.text = block.original
            kept.original = ""
            kept.edits = []
            return kept
        }
        return copy
    }

    /// For the reader: the edited text with its own headings.
    func readerBlocks() -> [ReaderBlock] {
        var items: [ReaderBlock] = []
        if !title.isEmpty { items.append(ReaderBlock(id: 0, kind: .heading(1), text: title)) }
        for block in blocks where block.kind != "break" && !block.text.isEmpty {   // a cut paragraph is empty
            let kind: ReaderBlock.Kind = block.kind == "heading" ? .heading(min(6, max(2, block.level + 1))) : .paragraph
            items.append(ReaderBlock(id: items.count, kind: kind, text: block.text))
        }
        return items
    }
}

/// The text measured before it is sent (POST /api/restyle/analyze).
struct RestyleAnalysis: Codable, Equatable, Sendable {
    var language = "ar"
    var machine = RestyleResult.Machine()
    var windows: [RestyleResult.WindowScore] = []

    static func decode(_ data: Data) throws -> RestyleAnalysis {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(RestyleAnalysis.self, from: data)
    }
}

/// Passages of the text that read most like a person's (POST /api/restyle/sample).
struct RestyleSampleAnswer: Codable, Equatable, Sendable {
    struct Passage: Codable, Equatable, Identifiable, Sendable {
        var id: String
        var text: String
        var words: Int
        var why: [String] = []
    }

    var language = "ar"
    var passages: [Passage] = []
    var words = 0

    static func decode(_ data: Data) throws -> RestyleSampleAnswer {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(RestyleSampleAnswer.self, from: data)
    }
}

/// A blind comparison: the reader picks the version that reads more like a
/// person, without knowing which is which. The share that picked the edited
/// version comes with its 95% interval (Wilson), so a handful of answers is
/// not taken for a result.
struct BlindTest: Codable, Equatable, Sendable {
    struct Trial: Codable, Equatable, Identifiable, Sendable {
        var id: String           // block id
        var editedFirst: Bool
        var choseEdited: Bool?
    }

    var trials: [Trial] = []

    static func make<G: RandomNumberGenerator>(from result: RestyleResult, count: Int = 10,
                                               using generator: inout G) -> BlindTest {
        let changed = result.blocks.filter { $0.changed && $0.text.split(separator: " ").count >= 12 }
        let picked = changed.shuffled(using: &generator).prefix(count)
        return BlindTest(trials: picked.map { Trial(id: $0.id, editedFirst: Bool.random(using: &generator)) })
    }

    var answered: [Trial] { trials.filter { $0.choseEdited != nil } }
    var preferredEdited: Int { answered.filter { $0.choseEdited == true }.count }

    /// The share that preferred the edited version, and its 95% Wilson interval.
    var share: (value: Double, low: Double, high: Double)? {
        let n = Double(answered.count)
        guard n > 0 else { return nil }
        let p = Double(preferredEdited) / n
        let z = 1.96
        let centre = (p + z * z / (2 * n)) / (1 + z * z / n)
        let margin = z * ((p * (1 - p) / n + z * z / (4 * n * n)).squareRoot()) / (1 + z * z / n)
        return (p, max(0, centre - margin), min(1, centre + margin))
    }
}
