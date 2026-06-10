import Foundation

enum TaskKind: String, CaseIterable, Codable {
    case ask
    case voiceConversation = "voice_conversation"
    case translate
    case reply
    case studyCards = "study_cards"
    case linearizeTable = "linearize_table"
    case organizePlaceDescription = "organize_place_description"
    case conciseReply = "concise_reply"
    case quick
    case health
    case describeImage = "describe_image"
    case altText = "alt_text"
    case screenshot
    case currencyOrReceipt = "currency_or_receipt"
    case medicalText = "medical_text"
    case legalText = "legal_text"
    case tableRead = "table_read"
    case mathExtract = "math_extract"
    case liveScene = "live_scene"
    case walkingSnapshot = "walking_snapshot"
    case convert
    case ocr
    case askDocument = "ask_document"
}

enum AIThinkingLevel: String, Codable, CaseIterable {
    case minimal, low, medium, high
}

enum AIValidationProfile: String, Codable {
    case conversational
    case concise
    case faithfulText
    case structured
    case visualSafety
    case documentGrounded
}

enum AIQualitySource: String, Codable {
    case quickPreference
    case documentPreference
    case fixedFast
    case fixedBalanced
}

struct AITaskPolicy {
    let task: TaskKind
    let qualitySource: AIQualitySource
    let thinkingLevel: AIThinkingLevel
    let temperature: Double
    let maxOutputTokens: Int
    let timeoutSeconds: TimeInterval
    let attemptsPerModel: Int
    let repairEnabled: Bool
    let preserveCriticalTokens: Bool
    let validationProfile: AIValidationProfile
    let minimumUsefulCharacters: Int

    var responseSchema: [String: Any]? {
        AIResponseSchemas.schema(for: task)
    }

    func modelCandidates(quickQuality: String, documentQuality: String) -> [String] {
        let selectedQuality: String
        switch qualitySource {
        case .quickPreference: selectedQuality = quickQuality
        case .documentPreference: selectedQuality = documentQuality
        case .fixedFast: selectedQuality = "fast"
        case .fixedBalanced: selectedQuality = "balanced"
        }
        return AIModelRouter.models(for: selectedQuality)
    }
}

enum AIModelRouter {
    static func models(for quality: String) -> [String] {
        switch quality {
        case "fast":
            return ["gemini-3.1-flash-lite", "gemini-3.5-flash"]
        case "best":
            return ["gemini-3.1-pro-preview", "gemini-3.5-flash", "gemini-3.1-flash-lite"]
        case "balanced": fallthrough
        default:
            return ["gemini-3.5-flash", "gemini-3.1-flash-lite"]
        }
    }
}

enum AITaskPolicyCatalog {
    static let contractVersion = "basir-ai-2026.06-v5"
    static let promptContractVersion = "basir-prompts-2026.06-v4"

    static func policy(for task: TaskKind) -> AITaskPolicy {
        switch task {
        case .ask:
            return make(task, .quickPreference, .medium, 0.35, 8_192, 120, 2, true, false, .conversational, 8)
        case .voiceConversation:
            return make(task, .fixedFast, .low, 0.35, 2_048, 75, 2, true, false, .concise, 4)
        case .translate:
            return make(task, .fixedFast, .low, 0.10, 8_192, 120, 2, true, true, .faithfulText, 1)
        case .reply:
            return make(task, .fixedFast, .low, 0.45, 4_096, 90, 2, true, false, .conversational, 8)
        case .studyCards:
            return make(task, .quickPreference, .medium, 0.20, 12_288, 150, 2, true, true, .structured, 16)
        case .linearizeTable:
            return make(task, .fixedFast, .low, 0.05, 12_288, 150, 2, true, true, .faithfulText, 4)
        case .organizePlaceDescription:
            return make(task, .quickPreference, .low, 0.15, 4_096, 90, 2, true, false, .visualSafety, 8)
        case .conciseReply:
            return make(task, .fixedFast, .minimal, 0.25, 1_024, 60, 2, true, false, .concise, 2)
        case .quick:
            return make(task, .fixedFast, .minimal, 0.20, 2_048, 60, 2, true, false, .concise, 2)
        case .health:
            return make(task, .quickPreference, .medium, 0.15, 6_144, 120, 2, true, true, .conversational, 8)
        case .describeImage:
            return make(task, .fixedBalanced, .medium, 0.15, 8_192, 120, 2, true, false, .structured, 8)
        case .altText:
            return make(task, .fixedFast, .low, 0.10, 3_072, 90, 2, true, false, .structured, 4)
        case .screenshot:
            return make(task, .fixedFast, .low, 0.05, 8_192, 120, 2, true, true, .structured, 4)
        case .currencyOrReceipt:
            return make(task, .fixedFast, .low, 0.0, 6_144, 120, 2, true, true, .structured, 2)
        case .medicalText:
            return make(task, .documentPreference, .high, 0.05, 12_288, 180, 2, true, true, .structured, 8)
        case .legalText:
            return make(task, .documentPreference, .high, 0.05, 12_288, 180, 2, true, true, .structured, 8)
        case .tableRead:
            return make(task, .fixedBalanced, .medium, 0.0, 16_384, 180, 2, true, true, .structured, 4)
        case .mathExtract:
            return make(task, .documentPreference, .high, 0.0, 12_288, 180, 2, true, true, .faithfulText, 1)
        case .liveScene:
            return make(task, .fixedBalanced, .low, 0.0, 1_024, 45, 2, true, false, .visualSafety, 2)
        case .walkingSnapshot:
            return make(task, .fixedBalanced, .low, 0.0, 2_048, 75, 2, true, false, .visualSafety, 2)
        case .convert:
            return make(task, .documentPreference, .high, 0.0, 24_576, 300, 2, true, true, .documentGrounded, 1)
        case .ocr:
            return make(task, .fixedFast, .low, 0.0, 16_384, 180, 2, true, true, .structured, 1)
        case .askDocument:
            return make(task, .documentPreference, .high, 0.10, 10_240, 240, 2, true, true, .documentGrounded, 4)
        }
    }

