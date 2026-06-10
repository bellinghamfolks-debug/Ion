import Foundation

enum L10n {
    static func text(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: .main, value: key, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }

    static func pageList(_ pages: [Int]) -> String {
        let separator = isArabic ? "، " : ", "
        return pages.map(String.init).joined(separator: separator)
    }

    static var isArabic: Bool {
        let language = Bundle.main.preferredLocalizations.first ?? Locale.current.languageCode ?? "en"
        return language.lowercased().hasPrefix("ar")
    }
}
