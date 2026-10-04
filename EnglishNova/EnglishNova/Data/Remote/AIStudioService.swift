import Foundation

// MARK: - Models

struct ExplainResult: Decodable {
    let explanationAr: String
    let exampleEn: String?
    var cached: Bool? = nil
}

struct WritingCorrection: Decodable, Hashable, Identifiable {
    let original: String
    let replacement: String
    let reasonAr: String
    var id: String { "\(original)|\(replacement)" }
}

/// Four-part writing rubric, each 0–100 for the learner's CEFR level.
struct WritingRubric: Decodable, Hashable {
    let taskAchievement: Int?
    let coherence: Int?
    let vocabulary: Int?
    let grammar: Int?
}

/// Writing genres the coach can judge against (sent as `taskType`).
enum WritingTaskType: String, CaseIterable, Identifiable {
    case free, email, opinion, story, description
    case ieltsTask2 = "ielts_task2"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: return LE("كتابة حرة", "Free writing")
        case .email: return LE("رسالة أو بريد", "Email or message")
        case .opinion: return LE("رأي", "Opinion")
        case .story: return LE("قصة", "Story")
        case .description: return LE("وصف", "Description")
        case .ieltsTask2: return LE("IELTS مهمة 2", "IELTS Task 2")
        }
    }
}

struct WritingResult: Decodable {
    let corrected: String
    let feedbackAr: String
    let score: Int?
    let strengthsAr: [String]
    let improvementsAr: [String]
    let corrections: [WritingCorrection]
    let nextTaskEn: String?
    let rubric: WritingRubric?
    let revisionAr: String?

    private enum CodingKeys: String, CodingKey {
        case corrected, feedbackAr, score, strengthsAr, improvementsAr, corrections, nextTaskEn, rubric, revisionAr
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        corrected = try container.decodeIfPresent(String.self, forKey: .corrected) ?? ""
        feedbackAr = try container.decodeIfPresent(String.self, forKey: .feedbackAr) ?? ""
        score = try container.decodeIfPresent(Int.self, forKey: .score)
        strengthsAr = try container.decodeIfPresent([String].self, forKey: .strengthsAr) ?? []
        improvementsAr = try container.decodeIfPresent([String].self, forKey: .improvementsAr) ?? []
        corrections = try container.decodeIfPresent([WritingCorrection].self, forKey: .corrections) ?? []
        nextTaskEn = try container.decodeIfPresent(String.self, forKey: .nextTaskEn)
        rubric = try container.decodeIfPresent(WritingRubric.self, forKey: .rubric)
        revisionAr = try container.decodeIfPresent(String.self, forKey: .revisionAr)
    }
}

struct ExplainTextVocabulary: Decodable, Hashable, Identifiable {
    let term: String
    let meaningAr: String
    let exampleEn: String?
    var id: String { term }
}

struct ExplainTextGrammar: Decodable, Hashable, Identifiable {
    let pointAr: String
    let exampleEn: String?
    var id: String { pointAr }
}

/// Explanation of a passage the learner photographed or pasted.
struct ExplainTextResult: Decodable {
    let translationAr: String
    let summaryAr: String
    let simplifiedEn: String?
    let vocabulary: [ExplainTextVocabulary]
    let grammar: [ExplainTextGrammar]

    private enum CodingKeys: String, CodingKey { case translationAr, summaryAr, simplifiedEn, vocabulary, grammar }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        translationAr = try container.decodeIfPresent(String.self, forKey: .translationAr) ?? ""
        summaryAr = try container.decodeIfPresent(String.self, forKey: .summaryAr) ?? ""
        simplifiedEn = try container.decodeIfPresent(String.self, forKey: .simplifiedEn)
        vocabulary = try container.decodeIfPresent([ExplainTextVocabulary].self, forKey: .vocabulary) ?? []
        grammar = try container.decodeIfPresent([ExplainTextGrammar].self, forKey: .grammar) ?? []
    }
}

