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

struct WritingResult: Decodable {
    let corrected: String
    let feedbackAr: String
    let score: Int?
    let strengthsAr: [String]
    let improvementsAr: [String]
    let corrections: [WritingCorrection]
    let nextTaskEn: String?

    private enum CodingKeys: String, CodingKey {
        case corrected, feedbackAr, score, strengthsAr, improvementsAr, corrections, nextTaskEn
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
    }
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
    case unavailable
    case progressNotSynced
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "سجّل الدخول أولًا لاستخدام الميزات الذكية عبر الخادم."
        case .rateLimited: return "وصلت إلى حد الاستخدام الذكي لهذه الساعة. جرّب مرة أخرى لاحقًا."
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
    private struct WritingBody: Encodable { let text: String; let level: String; let task: String? }
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

    func correctWriting(text: String, level: String, task: String? = nil) async throws -> WritingResult {
        try await post("ai/writing", WritingBody(text: text, level: level, task: task), WritingResult.self)
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
        if case APIError.server(let status, _) = error {
            switch status {
            case 401: return .notSignedIn
            case 409: return .progressNotSynced
            case 429: return .rateLimited
            case 502, 503, 504: return .unavailable
            default: break
            }
        }
        return .underlying((error as? LocalizedError)?.errorDescription ?? "تعذّر الاتصال بالخادم.")
    }
}
