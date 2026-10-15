import Foundation

/// The reader's translation preferences. Each one is sent with a translation
/// task and changes the result on the server (basir/translation_prefs.py):
/// most as explicit rules for the AI, and the glossary and digit style are
/// also enforced in code after translation. The defaults reproduce Basir's
/// translation before these preferences existed.
struct TranslationPreferences: Codable, Equatable, Hashable, Sendable {
    enum Style: String, Codable, CaseIterable, Sendable { case faithful, natural, plain }
    enum Formality: String, Codable, CaseIterable, Sendable { case formal, neutral }
    enum Names: String, Codable, CaseIterable, Sendable { case keep, targetScript = "target_script" }
    enum Terms: String, Codable, CaseIterable, Sendable {
        case translate, translateWithOriginal = "translate_with_original", keep
    }
    enum Quotations: String, Codable, CaseIterable, Sendable {
        case keep, keepWithMeaning = "keep_with_meaning", translate
    }
    enum Numerals: String, Codable, CaseIterable, Sendable { case source, western, eastern }
    enum ImageText: String, Codable, CaseIterable, Sendable { case translate, keep }

    struct GlossaryEntry: Codable, Equatable, Hashable, Identifiable, Sendable {
        var id = UUID()
        var source: String
        var target: String

        enum CodingKeys: String, CodingKey { case source, target }
    }

    static let maximumGlossary = 60
    static let maximumTermLength = 80

    /// Empty: detect automatically.
    var sourceLanguage: String = ""
    var style: Style = .faithful
    var formality: Formality = .formal
    var names: Names = .keep
    var terms: Terms = .translate
    var quotations: Quotations = .keep
    var numerals: Numerals = .source
    var notes: Bool = false
    var imageText: ImageText = .translate
    var glossary: [GlossaryEntry] = []

    static let standard = TranslationPreferences()

    var isStandard: Bool {
        var copy = self
        copy.glossary = []
        return copy == .standard && usableGlossary.isEmpty
    }

    /// Entries with both sides filled in, trimmed, within the server's limits.
    var usableGlossary: [GlossaryEntry] {
        glossary.compactMap { entry in
            let source = String(entry.source.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumTermLength))
            let target = String(entry.target.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumTermLength))
            guard !source.isEmpty, !target.isEmpty, source != target else { return nil }
            return GlossaryEntry(id: entry.id, source: source, target: target)
        }
        .prefix(Self.maximumGlossary)
        .map { $0 }
    }

    /// What the server receives (snake_case, only usable glossary entries).
    var payload: Payload {
        Payload(sourceLanguage: sourceLanguage, style: style.rawValue, formality: formality.rawValue,
                names: names.rawValue, terms: terms.rawValue, quotations: quotations.rawValue,
                numerals: numerals.rawValue, notes: notes, imageText: imageText.rawValue,
                glossary: usableGlossary.map { Payload.Term(source: $0.source, target: $0.target) })
    }

    struct Payload: Encodable, Equatable, Sendable {
        struct Term: Encodable, Equatable, Sendable {
            let source: String
            let target: String
        }

        let sourceLanguage: String
        let style: String
        let formality: String
        let names: String
        let terms: String
        let quotations: String
        let numerals: String
        let notes: Bool
        let imageText: String
        let glossary: [Term]

        enum CodingKeys: String, CodingKey {
            case sourceLanguage = "source_language"
            case style, formality, names, terms, quotations, numerals, notes
            case imageText = "image_text"
            case glossary
        }
    }
}
