import Foundation

/// The app speaks Arabic or English, following the language chosen for the
/// app in iOS Settings (or the device language).
enum AppLanguage: String {
    case arabic = "ar"
    case english = "en"

    static var current: AppLanguage {
        let preferred = Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "ar"
        return preferred.hasPrefix("en") ? .english : .arabic
    }

    var speechCode: String { self == .arabic ? "ar-SA" : "en-US" }
    var locale: Locale { Locale(identifier: self == .arabic ? "ar" : "en") }
}

/// Looks up interface text. Missing keys show the key itself so they are
/// caught in testing (Scripts/validate_strings.py fails the build on them).
func L(_ key: String) -> String {
    guard let entry = Strings.table[key] ?? StringsLife.table[key] ?? StringsPro.table[key] else { return key }
    return AppLanguage.current == .english ? entry.en : entry.ar
}

func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), arguments: arguments)
}
