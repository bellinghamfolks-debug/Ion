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
                return fallback(
                    message: message,
                    level: level,
                    note: LE("وصل رد فارغ من الخادم.", "The server returned an empty response.")
                )
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
        result.text += "\n\n" + LE("ملاحظة: ", "Note: ") + note + LE(
            " استُخدم المدرّب المحلي لهذه الرسالة.",
            " The local tutor was used for this message."
        )
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
                feedbackAr: fallback.feedbackAr + " " + safeReason(for: error) + LE(
                    " استُخدم المدرب المحلي لهذه المحاولة.",
                    " The local coach was used for this attempt."
                ),
                suggestedAnswer: fallback.suggestedAnswer,
                source: "local-fallback"
            )
        }
    }
}

private func safeReason(for error: Error) -> String {
    if case TutorRemoteError.notSignedIn = error {
        return LE(
            "الميزة الذكية تحتاج إلى تسجيل الدخول.",
            "The smart feature requires sign-in."
        )
    }
    if case APIError.server(let status, _) = error {
        switch status {
        case 401:
            return LE(
                "انتهت جلسة تسجيل الدخول أو لم تعد صالحة.",
                "The sign-in session expired or is no longer valid."
            )
        case 429:
            return LE(
                "وصلت الخدمة الذكية إلى حد الاستخدام المؤقت.",
                "The smart service reached a temporary usage limit."
            )
        case 502, 503, 504:
            return LE(
                "الخدمة الذكية غير متاحة مؤقتًا.",
                "The smart service is temporarily unavailable."
            )
        default:
            return LfE(
                "تعذر طلب الخدمة الذكية، رمز الاستجابة %@.",
                "The smart service request failed with response code %@.",
                "\(status)"
            )
        }
    }
    if case APIError.decoding = error {
        return LE(
            "تعذر قراءة استجابة الخدمة الذكية.",
            "The smart service response could not be read."
        )
    }
    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return LE("لا يوجد اتصال مستقر بالإنترنت.", "There is no stable internet connection.")
        case .timedOut:
            return LE("انتهت مهلة الاتصال بالخدمة الذكية.", "The smart service request timed out.")
        default:
            return LE("تعذر الوصول إلى الخدمة الذكية عبر الشبكة.", "The smart service could not be reached over the network.")
        }
    }
    return LE("تعذر الوصول إلى الخدمة الذكية.", "The smart service could not be reached.")
}
