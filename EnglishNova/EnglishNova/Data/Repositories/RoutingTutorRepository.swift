import Foundation

/// Chooses which engine answers the interactive tutor based on the learner's
/// selected `TutorProvider`, with a graceful on-device fallback whenever a
/// network engine is unavailable or fails.
final class RoutingTutorRepository: TutorRepositoryProtocol {
    private let gemini: GeminiTutorClient
    private let remote: RemoteTutorClient
    private let local: LocalTutorEngine
    private let settings: AppSettings

    init(gemini: GeminiTutorClient, remote: RemoteTutorClient, local: LocalTutorEngine, settings: AppSettings) {
        self.gemini = gemini
        self.remote = remote
        self.local = local
        self.settings = settings
    }

    func reply(to message: String, sessionID: String, level: CEFRLevel, locale: String, context: String?) async throws -> TutorMessage {
        switch await settings.tutorProvider {
        case .gemini:
            return await geminiReply(message: message, level: level, locale: locale)
        case .device:
            return local.reply(to: message, level: level)
        case .smart:
            return await smartReply(message: message, sessionID: sessionID, level: level, locale: locale, context: context)
        }
    }

    private func geminiReply(message: String, level: CEFRLevel, locale: String) async -> TutorMessage {
        guard let key = await settings.geminiAPIKey() else {
            return localFallback(message: message, level: level, note: "لم يُدخل مفتاح Gemini، فاستُخدم المدرّس المحلي.")
        }
        var client = gemini
        client.model = await settings.geminiModel
        do {
            return try await client.reply(to: message, level: level, locale: locale, apiKey: key)
        } catch {
            return localFallback(message: message, level: level, note: "تعذّر الاتصال بـ Gemini (\(error.localizedDescription))، فاستُخدم المدرّس المحلي.")
        }
    }

    private func smartReply(message: String, sessionID: String, level: CEFRLevel, locale: String, context: String?) async -> TutorMessage {
        do {
            let response = try await remote.reply(request: TutorRequest(
                sessionId: sessionID, locale: locale, level: level.rawValue, message: message, context: context
            ))
            return TutorMessage(role: .assistant, text: response.reply, corrections: response.corrections, suggestedReplies: response.suggestedReplies)
        } catch APIError.missingBaseURL {
            return local.reply(to: message, level: level)
        } catch {
            return localFallback(message: message, level: level, note: "تعذر الاتصال، لذلك استُخدم المدرّس المحلي.")
        }
    }

    private func localFallback(message: String, level: CEFRLevel, note: String) -> TutorMessage {
        var fallback = local.reply(to: message, level: level)
        fallback.text += "\n\nملاحظة: \(note)"
        return fallback
    }
}
