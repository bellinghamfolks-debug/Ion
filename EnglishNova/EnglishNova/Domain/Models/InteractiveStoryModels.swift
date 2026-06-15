import Foundation

struct InteractiveStory: Identifiable, Hashable {
    let id: String
    let level: CEFRLevel
    let titleAr: String
    let titleEn: String
    let summaryAr: String
    let startSceneID: String
    let scenes: [StoryScene]
    let keyWords: [VocabularyWord]

    func scene(id: String) -> StoryScene? { scenes.first { $0.id == id } }
}

struct StoryScene: Identifiable, Hashable {
    let id: String
    let english: String
    let arabic: String
    let narratorHintAr: String?
    let choices: [StoryChoice]
    let ending: StoryEnding?
}

struct StoryChoice: Identifiable, Hashable {
    let id: String
    let english: String
    let arabic: String
    let nextSceneID: String
    let points: Int
    let feedbackAr: String
}

struct StoryEnding: Hashable {
    let id: String
    let titleAr: String
    let messageAr: String
}
