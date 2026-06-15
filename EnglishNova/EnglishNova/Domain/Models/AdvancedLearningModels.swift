import Foundation

enum StudyMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case balanced
    case exam
    case conversation
    case career
    case calm

    var id: String { rawValue }

    var titleAr: String {
        switch self {
        case .balanced: return "متوازن"
        case .exam: return "استعداد للاختبارات"
        case .conversation: return "محادثة وطلاقة"
        case .career: return "عمل ومقابلات"
        case .calm: return "هادئ ومختصر"
        }
    }

    var detailAr: String {
        switch self {
        case .balanced: return "يمزج الدروس والمراجعة والاستماع والكتابة دون تغليب مهارة واحدة."
        case .exam: return "يرفع أولوية القراءة والقواعد والكتابة وأسئلة IELTS وSTEP."
        case .conversation: return "يركز على الاستماع والنطق والرد السريع في المواقف اليومية."
        case .career: return "يركز على البريد المهني والاجتماعات والمقابلات والقانون والحوكمة."
        case .calm: return "يختار أقل عدد من الأنشطة مع الحفاظ على الاستمرارية."
        }
    }
}

enum LearningPathwayID: String, Codable, CaseIterable, Identifiable, Hashable {
    case foundations
    case dailyFluency
    case academicIELTS
    case stepMastery
    case careerEnglish
    case legalGovernance

    var id: String { rawValue }

    var titleAr: String {
        switch self {
        case .foundations: return "تأسيس من الصفر"
        case .dailyFluency: return "الطلاقة اليومية"
        case .academicIELTS: return "المسار الأكاديمي وIELTS"
        case .stepMastery: return "إتقان STEP"
        case .careerEnglish: return "الإنجليزية المهنية"
        case .legalGovernance: return "القانون والحوكمة"
        }
    }

    var systemImage: String {
        switch self {
        case .foundations: return "building.columns.fill"
        case .dailyFluency: return "bubble.left.and.bubble.right.fill"
        case .academicIELTS: return "text.book.closed.fill"
        case .stepMastery: return "checkmark.seal.fill"
        case .careerEnglish: return "briefcase.fill"
        case .legalGovernance: return "scalemass.fill"
        }
    }
}

enum AdvancedSkillDomain: String, Codable, CaseIterable, Identifiable, Hashable {
    case reading
    case listening
    case writing
    case speaking
    case grammar
    case vocabulary

    var id: String { rawValue }

    var titleAr: String {
        switch self {
        case .reading: return "القراءة"
        case .listening: return "الاستماع"
        case .writing: return "الكتابة"
        case .speaking: return "التحدث"
        case .grammar: return "القواعد"
        case .vocabulary: return "المفردات"
        }
    }

    var systemImage: String {
        switch self {
        case .reading: return "book.fill"
        case .listening: return "headphones"
        case .writing: return "pencil.line"
        case .speaking: return "waveform.and.mic"
        case .grammar: return "textformat"
        case .vocabulary: return "character.book.closed.fill"
        }
    }

    var languageSkill: LanguageSkill {
        switch self {
        case .reading: return .reading
        case .listening: return .listening
        case .writing, .grammar: return .grammar
        case .speaking: return .practicalCommunication
        case .vocabulary: return .vocabulary
        }
    }
}

struct PracticeSessionRecord: Codable, Hashable, Identifiable {
    let id: String
    let domain: AdvancedSkillDomain
    let sourceID: String
    let titleAr: String
    let level: CEFRLevel
    let score: Double
    let minutes: Int
    let createdAt: Date
    let details: [String]
}

struct KnowledgeState: Codable, Hashable, Identifiable {
    var id: String { itemID }
    let itemID: String
    var difficulty: Double
    var stabilityDays: Double
    var successes: Int
    var lapses: Int
    var lastReviewedAt: Date?
    var nextReviewAt: Date

    init(
        itemID: String,
        difficulty: Double = 5,
        stabilityDays: Double = 1,
        successes: Int = 0,
        lapses: Int = 0,
        lastReviewedAt: Date? = nil,
        nextReviewAt: Date = .now
    ) {
        self.itemID = itemID
        self.difficulty = difficulty
        self.stabilityDays = stabilityDays
        self.successes = successes
        self.lapses = lapses
        self.lastReviewedAt = lastReviewedAt
        self.nextReviewAt = nextReviewAt
    }
}

