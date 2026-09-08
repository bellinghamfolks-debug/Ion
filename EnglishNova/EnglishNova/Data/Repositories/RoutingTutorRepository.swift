import Foundation

/// Chooses which engine answers the interactive tutor based on the learner's
/// selected `TutorProvider`. Smart mode prefers the shared EnglishNova server
/// and falls back locally with a precise, non-sensitive reason when needed.
final class RoutingTutorRepository: TutorRepositoryProtocol {
    private let remote: RemoteTutorClient
    private let local: LocalTutorEngine
    private let settings: AppSettings

    init(remote: RemoteTutorClient, local: LocalTutorEngine, settings: AppSettings) {
        self.remote = remote
        self.local = local
        self.settings = settings
    }

    func reply(to message: String, sessionID: String, level: CEFRLevel, locale: String, context: String?) async throws -> TutorMessage {
        switch await settings.tutorProvider {
        case .device:
            return local.reply(to: message, level: level)
        // `.gemini` is a legacy persisted value. Personal Gemini keys are no
        // longer used; both values route through the shared server.
        case .smart, .gemini:
            return await smartReply(
                message: message,
                sessionID: sessionID,
                level: level,
                locale: locale,
                context: context
            )
        }
    }

    private func smartReply(
        message: String,
        sessionID: String,
        level: CEFRLevel,
        locale: String,
        context: String?
    ) async -> TutorMessage {
        do {
            let response = try await remote.reply(request: TutorRequest(
                sessionId: sessionID,
                locale: locale,
                level: level.rawValue,
                message: message,
                context: context
            ))
            let reply = response.reply.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reply.isEmpty else {
                return localFallback(
                    message: message,
                    level: level,
                    note: L("وصل رد فارغ من المدرّب الذكي، لذلك استُخدم المدرّب المحلي لهذه الرسالة.")
                )
            }
            return TutorMessage(
                role: .assistant,
                text: reply,
                corrections: response.corrections,
                suggestedReplies: response.suggestedReplies
            )
        } catch {
            return localFallback(message: message, level: level, note: fallbackNote(for: error))
        }
    }

    private func fallbackNote(for error: Error) -> String {
        if case TutorRemoteError.notSignedIn = error {
            return L("المدرّب الذكي يحتاج إلى تسجيل الدخول. استُخدم المدرّب المحلي لهذه الرسالة.")
        }

        if case APIError.missingBaseURL = error {
            return L("عنوان خدمة EnglishNova غير متاح في هذا البناء. استُخدم المدرّب المحلي.")
        }
        if case APIError.insecureBaseURL = error {
            return L("تم رفض عنوان خدمة غير آمن. استُخدم المدرّب المحلي.")
        }
        if case APIError.responseTooLarge = error {
            return L("كانت استجابة الخادم أكبر من الحد الآمن. استُخدم المدرّب المحلي.")
        }
        if case APIError.invalidResponse = error {
            return L("وصلت استجابة شبكة غير صالحة. استُخدم المدرّب المحلي.")
        }
        if case APIError.decoding = error {
            return L("تعذر قراءة استجابة المدرّب الذكي. استُخدم المدرّب المحلي لهذه الرسالة.")
        }
        if case APIError.server(let status, _) = error {
            switch status {
            case 401:
                return L("انتهت جلسة تسجيل الدخول أو لم تعد صالحة. سجّل الدخول مجددًا لاستخدام المدرّب الذكي. استُخدم المدرّب المحلي الآن.")
            case 429:
                return L("وصل المدرّب الذكي إلى حد الاستخدام المؤقت. استُخدم المدرّب المحلي لهذه الرسالة.")
            case 502, 503, 504:
                return L("خدمة المدرّب الذكي غير متاحة مؤقتًا. استُخدم المدرّب المحلي لهذه الرسالة.")
            default:
                return Lf("تعذر طلب المدرّب الذكي، رمز الاستجابة %@. استُخدم المدرّب المحلي.", "\(status)")
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return L("انقطع الاتصال بالإنترنت. استُخدم المدرّب المحلي لهذه الرسالة.")
            case .timedOut:
                return L("استغرق المدرّب الذكي وقتًا أطول من المتوقع. استُخدم المدرّب المحلي لهذه الرسالة.")
            default:
                return L("تعذر الوصول إلى المدرّب الذكي عبر الشبكة. استُخدم المدرّب المحلي لهذه الرسالة.")
            }
        }

        return L("حدث خطأ غير متوقع أثناء طلب المدرّب الذكي. استُخدم المدرّب المحلي لهذه الرسالة.")
    }

    private func localFallback(message: String, level: CEFRLevel, note: String) -> TutorMessage {
        var fallback = local.reply(to: message, level: level)
        fallback.text += "\n\nملاحظة: \(note)"
        return fallback
    }
}