    private static func make(
        _ task: TaskKind,
        _ qualitySource: AIQualitySource,
        _ thinkingLevel: AIThinkingLevel,
        _ temperature: Double,
        _ maxOutputTokens: Int,
        _ timeoutSeconds: TimeInterval,
        _ attemptsPerModel: Int,
        _ repairEnabled: Bool,
        _ preserveCriticalTokens: Bool,
        _ validationProfile: AIValidationProfile,
        _ minimumUsefulCharacters: Int
    ) -> AITaskPolicy {
        AITaskPolicy(
            task: task,
            qualitySource: qualitySource,
            thinkingLevel: thinkingLevel,
            temperature: temperature,
            maxOutputTokens: maxOutputTokens,
            timeoutSeconds: timeoutSeconds,
            attemptsPerModel: attemptsPerModel,
            repairEnabled: repairEnabled,
            preserveCriticalTokens: preserveCriticalTokens,
            validationProfile: validationProfile,
            minimumUsefulCharacters: minimumUsefulCharacters
        )
    }
}

enum AIExecutionDecision {
    static func shouldRetrySameModel(after error: Error) -> Bool {
        guard let gemini = error as? GeminiError else { return false }
        switch gemini {
        case .network:
            return true
        case let .http(status, _):
            return status == 408 || status == 409 || status == 429 || (500...599).contains(status)
        case let .decode(message):
            let lower = message.lowercased()
            return !lower.contains("blocked:")
                && !lower.contains("invalid gemini model")
                && !lower.contains("request text exceeds")
        case .missingApiKey, .cancelled:
            return false
        }
    }

    static func shouldTryFallback(after error: Error) -> Bool {
        if GeminiClient.shouldTryNextModel(after: error) { return true }
        guard let gemini = error as? GeminiError else { return false }
        if case let .decode(message) = gemini {
            let lower = message.lowercased()
            return !lower.contains("blocked:")
                && !lower.contains("request text exceeds")
                && !lower.contains("missing api key")
        }
        return false
    }

    static func boundedFailureReason(_ error: Error) -> String {
        guard let gemini = error as? GeminiError else {
            return "quality validation failed"
        }
        switch gemini {
        case let .decode(message):
            let lower = message.lowercased()
            if lower.contains("critical") { return "critical values changed or were omitted" }
            if lower.contains("valid json") || lower.contains("json") { return "structured JSON validation failed" }
            if lower.contains("empty") { return "response was empty" }
            if lower.contains("too short") { return "response was too short" }
            if lower.contains("repetition") || lower.contains("repeated") { return "response repeated content excessively" }
            if lower.contains("preamble") { return "response added an unwanted preamble" }
            if lower.contains("unsafe") || lower.contains("navigation") { return "response violated visual safety rules" }
            if lower.contains("blocked:") { return "provider blocked the response" }
            if lower.contains("invalid gemini model") { return "configured model was unavailable" }
            if lower.contains("exceeds") || lower.contains("too large") { return "request exceeded a safe size limit" }
            if lower.contains("table") || lower.contains("structured") || lower.contains("omitted") {
                return "structured response failed semantic validation"
            }
            return "response failed quality validation"
        case let .http(status, _):
            if status == 429 { return "provider rate limit" }
            if (500...599).contains(status) { return "provider service failure" }
            return "provider HTTP \(status)"
        case .network:
            return "temporary network failure"
        case .missingApiKey:
            return "missing API key"
        case .cancelled:
            return "cancelled"
        }
    }
}
