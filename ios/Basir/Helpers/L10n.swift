// L10n.swift
// Bilingual helper that mirrors the Android `t(arabic, english)` pattern.
//
// The Android app makes the language a per-app preference (not the OS
// locale) so the user can override the system language. We do the same
// on iOS via BasirSettings.language, persisted in UserDefaults.
//
// Usage:
//   Text(L10n.t("مرحباً", "Welcome"))
//   speak(L10n.t("جارٍ التحليل", "Analyzing"))

import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case arabic = "ar"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .arabic:  return "العربية"
        case .english: return "English"
        }
    }

    var bcp47: String { rawValue }

    /// Locale used for TTS, speech recognition, and SimpleDateFormat-style
    /// formatters. Saudi Arabic for Arabic users.
    var locale: Locale {
        switch self {
        case .arabic:  return Locale(identifier: "ar_SA")
        case .english: return Locale(identifier: "en_US")
        }
    }

    /// Nonisolated read of the persisted language straight from
    /// UserDefaults — same key (`language_raw`) that BasirSettings'
    /// @AppStorage writes. This lets localization helpers run from
    /// nonisolated contexts without touching the @MainActor
    /// BasirSettings singleton (required under the Swift 6 toolchain).
    static var current: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: "language_raw")
            ?? AppLanguage.arabic.rawValue
        return AppLanguage(rawValue: raw) ?? .arabic
    }
}

enum L10n {
    /// Pick the Arabic or English variant based on the current user
    /// language. Static so it can be called from SwiftUI bodies without
    /// environment dependency injection.
    static func t(_ arabic: String, _ english: String) -> String {
        AppLanguage.current == .arabic ? arabic : english
    }

    /// 20-language BCP-47 → display name lookup used by TranslateView's
    /// language picker. Mirrors AiClient.bcp47Name on Android.
    static let supportedTranslationLanguages: [(code: String, ar: String, en: String)] = [
        ("auto", "اكتشاف اللغة تلقائيًا", "Detect language automatically"),
        ("ar",   "العربية",              "Arabic"),
        ("en",   "الإنجليزية",            "English"),
        ("fr",   "الفرنسية",              "French"),
        ("es",   "الإسبانية",             "Spanish"),
        ("de",   "الألمانية",             "German"),
        ("it",   "الإيطالية",             "Italian"),
        ("pt",   "البرتغالية",            "Portuguese"),
        ("ru",   "الروسية",               "Russian"),
        ("tr",   "التركية",               "Turkish"),
        ("fa",   "الفارسية",              "Persian"),
        ("ur",   "الأردية",               "Urdu"),
        ("hi",   "الهندية",               "Hindi"),
        ("zh",   "الصينية",               "Chinese"),
        ("ja",   "اليابانية",             "Japanese"),
        ("ko",   "الكورية",               "Korean"),
        ("id",   "الإندونيسية",           "Indonesian"),
        ("ms",   "الماليزية",             "Malay"),
        ("nl",   "الهولندية",             "Dutch"),
        ("pl",   "البولندية",             "Polish"),
        ("sv",   "السويدية",              "Swedish"),
    ]

    static func languageName(_ code: String) -> String {
        let entry = supportedTranslationLanguages.first { $0.code == code }
        guard let entry else { return code }
        return AppLanguage.current == .arabic ? entry.ar : entry.en
    }
}
