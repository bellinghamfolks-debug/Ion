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

    func isCorrect(_ response: String) -> Bool {
        let answers = [answer] + (acceptableAnswers ?? [])
        return answers.contains { StringSimilarity.score($0, response) >= 0.88 }
    }
}
