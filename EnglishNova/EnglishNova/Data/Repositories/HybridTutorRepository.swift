import Foundation

/// Legacy hybrid wrapper retained for compatibility with tests and older wiring.
/// Live text tutoring uses `RoutingTutorRepository`.
struct HybridTutorRepository: TutorRepositoryProtocol {
    let remote: RemoteTutorClient
    let local: LocalTutorEngine

    func reply(to message: String, sessionID: String, level: CEFRLevel, locale: String, context: String?) async throws -> TutorMessage {
        do {
            let response = try await remote.reply(request: TutorRequest(
                sessionId: sessionID,
                locale: locale,
                level: level.rawValue,
                message: message,
                context: context
            ))
            let text = response.reply.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return fallback(message: message, level: level, note: "وصل رد فارغ من الخادم.")
            }
            return TutorMessage(
                role: .assistant,
                text: text,
                corrections: response.corrections,
                suggestedReplies: response.suggestedReplies
            )
        } catch {
            return fallback(message: message, level: level, note: safeReason(for: error))
        }
    }

    private func fallback(message: String, level: CEFRLevel, note: String) -> TutorMessage {
        var result = local.reply(to: message, level: level)
        result.text += "\n\nملاحظة: \(note) استُخدم المدرّب المحلي لهذه الرسالة."
        return result
    }
}

struct HybridVoiceCoachRepository: VoiceCoachRepositoryProtocol {
    let remote: RemoteVoiceCoachClient
    let local: LocalVoiceCoachEngine

    func reply(to request: VoiceCoachRequest) async throws -> VoiceCoachReply {
        do {
            return try await remote.reply(request: request)
        } catch {
            let fallback = local.reply(to: request)
            return VoiceCoachReply(
                reply: fallback.reply,
                translationAr: fallback.translationAr,
                feedbackAr: fallback.feedbackAr + " " + safeReason(for: error) + " استُخدم المدرب المحلي لهذه المحاولة.",
                suggestedAnswer: fallback.suggestedAnswer,
                source: "local-fallback"
            )
        }
    }
}

private func safeReason(for error: Error) -> String {
    if case TutorRemoteError.notSignedIn = error {
        return "الميزة الذكية تحتاج إلى تسجيل الدخول."
    }
    if case APIError.server(let status, _) = error {
        switch status {
        case 401: return "انتهت جلسة تسجيل الدخول أو لم تعد صالحة."
        case 429: return "وصلت الخدمة الذكية إلى حد الاستخدام المؤقت."
        case 502, 503, 504: return "الخدمة الذكية غير متاحة مؤقتًا."
        default: return "تعذر طلب الخدمة الذكية، رمز الاستجابة \(status)."
        }
    }
    if case APIError.decoding = error {
        return "تعذر قراءة استجابة الخدمة الذكية."
    }
    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost: return "لا يوجد اتصال مستقر بالإنترنت."
        case .timedOut: return "انتهت مهلة الاتصال بالخدمة الذكية."
        default: return "تعذر الوصول إلى الخدمة الذكية عبر الشبكة."
        }
    }
    return "تعذر الوصول إلى الخدمة الذكية."
}
