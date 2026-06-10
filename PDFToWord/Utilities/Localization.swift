import Foundation
import SwiftUI

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

/// SwiftUI has no built-in "live region" modifier on iOS 17, yet the views
/// express intent with `.accessibilityLiveRegion(.polite)`. This shim keeps
/// those call sites working and applies the closest standard behaviour:
/// marking the element as frequently updating so VoiceOver re-announces it
/// when its text changes (e.g. conversion progress).
enum AccessibilityLiveRegionMode {
    case polite
    case assertive
}

extension View {
    func accessibilityLiveRegion(_ mode: AccessibilityLiveRegionMode) -> some View {
        accessibilityAddTraits(.updatesFrequently)
    }
}