struct LearningPathwayMilestone: Codable, Hashable, Identifiable {
    let id: String
    let titleAr: String
    let detailAr: String
    let requiredSessions: Int
    let requiredAverageScore: Double
    let requiredDomains: [AdvancedSkillDomain]
}

struct LearningPathwayDefinition: Hashable, Identifiable {
    let id: LearningPathwayID
    let titleAr: String
    let detailAr: String
    let targetLevel: CEFRLevel
    let estimatedWeeks: Int
    let milestones: [LearningPathwayMilestone]
}

struct LearningPathwayProgress: Hashable {
    let pathway: LearningPathwayDefinition
    let completedMilestones: Int
    let totalMilestones: Int
    let overallProgress: Double
    let currentMilestone: LearningPathwayMilestone?
    let currentMilestoneProgress: Double
}

struct ComprehensionQuestion: Codable, Hashable, Identifiable {
    let id: String
    let prompt: String
    let promptAr: String
    let choices: [String]
    let answer: String
    let explanationAr: String
}

struct ReadingPassage: Hashable, Identifiable {
    let id: String
    let level: CEFRLevel
    let title: String
    let titleAr: String
    let text: String
    let estimatedMinutes: Int
    let topicAr: String
    let questions: [ComprehensionQuestion]
}

struct ListeningPassage: Hashable, Identifiable {
    let id: String
    let level: CEFRLevel
    let titleAr: String
    let transcript: String
    let contextAr: String
    let recommendedReplays: Int
    let questions: [ComprehensionQuestion]
}

enum WritingPromptKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case sentence
    case message
    case email
    case paragraph
    case opinion
    case report

    var id: String { rawValue }

    var titleAr: String {
        switch self {
        case .sentence: return "جمل قصيرة"
        case .message: return "رسالة يومية"
        case .email: return "بريد إلكتروني"
        case .paragraph: return "فقرة مترابطة"
        case .opinion: return "رأي وحجة"
        case .report: return "تقرير مهني"
        }
    }
}

struct WritingPrompt: Hashable, Identifiable {
    let id: String
    let level: CEFRLevel
    let kind: WritingPromptKind
    let titleAr: String
    let prompt: String
    let promptAr: String
    let minimumWords: Int
    let suggestedWords: [String]
    let checklistAr: [String]
    let sampleAnswer: String
}

struct WritingEvaluation: Codable, Hashable {
    let wordCount: Int
    let taskAchievement: Double
    let organization: Double
    let languageRange: Double
    let mechanics: Double
    let overall: Double
    let strengthsAr: [String]
    let improvementsAr: [String]
    let detectedConnectors: [String]
    let repeatedWords: [String]
}

struct WeeklyLearningReport: Hashable {
    let startDate: Date
    let endDate: Date
    let activeDays: Int
    let totalMinutes: Int
    let completedLessons: Int
    let practiceSessions: Int
    let averagePracticeScore: Double
    let dueReviewCount: Int
    let strongestDomain: AdvancedSkillDomain?
    let focusDomain: AdvancedSkillDomain?
    let narrativeAr: String
    let nextWeekActions: [String]

    var shareText: String {
        var lines = [
            "تقرير EnglishNova الأسبوعي",
            "الفترة: \(startDate.formatted(date: .abbreviated, time: .omitted)) إلى \(endDate.formatted(date: .abbreviated, time: .omitted))",
            "الأيام النشطة: \(activeDays)",
            "وقت التعلم: \(totalMinutes) دقيقة",
            "الدروس المكتملة: \(completedLessons)",
            "جلسات المهارات: \(practiceSessions)",
            "متوسط جلسات المهارات: \(Int(averagePracticeScore * 100))٪",
            "المراجعات المستحقة: \(dueReviewCount)",
            narrativeAr,
            "خطوات الأسبوع القادم:"
        ]
        lines.append(contentsOf: nextWeekActions.enumerated().map { "\($0.offset + 1). \($0.element)" })
        return lines.joined(separator: "\n")
    }
}
