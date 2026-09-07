import Foundation

enum IELTSSection: String, Codable, CaseIterable, Identifiable, Hashable {
    case listening
    case reading
    case writing
    case speaking

    var id: String { rawValue }

    var titleAr: String {
        switch self {
        case .listening: return L("الاستماع")
        case .reading: return L("القراءة")
        case .writing: return L("الكتابة")
        case .speaking: return L("التحدث")
        }
    }

    var systemImage: String {
        switch self {
        case .listening: return "headphones"
        case .reading: return "book.fill"
        case .writing: return "pencil.line"
        case .speaking: return "waveform.and.mic"
        }
    }

    var practiceDomain: AdvancedSkillDomain {
        switch self {
        case .listening: return .listening
        case .reading: return .reading
        case .writing: return .writing
        case .speaking: return .speaking
        }
    }
}

enum IELTSPreparationPhase: String, Codable, CaseIterable, Identifiable, Hashable {
    case foundation
    case bridge
    case examSkills
    case bandSixSimulation

    var id: String { rawValue }

    var titleAr: String {
        switch self {
        case .foundation: return L("مرحلة التأسيس")
        case .bridge: return L("مرحلة الجسر إلى IELTS")
        case .examSkills: return L("مرحلة مهارات الاختبار")
        case .bandSixSimulation: return L("مرحلة محاكاة Band 6")
        }
    }

    var detailAr: String {
        switch self {
        case .foundation:
            return L("نبني الجملة والمفردات والاستماع الأساسي قبل ضغط أسئلة الاختبار.")
        case .bridge:
            return L("ننقل اللغة العامة إلى قراءة أطول وكتابة فقرات وتحدث ممتد.")
        case .examSkills:
            return L("نتدرب على أنواع أسئلة IELTS وإدارة الوقت ومعايير الكتابة والتحدث.")
        case .bandSixSimulation:
            return L("نكرر محاكاة مقننة ونغلق أضعف فجوة حتى تثبت الجاهزية.")
        }
    }

    var expectedRemainingWeeks: Int {
        switch self {
        case .foundation: return 36
        case .bridge: return 24
        case .examSkills: return 14
        case .bandSixSimulation: return 8
        }
    }
}

enum IELTSStudyArea: String, Codable, CaseIterable, Identifiable, Hashable {
    case course
    case vocabulary
    case listening
    case reading
    case writing
    case speaking
    case correction
    case mock

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .course: return "graduationcap.fill"
        case .vocabulary: return "rectangle.stack.fill"
        case .listening: return "headphones"
        case .reading: return "book.fill"
        case .writing: return "pencil.line"
        case .speaking: return "waveform.and.mic"
        case .correction: return "exclamationmark.bubble.fill"
        case .mock: return "timer"
        }
    }

    var activityKind: LearningActivityKind {
        switch self {
        case .course: return .lesson
        case .vocabulary, .correction: return .review
        case .listening: return .listening
        case .reading: return .reading
        case .writing: return .writing
        case .speaking: return .exam
        case .mock: return .exam
        }
    }
}

struct IELTSStudyBlock: Identifiable, Codable, Hashable {
    let id: String
    let area: IELTSStudyArea
    let titleAr: String
    let detailAr: String
    let minutes: Int
    let breakAfterMinutes: Int

    init(
        id: String,
        area: IELTSStudyArea,
        titleAr: String,
        detailAr: String,
        minutes: Int,
        breakAfterMinutes: Int = 5
    ) {
        self.id = id
        self.area = area
        self.titleAr = titleAr
        self.detailAr = detailAr
        self.minutes = max(1, minutes)
        self.breakAfterMinutes = max(0, breakAfterMinutes)
    }
}

struct IELTSSectionEstimate: Identifiable, Hashable {
    var id: IELTSSection { section }
    let section: IELTSSection
    let estimatedBand: Double?
    let confidence: Double
    let evidenceCount: Int
    let recentAverage: Double?
    let isSufficient: Bool
}

struct IELTSReadinessSnapshot: Hashable {
    let phase: IELTSPreparationPhase
    let targetBand: Double
    let sectionEstimates: [IELTSSectionEstimate]
    let overallBand: Double?
    let confidence: Double
    let isReadyForBandSix: Bool
    let blockersAr: [String]

    var hasCompleteEvidence: Bool {
        sectionEstimates.allSatisfy(\.isSufficient)
    }
}

struct IELTSRoadmapStage: Identifiable, Hashable {
    let id: String
    let weekRangeAr: String
    let titleAr: String
    let outcomeAr: String
    let checkpointAr: String
}

struct IELTSObjectiveModule: Identifiable, Hashable {
    let id: String
    let section: IELTSSection
    let titleAr: String
    let contextAr: String
    let sourceText: String
    let recommendedMinutes: Int
    let questions: [ComprehensionQuestion]
}

enum IELTSWritingTaskType: String, Codable, CaseIterable, Identifiable, Hashable {
    case academicTask1
    case task2

    var id: String { rawValue }

    var titleAr: String {
        switch self {
        case .academicTask1: return L("Academic Writing Task 1")
        case .task2: return L("Writing Task 2")
        }
    }

    var minimumWords: Int { self == .academicTask1 ? 150 : 250 }
    var recommendedMinutes: Int { self == .academicTask1 ? 20 : 40 }
}

struct IELTSWritingTask: Identifiable, Hashable {
    let id: String
    let type: IELTSWritingTaskType
    let prompt: String
    /// Complete textual equivalent of the visual input. This is required for
    /// screen-reader users and is the authoritative data for the response.
    let accessibleSourceDescription: String?
    let focusWords: [String]
    let checklistAr: [String]
}

struct IELTSWritingEvaluation: Hashable {
    let wordCount: Int
    let taskResponse: Double
    let coherenceAndCohesion: Double
    let lexicalResource: Double
    let grammaticalRangeAndAccuracy: Double
    let estimatedBand: Double
    let strengthsAr: [String]
    let improvementsAr: [String]
    let limitationsAr: String
}
