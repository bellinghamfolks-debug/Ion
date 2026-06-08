// UserFriendlyErrorMapper.swift
// Port of UserFriendlyErrorMapper.java. Same 15-pattern table, same
// Arabic/English copy, just expressed in Swift.
//
// Used at every catch site that surfaces an error to the user. Direct
// match for AlertItem messages and showResult subtitles.

import Foundation

enum UserFriendlyErrorMapper {

    /// Map any thrown error to a localised "we tried, here's what happened"
    /// sentence, followed by a truncated technical trailer for developers.
    static func map(_ error: Error) -> String {
        // Show the user only the clear, human message. The raw technical
        // string (English HTTP/SDK text) looked robotic inside an Arabic
        // UI, so it's no longer appended.
        let raw = rawString(from: error)
        return friendlyMessage(for: raw, error: error)
    }

    static func friendlyMessage(for raw: String, error: Error) -> String {
        let low = raw.lowercased()

        // --- API key / authentication ---
        if low.contains("api key") && low.contains("empty") {
            return L10n.t("لم يُضف مفتاح Gemini بعد. افتح الإعدادات، ثم احفظ مفتاح API الخاص بمشروعك.",
                          "No Gemini API key has been added. Open Settings and save your project API key.")
        }
        if (low.contains("http 401") || low.contains("unauthorized")
                || low.contains("api key not valid") || low.contains("invalid_api_key")) {
            return L10n.t("لم تقبل الخدمة مفتاح Gemini. تأكد من صحة المفتاح ومن ارتباطه بالمشروع المناسب، ثم أعد المحاولة.",
                          "The Gemini key was not accepted. Check that the key is valid and belongs to the correct project, then try again.")
        }
        if (low.contains("http 403") || low.contains("forbidden")
                || low.contains("permission_denied")) {
            return L10n.t("لا يملك المفتاح الصلاحية المطلوبة. تحقق من تفعيل Gemini API وصلاحيات المشروع وإعدادات الفوترة، ثم أعد المحاولة.",
                          "The key does not have the required permission. Check Gemini API access, project permissions, and billing, then try again.")
        }

        // --- Rate limits and server load ---
        if low.contains("http 429") || low.contains("rate") || low.contains("quota") {
            return L10n.t("وصل الحساب إلى حد الطلبات أو الحصة المتاحة. أعد المحاولة لاحقًا، أو راجع حدود الاستخدام والفوترة في مشروعك.",
                          "The account has reached its request or quota limit. Try again later, or review usage and billing limits for your project.")
        }
        if low.contains("http 500") || low.contains("http 502")
                || low.contains("http 503") || low.contains("http 504")
                || low.contains("internal server error") || low.contains("unavailable") {
            return L10n.t("خدمة الذكاء الاصطناعي غير متاحة مؤقتًا. أعد المحاولة بعد قليل.",
                          "The AI service is temporarily unavailable. Try again shortly.")
        }

        // --- Network ---
        if low.contains("unknown host") || low.contains("a server with the specified hostname could not be found")
                || low.contains("no internet") || low.contains("not connect to") {
            return L10n.t("تعذّر الاتصال بالخدمة. تحقق من الإنترنت، ومن عنوان الخادم الوسيط إذا كنت تستخدمه، ثم أعد المحاولة.",
                          "The service could not be reached. Check your internet connection and proxy address if you use one, then try again.")
        }
        if low.contains("timeout") || low.contains("timed out") || low.contains("http 408") {
            return L10n.t("استغرق الطلب وقتًا أطول من المسموح. تحقق من الشبكة وأعد المحاولة، أو استخدم ملفًا أصغر.",
                          "The request took too long. Check your connection and try again, or use a smaller file.")
        }

        // --- Model output problems ---
        if low.contains("unterminated") || low.contains("malformed json") || low.contains("decode") {
            return L10n.t("وصلت استجابة غير مكتملة. جرّب مستوى جودة أعلى، أو أعد المحاولة بملف أصغر.",
                          "The response was incomplete. Try a higher quality level or use a smaller file.")
        }
        if low.contains("safety") || low.contains("blocked") || low.contains("recitation") {
            return L10n.t("لم تسمح ضوابط الخدمة بمعالجة هذا المحتوى. جرّب صورة أخرى أو أعد صياغة الطلب.",
                          "The service safeguards did not allow this content. Try another image or rephrase the request.")
        }

        // --- Cancellation ---
        if low.contains("cancel") || low.contains("interrupted") || error is CancellationError {
            return L10n.t("أُلغيت العملية.", "The operation was cancelled.")
        }

        if let geminiError = error as? GeminiError, case .missingApiKey = geminiError {
            return L10n.t("لم يُضف مفتاح Gemini بعد. افتح الإعدادات، ثم احفظ مفتاح API الخاص بمشروعك.",
                          "No Gemini API key has been added. Open Settings and save your project API key.")
        }

        return L10n.t("تعذّر إكمال الطلب. تحقق من اتصال الإنترنت وإعداد Gemini أو الخادم الوسيط، ثم أعد المحاولة.",
                      "The request could not be completed. Check your internet connection and Gemini or proxy settings, then try again.")
    }

    private static func rawString(from error: Error) -> String {
        if let gemini = error as? GeminiError {
            switch gemini {
            case .missingApiKey:                          return "API key is empty"
            case .http(let status, let body):             return "HTTP \(status): \(body)"
            case .decode(let msg):                        return msg
            case .network(let underlying):                return underlying.localizedDescription
            case .cancelled:                              return "Cancelled"
            }
        }
        return (error as NSError).localizedDescription
    }

    private static func truncate(_ s: String, max: Int) -> String {
        if s.count <= max { return s }
        return String(s.prefix(max)) + "..."
    }
}
