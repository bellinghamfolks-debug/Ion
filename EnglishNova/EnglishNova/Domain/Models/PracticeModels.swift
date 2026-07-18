import Foundation

struct ConversationScenario: Identifiable, Hashable {
    let id: String
    let level: CEFRLevel
    let titleAr: String
    let titleEn: String
    let roleAr: String
    let openingLine: String
    let openingLineAr: String
    let turns: [ConversationTurn]
}

struct ConversationTurn: Identifiable, Hashable {
    let id: String
    let promptAr: String
    let expectedIdeas: [String]
    let sampleAnswer: String
    let responseOnSuccess: String
    let responseOnRetry: String
}

struct ConversationEvaluation: Hashable {
    let score: Double
    let matchedIdeas: [String]
    let feedbackAr: String
}

struct DictationPrompt: Identifiable, Hashable {
    let id: String
    let level: CEFRLevel
    let sentence: String
    let translationAr: String
}

// MARK: - Batch 3: pronunciation and adaptive coaching

enum AccentVariant: String, Codable, CaseIterable, Identifiable, Hashable {
    case american
    case british

    var id: String { rawValue }

    var titleAr: String {
        switch self {
        case .american: return L("أمريكية")
        case .british: return L("بريطانية")
        }
    }

    var titleEn: String {
        switch self {
        case .american: return "American English"
        case .british: return "British English"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .american: return "en-US"
        case .british: return "en-GB"
        }
    }
}

struct SpeechSegmentSnapshot: Codable, Hashable, Identifiable {
    var id: String { "\(timestamp)-\(text)" }
    let text: String
    let timestamp: TimeInterval
    let duration: TimeInterval
    let confidence: Float
}

enum PronunciationIssueKind: String, Codable, Hashable {
    case accurate
    case close
    case substituted
    case omitted
    case extra

    var titleAr: String {
        switch self {
        case .accurate: return L("دقيق")
        case .close: return L("قريب")
        case .substituted: return L("استبدال")
        case .omitted: return L("محذوف")
        case .extra: return L("إضافة")
        }
    }

    var systemImage: String {
        switch self {
        case .accurate: return "checkmark.circle.fill"
        case .close: return "checkmark.circle"
        case .substituted: return "arrow.left.arrow.right.circle"
        case .omitted: return "minus.circle"
        case .extra: return "plus.circle"
        }
    }
}

struct WordPronunciationResult: Codable, Hashable, Identifiable {
    let id: String
    let expected: String
    let recognized: String?
    let similarity: Double
    let issue: PronunciationIssueKind
    let tipAr: String?
}

struct PronunciationReport: Codable, Hashable, Identifiable {
    let id: String
    let target: String
    let recognized: String
    let accent: AccentVariant
    let createdAt: Date
    let accuracy: Double
    let completeness: Double
    let fluency: Double
    let overall: Double
    let wordsPerMinute: Double
    let words: [WordPronunciationResult]
    let tipsAr: [String]

    var needsPractice: [WordPronunciationResult] {
        words.filter { $0.issue != .accurate && $0.issue != .extra }
    }
}

struct LearningMistake: Codable, Hashable, Identifiable {
    let id: String
    let category: String
    let source: String
    let prompt: String
    let learnerAnswer: String
    let correction: String
    let explanationAr: String
    let createdAt: Date
    var reviewCount: Int
    var resolved: Bool
}

struct ConversationMemoryEntry: Codable, Hashable, Identifiable {
    let id: String
    let scenarioID: String
    let scenarioTitle: String
    let transcript: String
    let reply: String
    let score: Double
    let createdAt: Date
}

enum ExamTrack: String, Codable, CaseIterable, Identifiable, Hashable {
    case ieltsSpeaking
    case step
    case workplace

    var id: String { rawValue }

    var titleAr: String {
        switch self {
        case .ieltsSpeaking: return "IELTS Speaking"
        case .step: return L("اختبار STEP")
        case .workplace: return L("الإنجليزية المهنية")
        }
    }