/// Today's AI budget for the signed-in learner.
struct AIQuota: Decodable, Hashable {
    let dailyUnits: Int
    let usedUnits: Int
    let remainingUnits: Int
    let resetsAt: String?
}

struct ExerciseQuestion: Decodable, Identifiable {
    let prompt: String
    let options: [String]
    let answerIndex: Int
    let hintAr: String?
    var id: String { prompt }
}

struct ExerciseResult: Decodable {
    let questions: [ExerciseQuestion]
    let focusAr: String?
    let reasonAr: String?
    let domain: String?
    let cached: Bool?

    private enum CodingKeys: String, CodingKey { case questions, focusAr, reasonAr, domain, cached }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        questions = try container.decodeIfPresent([ExerciseQuestion].self, forKey: .questions) ?? []
        focusAr = try container.decodeIfPresent(String.self, forKey: .focusAr)
        reasonAr = try container.decodeIfPresent(String.self, forKey: .reasonAr)
        domain = try container.decodeIfPresent(String.self, forKey: .domain)
        cached = try container.decodeIfPresent(Bool.self, forKey: .cached)
    }
}

struct AILearningBrief: Decodable, Hashable {
    let headlineAr: String
    let focusAr: String
    let whyAr: String
    let actionsAr: [String]
    let challengeEn: String
    let domain: String?
    let generatedAt: String?
    let cached: Bool?

    private enum CodingKeys: String, CodingKey {
        case headlineAr, focusAr, whyAr, actionsAr, challengeEn, domain, generatedAt, cached
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        headlineAr = try container.decodeIfPresent(String.self, forKey: .headlineAr) ?? "تركيز اليوم"
        focusAr = try container.decodeIfPresent(String.self, forKey: .focusAr) ?? ""
        whyAr = try container.decodeIfPresent(String.self, forKey: .whyAr) ?? ""
        actionsAr = try container.decodeIfPresent([String].self, forKey: .actionsAr) ?? []
        challengeEn = try container.decodeIfPresent(String.self, forKey: .challengeEn) ?? ""
        domain = try container.decodeIfPresent(String.self, forKey: .domain)
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
        cached = try container.decodeIfPresent(Bool.self, forKey: .cached)
    }
}

struct LeaderboardEntry: Decodable, Identifiable {
    let rank: Int
    let name: String
    let points: Int
    let streak: Int
    let isMe: Bool
    var id: Int { rank }
}

struct MyRank: Decodable {
    let rank: Int
    let points: Int
    let streak: Int
}

struct LeaderboardResult: Decodable {
    let top: [LeaderboardEntry]
    let me: MyRank?
}

enum AIStudioError: LocalizedError {
    case notSignedIn
    case rateLimited
    case dailyLimit
    case dailyCapacity
    case unavailable
    case progressNotSynced
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "سجّل الدخول أولًا لاستخدام الميزات الذكية عبر الخادم."
        case .rateLimited: return "وصلت إلى حد الاستخدام الذكي لهذه الساعة. جرّب مرة أخرى لاحقًا."
        case .dailyLimit: return LE("استخدمت رصيدك اليومي من المساعد الذكي. يتجدد الرصيد عند منتصف الليل بتوقيت الرياض، والدروس والتدريب المحلي متاحة دائمًا.",
                                     "You have used today's AI allowance. It renews at midnight Riyadh time; lessons and offline practice are always available.")
        case .dailyCapacity: return LE("المساعد الذكي مشغول جدًا اليوم. جرّب لاحقًا، والتعلّم المحلي متاح دائمًا.",
                                        "The AI assistant is at today's capacity. Try again later; offline learning is always available.")
        case .unavailable: return "المدرّب الذكي غير متاح حاليًا، ويمكنك متابعة التعلّم محليًا."
        case .progressNotSynced: return "يحتاج الموجز الذكي إلى مزامنة تقدّمك أولًا."
        case .underlying(let message): return message
        }
    }
}

