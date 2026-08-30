import Foundation
import SwiftUI

@MainActor
final class L10n: ObservableObject {
    private static let key = "interface_language"

    @Published var language: InterfaceLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.key) }
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.key),
           let value = InterfaceLanguage(rawValue: saved) {
            language = value
        } else {
            language = Locale.current.language.languageCode?.identifier == "ar" ? .arabic : .english
        }
    }

    var isArabic: Bool { language.isArabic }
    var layoutDirection: LayoutDirection { isArabic ? .rightToLeft : .leftToRight }
    var locale: Locale { Locale(identifier: language.rawValue) }

    func t(_ arabic: String, _ english: String) -> String {
        isArabic ? arabic : english
    }
}


