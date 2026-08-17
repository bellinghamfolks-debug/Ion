import Foundation

protocol CourseRepositoryProtocol {
    func catalog() async throws -> CourseCatalog
    func refresh() async throws -> CourseCatalog
    func lesson(id: String) async throws -> Lesson?
}

protocol ProgressRepositoryProtocol {
    func snapshot() async -> UserProgressSnapshot
    func recordLesson(lessonID: String, score: Double, passed: Bool, points: Int, minutes: Int) async
    func progress(for lessonID: String) async -> LessonProgress?
    func recordLessonReview(lessonID: String, score: Double, minutes: Int, points: Int, at date: Date) async -> LessonReviewState
    func recordSkill(_ skill: LanguageSkill, correct: Bool, at date: Date) async
    func recordStory(storyID: String, score: Double, endingID: String) async
    func savePlacementResult(_ result: PlacementResult) async
    func recordPracticeSession(_ session: PracticeSessionRecord) async
    func recordKnowledge(itemID: String, score: Double, at date: Date) async
    func replace(with snapshot: UserProgressSnapshot) async
}

protocol VocabularyRepositoryProtocol {
    func add(words: [VocabularyWord]) async
    func dueCards(on date: Date) async -> [ReviewCard]
    func grade(cardID: String, grade: ReviewGrade, now: Date) async
    func allCards() async -> [ReviewCard]
    func updateMetadata(cardID: String, isFavorite: Bool, tags: [String], note: String) async
    func remove(cardID: String) async
    func replace(with cards: [ReviewCard]) async
}

protocol TutorRepositoryProtocol {
    func reply(to message: String, sessionID: String, level: CEFRLevel, locale: String, context: String?) async throws -> TutorMessage
}

protocol LearningMemoryRepositoryProtocol {
    func snapshot() async -> LearnerMemorySnapshot
    func recordPronunciation(_ report: PronunciationReport) async
    func recordMistake(_ mistake: LearningMistake) async
    func recordConversation(_ entry: ConversationMemoryEntry) async
    func recordExamAttempt(_ attempt: ExamAttempt) async
    func recordInterviewAttempt(_ attempt: ExamAttempt) async
    func markMistakeResolved(id: String, resolved: Bool) async
    func replace(with snapshot: LearnerMemorySnapshot) async
}

protocol VoiceCoachRepositoryProtocol {
    func reply(to request: VoiceCoachRequest) async throws -> VoiceCoachReply
}
