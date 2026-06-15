import Foundation

enum LearningActivityKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case lesson
    case review
    case listening
    case pronunciation
    case story
    case conversation
    case reading
    case writing
    case exam

    var id: String { rawValue }

    var titleAr: String {
        switch self {
        case .lesson: return "درس جديد"
        case .review: return "مراجعة كلمات"
        case .listening: return "تدريب استماع"
        case .pronunciation: return "تدريب نطق"
        case .story: return "قصة متدرجة"
        case .conversation: return "محادثة موقف"
        case .reading: return "قراءة وفهم"
        case .writing: return "تدريب كتابة"
        case .exam: return "تدريب اختبار"
        }
    }

    var systemImage: String {
        switch self {
        case .lesson: return "graduationcap.fill"
        case .review: return "rectangle.stack.fill"
        case .listening: return "headphones"
        case .pronunciation: return "waveform.and.mic"
        case .story: return "book.pages.fill"
        case .conversation: return "person.2.wave.2.fill"
        case .reading: return "book.fill"
        case .writing: return "pencil.line"
        case .exam: return "doc.text.magnifyingglass"
        }
    }
}

struct LearningPlanItem: Identifiable, Codable, Hashable {
    let id: String
    let kind: LearningActivityKind
    let titleAr: String
    let subtitleAr: String
    let estimatedMinutes: Int
    let referenceID: String?
    var isCompleted: Bool
}

struct DailyLearningPlan: Identifiable, Codable, Hashable {
    var id: Date { date.startOfDay }
    let date: Date
    let targetMinutes: Int
    var items: [LearningPlanItem]

    var completedMinutes: Int {
        items.filter(\.isCompleted).reduce(0) { $0 + $1.estimatedMinutes }
    }

    var progress: Double {
        guard !items.isEmpty else { return 0 }
        return Double(items.filter(\.isCompleted).count) / Double(items.count)
    }
}

struct SkillProgress: Codable, Hashable {
    var skill: LanguageSkill
    var attempts: Int = 0
    var correct: Int = 0
    var lastPracticedAt: Date?

    var accuracy: Double {
        guard attempts > 0 else { return 0 }
        return Double(correct) / Double(attempts)
    }
}

struct StoryProgress: Codable, Hashable {
    var storyID: String
    var completedAt: Date?
    var bestScore: Double = 0
    var endingsReached: [String] = []
}

struct LearningInsight: Identifiable, Hashable {
    let id: String
    let titleAr: String
    let valueAr: String
    let detailAr: String
    let systemImage: String
}

struct LearningInsights: Hashable {
    let totalMinutes: Int
    let completedLessons: Int
    let totalAttempts: Int
    let averageLessonScore: Double
    let dueVocabulary: Int
    let strongestSkill: SkillProgress?
    let focusSkill: SkillProgress?
    let activeDaysLast30: Int
    let insights: [LearningInsight]
}
