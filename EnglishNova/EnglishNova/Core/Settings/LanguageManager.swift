import Foundation

/// Applies the chosen UI language at the system (bundle) level. SwiftUI resolves
/// `Text` localization from the main bundle's active language, so a full switch
/// needs the app to relaunch — which is why changing the language prompts a
/// restart. (iOS can't relaunch an app programmatically; the user reopens it.)
enum LanguageManager {
    private static let appleLanguagesKey = "AppleLanguages"

    /// Persist the language override so the whole bundle uses it on next launch.
    static func apply(_ language: AppSettings.InterfaceLanguage) {
        UserDefaults.standard.set([language.rawValue], forKey: appleLanguagesKey)
        UserDefaults.standard.synchronize()
    }

    /// The language the bundle will use on next launch (nil = follow the system).
    static var overrideCode: String? {
        (UserDefaults.standard.array(forKey: appleLanguagesKey) as? [String])?.first
    }

    /// Force-quit so the app relaunches in the newly selected language. Used only
    /// after the user confirms the restart prompt.
    static func restart() {
        // Let the confirmation alert dismiss first, then terminate.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { exit(0) }
    }
}
