import Foundation

/// Build-independent localization.
///
/// SwiftUI's implicit `.strings`/`.lproj` localization proved unreliable through
/// XcodeGen/CI (the English variant group didn't always end up in the bundle),
/// so the app does NOT depend on it. Instead every user-facing Arabic string is
/// looked up in `translations.json` (a plain bundled resource, copied exactly
/// like curriculum.json) and swapped to English when the UI language is English.
///
/// Arabic is the source language: keys ARE the Arabic text. In Arabic mode we
/// return the key unchanged; in English mode we return the mapped translation
/// (or the Arabic key as a safe fallback when a string isn't mapped yet).
final class Localizer {
    static let shared = Localizer()

    /// Toggled by AppSettings to match the chosen interface language.
    var isEnglish = false

    private var map: [String: String] = [:]

    private init() {
        // Synchronous read so the very first render is already in the right
        // language (AppSettings mirrors the choice here on every change).
        isEnglish = UserDefaults.standard.string(forKey: "ui.language") == "en"
        load()
    }

    private func load() {
        let url = Bundle.main.url(forResource: "translations", withExtension: "json",
                                  subdirectory: "LocalizationData")
            ?? Bundle.main.url(forResource: "translations", withExtension: "json")
        guard let url,
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        map = dict
    }

    func translate(_ arabic: String) -> String {
        guard isEnglish else { return arabic }
        return map[arabic] ?? arabic
    }
}

/// Localize an Arabic source string. Use for any user-facing text — both dynamic
/// String values and (via the wrapping applied across the views) literal labels.
func L(_ arabic: String) -> String { Localizer.shared.translate(arabic) }
