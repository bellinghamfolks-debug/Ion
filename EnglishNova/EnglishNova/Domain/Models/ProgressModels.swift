import Foundation

struct LessonProgress: Codable, Identifiable, Hashable {
    var id: String { lessonID }
    var lessonID: String
    var completedAt: Date?
    var bestScore: Double
    var attempts: Int
    var earnedPoints: Int
}

struct DailyActivity: Codable, Identifiable, Hashable {
    var id: Date { date.startOfDay }
    var date: Date
    var minutes: Int
    var exercises: Int
    var points: Int
}

struct UserProgressSnapshot: Codable {
    var lessons: [String: LessonProgress] = [:]
    var activity: [DailyActivity] = []
    var skills: [LanguageSkill: SkillProgress] = [:]
    var stories: [String: StoryProgress] = [:]
    var lastPlacementResult: PlacementResult?
    var practiceSessions: [PracticeSessionRecord] = []
    var knowledgeStates: [String: KnowledgeState] = [:]

    enum CodingKeys: String, CodingKey {
        case lessons, activity, skills, stories, lastPlacementResult
        case practiceSessions, knowledgeStates
    }

    init(
        lessons: [String: LessonProgress] = [:],
        activity: [DailyActivity] = [],
        skills: [LanguageSkill: SkillProgress] = [:],
        stories: [String: StoryProgress] = [:],
        lastPlacementResult: PlacementResult? = nil,
        practiceSessions: [PracticeSessionRecord] = [],
        knowledgeStates: [String: KnowledgeState] = [:]
    ) {
        self.lessons = lessons
        self.activity = activity
        self.skills = skills
        self.stories = stories
        self.lastPlacementResult = lastPlacementResult
        self.practiceSessions = practiceSessions
        self.knowledgeStates = knowledgeStates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lessons = try container.decodeIfPresent([String: LessonProgress].self, forKey: .lessons) ?? [:]
        activity = try container.decodeIfPresent([DailyActivity].self, forKey: .activity) ?? []
        skills = try container.decodeIfPresent([LanguageSkill: SkillProgress].self, forKey: .skills) ?? [:]
        stories = try container.decodeIfPresent([String: StoryProgress].self, forKey: .stories) ?? [:]
        lastPlacementResult = try container.decodeIfPresent(PlacementResult.self, forKey: .lastPlacementResult)
        practiceSessions = try container.decodeIfPresent([PracticeSessionRecord].self, forKey: .practiceSessions) ?? []
        knowledgeStates = try container.decodeIfPresent([String: KnowledgeState].self, forKey: .knowledgeStates) ?? [:]
    }
}

struct ReviewCard: Codable, Identifiable, Hashable {
    var id: String { word.id }
    var word: VocabularyWord
    var repetitions: Int = 0
    var intervalDays: Int = 0
    var easeFactor: Double = 2.5
    var dueDate: Date = .now
    var lastReviewedAt: Date?
    var addedAt: Date = .now
    var isFavorite: Bool = false
    var tags: [String] = []
    var note: String = ""
    var confidence: Double = 0
    var difficulty: Double = 5
    var stabilityDays: Double = 1
    var lapses: Int = 0
    var scheduledIntervalDays: Double = 0
    var lastGradeRaw: Int?

    enum CodingKeys: String, CodingKey {
        case word, repetitions, intervalDays, easeFactor, dueDate, lastReviewedAt
        case addedAt, isFavorite, tags, note, confidence
        case difficulty, stabilityDays, lapses, scheduledIntervalDays, lastGradeRaw
    }

    init(
        word: VocabularyWord,
        repetitions: Int = 0,
        intervalDays: Int = 0,
        easeFactor: Double = 2.5,
        dueDate: Date = .now,
        lastReviewedAt: Date? = nil,
        addedAt: Date = .now,
        isFavorite: Bool = false,
        tags: [String] = [],
        note: String = "",
        confidence: Double = 0,
        difficulty: Double = 5,
        stabilityDays: Double = 1,
        lapses: Int = 0,
        scheduledIntervalDays: Double = 0,
        lastGradeRaw: Int? = nil
    ) {
        self.word = word
        self.repetitions = repetitions
        self.intervalDays = intervalDays
        self.easeFactor = easeFactor
        self.dueDate = dueDate
        self.lastReviewedAt = lastReviewedAt
        self.addedAt = addedAt
        self.isFavorite = isFavorite
        self.tags = tags
        self.note = note
        self.confidence = confidence
        self.difficulty = difficulty
        self.stabilityDays = stabilityDays
        self.lapses = lapses
        self.scheduledIntervalDays = scheduledIntervalDays
        self.lastGradeRaw = lastGradeRaw
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        word = try container.decode(VocabularyWord.self, forKey: .word)
        repetitions = try container.decodeIfPresent(Int.self, forKey: .repetitions) ?? 0
        intervalDays = try container.decodeIfPresent(Int.self, forKey: .intervalDays) ?? 0
        easeFactor = try container.decodeIfPresent(Double.self, forKey: .easeFactor) ?? 2.5
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate) ?? .now
        lastReviewedAt = try container.decodeIfPresent(Date.self, forKey: .lastReviewedAt)
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? .now
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
        difficulty = min(10, max(1, try container.decodeIfPresent(Double.self, forKey: .difficulty) ?? 5))
        stabilityDays = min(365, max(0.15, try container.decodeIfPresent(Double.self, forKey: .stabilityDays) ?? max(1, Double(intervalDays))))
        lapses = max(0, try container.decodeIfPresent(Int.self, forKey: .lapses) ?? 0)
        scheduledIntervalDays = min(365, max(0, try container.decodeIfPresent(Double.self, forKey: .scheduledIntervalDays) ?? Double(intervalDays)))
        lastGradeRaw = try container.decodeIfPresent(Int.self, forKey: .lastGradeRaw)
    }

    func estimatedRetrievability(at date: Date = .now) -> Double {
        AdaptiveReviewEngine.retrievability(for: self, at: date)
    }
}

enum ReviewGrade: Int, CaseIterable {
    case again = 0
    case hard = 3
    case good = 4
    case easy = 5

    var titleAr: String {
        switch self {
        case .again: return L("إعادة")
        case .hard: return L("صعب")
        case .good: return L("جيد")
        case .easy: return L("سهل")
        }
    }
}
