import Foundation

enum ExerciseType: String, Codable {
    case explanation
    case multipleChoice
    case fillBlank
    case arrangeWords
    case flashcard
    case listenAndChoose
    case speak
    case translation
    // 2.0: generated on device from the lesson's own vocabulary (see ExerciseSynthesizer).
    case matchPairs
    case listenType
    case dictation
    case trueFalse

    /// Informational items are shown but never graded.
    var isGraded: Bool { self != .explanation && self != .flashcard }

    /// Items whose answer is typed on the keyboard.
    var isTyped: Bool {
        switch self {
        case .fillBlank, .translation, .listenType, .dictation: return true
        default: return false
        }
    }

    /// Items that start with audio, so Magic Tap and auto-play should replay it.
    var startsWithAudio: Bool {
        switch self {
        case .listenAndChoose, .listenType, .dictation, .speak: return true
        default: return false
        }
    }
}

struct Exercise: Codable, Identifiable, Hashable {
    var id: String
    var type: ExerciseType
    var promptAr: String
    var promptEn: String?
    var answer: String
    var choices: [String]?
    var tokens: [String]?
    var explanationAr: String
    var accessibilityHint: String
    var speechText: String?
    var acceptableAnswers: [String]?

    /// Synthesized items carry already-localized copy and learner-facing
    /// content (English words, Arabic meanings) that must not go through `L()`.
    var isSynthesized: Bool { id.hasPrefix("syn-") }

    func isCorrect(_ response: String) -> Bool {
        switch type {
        case .matchPairs:
            return Self.pairs(from: response) == Self.pairs(from: answer)
        case .multipleChoice, .listenAndChoose, .trueFalse:
            // Selected options are exact values, not approximate typed answers.
            // Fuzzy matching can accept a distractor that differs by a negation.
            return response == answer
        default:
            let answers = [answer] + (acceptableAnswers ?? [])
            return answers.contains { StringSimilarity.score($0, response) >= 0.88 }
        }
    }

    /// `matchPairs` answers are encoded as `english=arabic|english=arabic`.
    static func pairs(from encoded: String) -> [String: String] {
        var result: [String: String] = [:]
        for item in encoded.split(separator: "|") {
            let parts = item.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { continue }
            result[parts[0]] = parts[1]
        }
        return result
    }

    static func encodePairs(_ pairs: [(String, String)]) -> String {
        pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "|")
    }
}

extension ExerciseType {
    /// The skill a single answer of this type provides evidence for.
    var practicedSkill: LanguageSkill {
        switch self {
        case .listenAndChoose, .listenType, .dictation: return .listening
        case .speak: return .practicalCommunication
        case .translation, .arrangeWords, .fillBlank: return .grammar
        case .multipleChoice, .flashcard, .matchPairs, .trueFalse: return .vocabulary
        case .explanation: return .reading
        }
    }
}
