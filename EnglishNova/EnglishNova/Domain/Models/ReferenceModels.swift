import Foundation

struct GrammarTopic: Identifiable, Hashable {
    let id: String
    let level: CEFRLevel
    let titleAr: String
    let titleEn: String
    let summaryAr: String
    let formula: String
    let examples: [BilingualExample]
    let commonMistakes: [String]
}

struct BilingualExample: Identifiable, Hashable {
    let id = UUID()
    let english: String
    let arabic: String
}

struct GradedStory: Identifiable, Hashable {
    let id: String
    let level: CEFRLevel
    let titleAr: String
    let titleEn: String
    let paragraphs: [BilingualExample]
    let keyWords: [VocabularyWord]
    let questions: [StoryQuestion]
}

struct StoryQuestion: Identifiable, Hashable {
    let id: String
    let promptAr: String
    let choices: [String]
    let answer: String
}

struct AchievementDefinition: Identifiable, Hashable {
    let id: String
    let titleAr: String
    let descriptionAr: String
    let systemImage: String
    let requiredPoints: Int
}
