import Foundation

/// Talks to Google's Gemini API (Generative Language) directly from the device
/// using the learner's own API key. The key is passed in the request header
/// (not the URL) and is never logged or persisted by this client — it is read
/// from the Keychain at call time by the caller.
struct GeminiTutorClient {
    enum GeminiError: LocalizedError {
        case missingKey
        case http(status: Int, message: String)
        case emptyResponse
        case decoding(String)

        var errorDescription: String? {
            switch self {
            case .missingKey: return "لم يتم إدخال مفتاح Gemini."
            case let .http(status, message): return "خطأ من Gemini (\(status)): \(message)"
            case .emptyResponse: return "لم يُرجِع Gemini أي رد."
            case let .decoding(detail): return "تعذّر قراءة رد Gemini: \(detail)"
            }
        }
    }

    var model: String = "gemini-1.5-flash"
    var session: URLSession = .shared

    private var endpoint: URL? {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")
    }

    func reply(to message: String, level: CEFRLevel, locale: String, apiKey: String) async throws -> TutorMessage {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw GeminiError.missingKey }
        guard let endpoint else { throw GeminiError.decoding("نموذج غير صالح") }

        let body = GeminiRequest(
            systemInstruction: .init(parts: [.init(text: Self.systemPrompt(level: level, locale: locale))]),
            contents: [.init(role: "user", parts: [.init(text: message)])],
            generationConfig: .init(responseMimeType: "application/json", temperature: 0.4)
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard data.count <= 5 * 1_024 * 1_024 else { throw GeminiError.decoding("استجابة أكبر من الحد") }
        guard let http = response as? HTTPURLResponse else { throw GeminiError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            let raw = String(data: data.prefix(800), encoding: .utf8) ?? "غير معروف"
            throw GeminiError.http(status: http.statusCode, message: raw)
        }
        return try Self.parse(data)
    }

    /// Exposed for testing: turn a raw Gemini response body into a TutorMessage.
    static func parse(_ data: Data) throws -> TutorMessage {
        let decoder = JSONDecoder()
        let envelope: GeminiResponse
        do { envelope = try decoder.decode(GeminiResponse.self, from: data) }
        catch { throw GeminiError.decoding(error.localizedDescription) }

        guard let text = envelope.candidates?.first?.content?.parts?
            .compactMap(\.text).joined(), !text.isEmpty else {
            throw GeminiError.emptyResponse
        }

        // The model is asked for strict JSON, but tolerate stray prose/fences.
        let jsonSlice = extractJSONObject(from: text)
        if let jsonData = jsonSlice.data(using: .utf8),
           let structured = try? decoder.decode(TutorResponse.self, from: jsonData) {
            return TutorMessage(
                role: .assistant,
                text: structured.reply.isEmpty ? text : structured.reply,
                corrections: structured.corrections,
                suggestedReplies: structured.suggestedReplies
            )
        }
        // Fall back to using the raw text as the reply if it was not valid JSON.
        return TutorMessage(role: .assistant, text: text)
    }

    /// Pulls the first `{ ... }` block out of a string, ignoring code fences.
    private static func extractJSONObject(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            return text
        }
        return String(text[start...end])
    }

    static func systemPrompt(level: CEFRLevel, locale: String) -> String {
        let explanationLanguage = locale.hasPrefix("ar") ? "Arabic" : "English"
        return """
        You are a patient English tutor for a learner at CEFR level \(level.rawValue).
        Explain in \(explanationLanguage); keep English words/examples in English.
        Be concise and encouraging. Respond with ONLY a JSON object of this exact shape:
        {"reply": string, "corrections": [{"original": string, "replacement": string, "reason": string}], "suggestedReplies": [string]}
        "reason" must be written in \(explanationLanguage). Use an empty array when there is nothing to correct.
        """
    }
}

// MARK: - Wire types

private struct GeminiRequest: Encodable {
    struct Content: Encodable {
        var role: String?
        var parts: [Part]
    }
    struct Part: Encodable { var text: String }
    struct GenerationConfig: Encodable {
        var responseMimeType: String
        var temperature: Double
        enum CodingKeys: String, CodingKey {
            case responseMimeType = "response_mime_type"
            case temperature
        }
    }
    var systemInstruction: Content
    var contents: [Content]
    var generationConfig: GenerationConfig

    enum CodingKeys: String, CodingKey {
        case systemInstruction = "system_instruction"
        case contents
        case generationConfig
    }
}

struct GeminiResponse: Decodable {
    struct Candidate: Decodable { var content: Content? }
    struct Content: Decodable { var parts: [Part]? }
    struct Part: Decodable { var text: String? }
    var candidates: [Candidate]?
}
