import Foundation

struct CourseCatalog: Codable {
    var version: Int
    var levels: [CourseLevel]
}

struct CourseLevel: Codable, Identifiable, Hashable {
    var id: String
    var level: CEFRLevel
    var titleAr: String
    var titleEn: String
    var descriptionAr: String
    var units: [CourseUnit]
}

struct CourseUnit: Codable, Identifiable, Hashable {
    var id: String
    var order: Int
    var titleAr: String
    var titleEn: String
    var descriptionAr: String
    var icon: String
    var lessons: [Lesson]
}

struct Lesson: Codable, Identifiable, Hashable {
    var id: String
    var order: Int
    var titleAr: String
    var titleEn: String
    var objectiveAr: String
    var estimatedMinutes: Int
    var points: Int
    var vocabulary: [VocabularyWord]
    var exercises: [Exercise]
}

struct VocabularyWord: Codable, Identifiable, Hashable {
    var id: String
    var english: String
    var arabic: String
    var example: String
    var exampleArabic: String
    var partOfSpeech: String
    var phonetic: String?
}
