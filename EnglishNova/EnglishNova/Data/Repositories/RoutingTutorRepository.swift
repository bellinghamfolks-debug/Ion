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
                    note: LE(
                        "وصل رد فارغ من المدرّب الذكي، لذلك استُخدم المدرّب المحلي لهذه الرسالة.",
                        "The smart tutor returned an empty response, so the local tutor was used for this message."
                    )
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
            return LE(
                "المدرّب الذكي يحتاج إلى تسجيل الدخول. استُخدم المدرّب المحلي لهذه الرسالة.",
                "The smart tutor requires sign-in. The local tutor was used for this message."
            )
        }

        if case APIError.missingBaseURL = error {
            return LE(
                "عنوان خدمة EnglishNova غير متاح في هذا البناء. استُخدم المدرّب المحلي.",
                "The EnglishNova service address is unavailable in this build. The local tutor was used."
            )
        }
        if case APIError.insecureBaseURL = error {
            return LE(
                "تم رفض عنوان خدمة غير آمن. استُخدم المدرّب المحلي.",
                "An insecure service address was rejected. The local tutor was used."
            )
        }
        if case APIError.responseTooLarge = error {
            return LE(
                "كانت استجابة الخادم أكبر من الحد الآمن. استُخدم المدرّب المحلي.",
                "The server response exceeded the safe size limit. The local tutor was used."
            )
        }
        if case APIError.invalidResponse = error {
            return LE(
                "وصلت استجابة شبكة غير صالحة. استُخدم المدرّب المحلي.",
                "An invalid network response was received. The local tutor was used."
            )
        }
        if case APIError.decoding = error {
            return LE(
                "تعذر قراءة استجابة المدرّب الذكي. استُخدم المدرّب المحلي لهذه الرسالة.",
                "The smart tutor response could not be read. The local tutor was used for this message."
            )
        }
        if case APIError.server(let status, _) = error {
            switch status {
            case 401:
                return LE(
                    "انتهت جلسة تسجيل الدخول أو لم تعد صالحة. سجّل الدخول مجددًا لاستخدام المدرّب الذكي. استُخدم المدرّب المحلي الآن.",
                    "Your sign-in session expired or is no longer valid. Sign in again to use the smart tutor. The local tutor was used for now."
                )
            case 429:
                return LE(
                    "وصل المدرّب الذكي إلى حد الاستخدام المؤقت. استُخدم المدرّب المحلي لهذه الرسالة.",
                    "The smart tutor reached a temporary usage limit. The local tutor was used for this message."
                )
            case 502, 503, 504:
                return LE(
                    "خدمة المدرّب الذكي غير متاحة مؤقتًا. استُخدم المدرّب المحلي لهذه الرسالة.",
                    "The smart tutor service is temporarily unavailable. The local tutor was used for this message."
                )
            default:
                return LfE(
                    "تعذر طلب المدرّب الذكي، رمز الاستجابة %@. استُخدم المدرّب المحلي.",
                    "The smart tutor request failed with response code %@. The local tutor was used.",
                    "\(status)"
                )
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return LE(
                    "انقطع الاتصال بالإنترنت. استُخدم المدرّب المحلي لهذه الرسالة.",
                    "The internet connection was lost. The local tutor was used for this message."
                )
            case .timedOut:
                return LE(
                    "استغرق المدرّب الذكي وقتًا أطول من المتوقع. استُخدم المدرّب المحلي لهذه الرسالة.",
                    "The smart tutor took longer than expected. The local tutor was used for this message."
                )
            default:
                return LE(
                    "تعذر الوصول إلى المدرّب الذكي عبر الشبكة. استُخدم المدرّب المحلي لهذه الرسالة.",
                    "The smart tutor could not be reached over the network. The local tutor was used for this message."
                )
            }
        }

        return LE(
            "حدث خطأ غير متوقع أثناء طلب المدرّب الذكي. استُخدم المدرّب المحلي لهذه الرسالة.",
            "An unexpected error occurred while requesting the smart tutor. The local tutor was used for this message."
        )
    }

    private func localFallback(message: String, level: CEFRLevel, note: String) -> TutorMessage {
        var fallback = local.reply(to: message, level: level)
        fallback.text += "\n\n" + LE("ملاحظة: ", "Note: ") + note
        return fallback
    }
}