// MARK: - Service

struct AIStudioService {
    private let api = APIClient(configuration: APIConfiguration(baseURL: nil))

    private var token: String? {
        let value = KeychainStore().string(for: "server.authToken")
        return value?.isEmpty == false ? value : nil
    }

    private struct ExplainBody: Encodable { let concept: String; let level: String }
    private struct WritingBody: Encodable {
        let text: String
        let level: String
        let task: String?
        let taskType: String
        let previousText: String?
    }
    private struct ExplainTextBody: Encodable { let text: String; let level: String; let locale: String }
    private struct ExerciseBody: Encodable {
        let topic: String?
        let level: String
        let count: Int
        let adaptive: Bool
        let domain: String?
    }

    func explain(concept: String, level: String) async throws -> ExplainResult {
        try await post("ai/explain", ExplainBody(concept: concept, level: level), ExplainResult.self)
    }

    func correctWriting(
        text: String,
        level: String,
        task: String? = nil,
        taskType: WritingTaskType = .free,
        previousText: String? = nil
    ) async throws -> WritingResult {
        try await post(
            "ai/writing",
            WritingBody(text: text, level: level, task: task, taskType: taskType.rawValue, previousText: previousText),
            WritingResult.self
        )
    }

    func explainText(_ text: String, level: String) async throws -> ExplainTextResult {
        try await post(
            "ai/explain-text",
            ExplainTextBody(text: text, level: level, locale: Localizer.shared.isEnglish ? "en" : "ar"),
            ExplainTextResult.self
        )
    }

    func quota() async throws -> AIQuota {
        guard let token else { throw AIStudioError.notSignedIn }
        do {
            return try await api.get(path: "ai/quota", response: AIQuota.self, bearerToken: token)
        } catch {
            throw mapped(error)
        }
    }

    func generateExercise(topic: String, level: String, count: Int) async throws -> ExerciseResult {
        try await post(
            "ai/exercise",
            ExerciseBody(topic: topic, level: level, count: count, adaptive: false, domain: nil),
            ExerciseResult.self
        )
    }

    func generateAdaptiveExercise(level: String, count: Int = 5) async throws -> ExerciseResult {
        try await post(
            "ai/exercise",
            ExerciseBody(topic: nil, level: level, count: count, adaptive: true, domain: nil),
            ExerciseResult.self
        )
    }

    func learningBrief() async throws -> AILearningBrief {
        guard let token else { throw AIStudioError.notSignedIn }
        do {
            return try await api.get(path: "ai/brief", response: AILearningBrief.self, bearerToken: token)
        } catch {
            throw mapped(error)
        }
    }

    func leaderboard() async throws -> LeaderboardResult {
        guard let token else { throw AIStudioError.notSignedIn }
        do {
            return try await api.get(path: "leaderboard", response: LeaderboardResult.self, bearerToken: token)
        } catch {
            throw mapped(error)
        }
    }

    private func post<B: Encodable, R: Decodable>(_ path: String, _ body: B, _ type: R.Type) async throws -> R {
        guard let token else { throw AIStudioError.notSignedIn }
        do {
            return try await api.send(path: path, method: "POST", body: body,
                                      response: type, bearerToken: token)
        } catch {
            throw mapped(error)
        }
    }

    private func mapped(_ error: Error) -> AIStudioError {
        if case APIError.server(let status, let message) = error {
            switch status {
            case 401: return .notSignedIn
            case 409: return .progressNotSynced
            case 429 where message.contains("ai_daily_limit"): return .dailyLimit
            case 503 where message.contains("ai_daily_capacity"): return .dailyCapacity
            case 429: return .rateLimited
            case 502, 503, 504: return .unavailable
            default: break
            }
        }
        return .underlying((error as? LocalizedError)?.errorDescription ?? "تعذّر الاتصال بالخادم.")
    }
}
