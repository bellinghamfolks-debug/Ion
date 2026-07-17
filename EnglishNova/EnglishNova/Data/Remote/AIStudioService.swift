import Foundation

// Client for the server's extended AI features and the leaderboard. All AI
// endpoints require a signed-in user; the token is read from the Keychain (the
// same item AccountService writes), matching RemoteTutorClient.

// MARK: - Models

struct ExplainResult: Decodable {
    let explanationAr: String
    let exampleEn: String?
    var cached: Bool? = nil
}

struct WritingResult: Decodable {
    let corrected: String
    let feedbackAr: String
    let score: Int?
}

struct ExerciseQuestion: Decodable, Identifiable {
    let prompt: String
    let options: [String]
    let answerIndex: Int
    let hintAr: String?
    // Stable identity for ForEach: the prompt is unique enough per set.
    var id: String { prompt }
}

struct ExerciseResult: Decodable {
    let questions: [ExerciseQuestion]
    var cached: Bool? = nil
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

/// A friendly, user-facing error for the AI studio screens.
enum AIStudioError: LocalizedError {
    case notSignedIn
    case rateLimited
    case unavailable
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "سجّل الدخول أولًا لاستخدام ميزات الذكاء."
        case .rateLimited: return "لقد استخدمت الذكاء كثيرًا خلال الساعة. انتظر قليلًا ثم أعد المحاولة."
        case .unavailable: return "خدمة الذكاء غير متاحة حاليًا. حاول لاحقًا."
        case .underlying(let m): return m
        }
    }
}

// MARK: - Service

struct AIStudioService {
    private let api = APIClient(configuration: APIConfiguration(baseURL: nil))

    private var token: String? {
        let value = KeychainStore().string(for: "server.authToken")
        return (value?.isEmpty == false) ? value : nil
    }

    private struct ExplainBody: Encodable { let concept: String; let level: String }
    private struct WritingBody: Encodable { let text: String; let level: String }
    private struct ExerciseBody: Encodable { let topic: String; let level: String; let count: Int }

    func explain(concept: String, level: String) async throws -> ExplainResult {
        try await post("ai/explain", ExplainBody(concept: concept, level: level), ExplainResult.self)
    }

    func correctWriting(text: String, level: String) async throws -> WritingResult {
        try await post("ai/writing", WritingBody(text: text, level: level), WritingResult.self)
    }

    func generateExercise(topic: String, level: String, count: Int) async throws -> ExerciseResult {
        try await post("ai/exercise", ExerciseBody(topic: topic, level: level, count: count), ExerciseResult.self)
    }

    func leaderboard() async throws -> LeaderboardResult {
        guard let token else { throw AIStudioError.notSignedIn }
        do {
            return try await api.get(path: "leaderboard", response: LeaderboardResult.self, bearerToken: token)
        } catch {
            throw mapped(error)
        }
    }

    // MARK: - Helpers

    private func post<B: Encodable, R: Decodable>(_ path: String, _ body: B, _ type: R.Type) async throws -> R {
        guard let token else { throw AIStudioError.notSignedIn }
        do {
            return try await api.send(path: path, method: "POST", body: body,
                                      response: type, bearerToken: token)
        } catch {
            throw mapped(error)
        }
    }

    /// Turn transport/server errors into friendly AIStudioError cases.
    private func mapped(_ error: Error) -> AIStudioError {
        if case APIError.server(let status, _) = error {
            switch status {
            case 401: return .notSignedIn
            case 429: return .rateLimited
            case 502, 503: return .unavailable
            default: break
            }
        }
        return .underlying((error as? LocalizedError)?.errorDescription ?? "تعذّر الاتصال بالخادم.")
    }
}