    var detailAr: String {
        switch self {
        case .ieltsSpeaking: return L("تدريب على الطلاقة، الترابط، المفردات، وإجابة السؤال مباشرة.")
        case .step: return L("مفردات وقواعد وقراءة بأسلوب اختيار من متعدد.")
        case .workplace: return L("رسائل واجتماعات ومواقف عملية باللغة الإنجليزية.")
        }
    }
}

enum ExamQuestionKind: String, Codable, Hashable {
    case multipleChoice
    case speaking
}

struct ExamQuestion: Codable, Hashable, Identifiable {
    let id: String
    let track: ExamTrack
    let level: CEFRLevel
    let kind: ExamQuestionKind
    let prompt: String
    let promptAr: String
    let choices: [String]
    let answer: String?
    let keywords: [String]
    let explanationAr: String
}

struct ExamAttempt: Codable, Hashable, Identifiable {
    let id: String
    let track: ExamTrack
    let score: Double
    let answered: Int
    let correct: Int
    let createdAt: Date
    let notesAr: [String]
}

enum InterviewCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case introduction
    case behavioral
    case legalGovernance
    case difficult

    var id: String { rawValue }

    var titleAr: String {
        switch self {
        case .introduction: return L("التعريف والخلفية")
        case .behavioral: return L("الأسئلة السلوكية")
        case .legalGovernance: return L("القانون والحوكمة")
        case .difficult: return L("الأسئلة الصعبة")
        }
    }
}

struct InterviewQuestion: Hashable, Identifiable {
    let id: String
    let category: InterviewCategory
    let level: CEFRLevel
    let question: String
    let questionAr: String
    let expectedIdeas: [String]
    let sampleAnswer: String
    let coachingPointsAr: [String]
}

struct InterviewEvaluation: Codable, Hashable {
    let relevance: Double
    let structure: Double
    let language: Double
    let overall: Double
    let matchedIdeas: [String]
    let feedbackAr: [String]
}

struct VoiceCoachRequest: Codable, Hashable {
    let sessionID: String
    let scenarioID: String
    let level: CEFRLevel
    let accent: AccentVariant
    let prompt: String
    let learnerTranscript: String
    let localScore: Double
    let previousTurns: [ConversationMemoryEntry]
}

struct VoiceCoachReply: Codable, Hashable {
    let reply: String
    let translationAr: String?
    let feedbackAr: String
    let suggestedAnswer: String?
    let source: String
}

struct LearnerMemorySnapshot: Codable, Hashable {
    var pronunciationReports: [PronunciationReport] = []
    var mistakes: [LearningMistake] = []
    var conversations: [ConversationMemoryEntry] = []
    var examAttempts: [ExamAttempt] = []
    var interviewAttempts: [ExamAttempt] = []

    enum CodingKeys: String, CodingKey {
        case pronunciationReports, mistakes, conversations, examAttempts, interviewAttempts
    }

    init(
        pronunciationReports: [PronunciationReport] = [],
        mistakes: [LearningMistake] = [],
        conversations: [ConversationMemoryEntry] = [],
        examAttempts: [ExamAttempt] = [],
        interviewAttempts: [ExamAttempt] = []
    ) {
        self.pronunciationReports = pronunciationReports
        self.mistakes = mistakes
        self.conversations = conversations
        self.examAttempts = examAttempts
        self.interviewAttempts = interviewAttempts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pronunciationReports = try container.decodeIfPresent([PronunciationReport].self, forKey: .pronunciationReports) ?? []
        mistakes = try container.decodeIfPresent([LearningMistake].self, forKey: .mistakes) ?? []
        conversations = try container.decodeIfPresent([ConversationMemoryEntry].self, forKey: .conversations) ?? []
        examAttempts = try container.decodeIfPresent([ExamAttempt].self, forKey: .examAttempts) ?? []
        interviewAttempts = try container.decodeIfPresent([ExamAttempt].self, forKey: .interviewAttempts) ?? []
    }
}

struct PersonalizedRecommendation: Identifiable, Hashable {
    let id: String
    let titleAr: String
    let detailAr: String
    let systemImage: String
    let destination: RecommendationDestination
    let priority: Int
}

enum RecommendationDestination: String, Hashable {
    case pronunciation
    case mistakes
    case review
    case conversation
    case exam
    case lesson
}
