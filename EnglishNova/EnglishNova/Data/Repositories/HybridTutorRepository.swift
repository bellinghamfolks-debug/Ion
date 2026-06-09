import Foundation

struct HybridTutorRepository: TutorRepositoryProtocol {
    let remote: RemoteTutorClient
    let local: LocalTutorEngine

    func reply(to message: String, sessionID: String, level: CEFRLevel, locale: String, context: String?) async throws -> TutorMessage {
        do {
            let response = try await remote.reply(request: TutorRequest(sessionId: sessionID, locale: locale, level: level.rawValue, message: message, context: context))
            return TutorMessage(role: .assistant, text: response.reply, corrections: response.corrections, suggestedReplies: response.suggestedReplies)
        } catch APIError.missingBaseURL {
            return local.reply(to: message, level: level)
        } catch {
            var fallback = local.reply(to: message, level: level)
            fallback.text += "\n\nملاحظة: تعذر الاتصال، لذلك استُخدم المدرّس المحلي."
            return fallback
        }
    }
}

struct HybridVoiceCoachRepository: VoiceCoachRepositoryProtocol {
    let remote: RemoteVoiceCoachClient
    let local: LocalVoiceCoachEngine

    func reply(to request: VoiceCoachRequest) async throws -> VoiceCoachReply {
        do {
            return try await remote.reply(request: request)
        } catch APIError.missingBaseURL {
            return local.reply(to: request)
        } catch {
            var fallback = local.reply(to: request)
            fallback = VoiceCoachReply(
                reply: fallback.reply,
                translationAr: fallback.translationAr,
                feedbackAr: fallback.feedbackAr + " استُخدم المدرب المحلي لأن الاتصال بالخادم لم ينجح.",
                suggestedAnswer: fallback.suggestedAnswer,
                source: "local-fallback"
            )
            return fallback
        }
    }
}
