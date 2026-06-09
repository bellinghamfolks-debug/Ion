import Foundation

enum LanguageSkill: String, Codable, CaseIterable, Identifiable, Hashable {
    case vocabulary
    case grammar
    case reading
    case listening
    case practicalCommunication

    var id: String { rawValue }

    var titleAr: String {
        switch self {
        case .vocabulary: return "المفردات"
        case .grammar: return "القواعد"
        case .reading: return "القراءة"
        case .listening: return "الاستماع"
        case .practicalCommunication: return "التواصل العملي"
        }
    }

    var systemImage: String {
        switch self {
        case .vocabulary: return "character.book.closed.fill"
        case .grammar: return "textformat"
        case .reading: return "book.fill"
        case .listening: return "headphones"
        case .practicalCommunication: return "bubble.left.and.bubble.right.fill"
        }
    }
}

// Make `[LanguageSkill: T]` dictionaries serialize as a JSON object keyed by
// the skill's rawValue (e.g. {"reading": …}) instead of the default
// alternating-array form Swift uses for non-String/Int keys. This keeps the
// persisted progress shape consistent with the String-keyed collections and
// lets an empty `{}` decode cleanly during migration.
extension LanguageSkill: CodingKeyRepresentable {
    private struct SkillCodingKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    var codingKey: CodingKey { SkillCodingKey(stringValue: rawValue) }

    init?<T: CodingKey>(codingKey: T) {
        self.init(rawValue: codingKey.stringValue)
    }
}

struct PlacementQuestion: Identifiable, Codable, Hashable {
    let id: String
    let level: CEFRLevel
    let skill: LanguageSkill
    let prompt: String
    let promptAr: String?
    let choices: [String]
    let answer: String
    let explanationAr: String
    let speechText: String?
    let discrimination: Double
}

struct PlacementResponse: Codable, Hashable {
    let questionID: String
    let level: CEFRLevel
    let skill: LanguageSkill
    let selectedAnswer: String
    let wasCorrect: Bool
    let answeredAt: Date
}

struct PlacementSkillResult: Identifiable, Codable, Hashable {
    var id: LanguageSkill { skill }
    let skill: LanguageSkill
    let score: Double
    let answered: Int
}

struct PlacementResult: Codable, Hashable {
    let recommendedLevel: CEFRLevel
    let ability: Double
    let confidence: Double
    let responses: [PlacementResponse]
    let skills: [PlacementSkillResult]
    let completedAt: Date

    var correctCount: Int { responses.filter(\.wasCorrect).count }
}
