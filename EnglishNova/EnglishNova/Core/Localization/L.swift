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

    private var map: [String: String] = [:]           // bundled base translations
    private var overrides: [String: String] = [:]     // server (OTA) corrections

    private var overridesCacheURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("i18n-overrides.json")
    }

    private init() {
        // Synchronous read so the very first render is already in the right
        // language (AppSettings mirrors the choice here on every change).
        isEnglish = UserDefaults.standard.string(forKey: "ui.language") == "en"
        load()
        loadCachedOverrides()
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

    private func loadCachedOverrides() {
        guard let url = overridesCacheURL,
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        overrides = dict
    }

    func translate(_ arabic: String) -> String {
        guard isEnglish else { return arabic }
        return overrides[arabic] ?? map[arabic] ?? arabic
    }

    /// Fetch translation corrections published on the server (channel "i18n")
    /// so wrong translations can be fixed WITHOUT a new app build. The payload
    /// is a plain { arabic: english } map; it's cached on disk so it also
    /// applies offline on the next launch.
    func refreshFromServer() async {
        guard let base = ServerEndpoint.currentURL else { return }
        var comps = URLComponents(url: base.appendingPathComponent("content"),
                                  resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "channel", value: "i18n")]
        guard let url = comps?.url else { return }
        struct ContentResponse: Decodable { let payload: [String: String]? }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  data.count <= 5 * 1_024 * 1_024 else { return }
            let decoded = try JSONDecoder().decode(ContentResponse.self, from: data)
            guard let payload = decoded.payload, !payload.isEmpty else { return }
            overrides = payload
            if let cache = overridesCacheURL, let encoded = try? JSONEncoder().encode(payload) {
                try? encoded.write(to: cache, options: .atomic)
            }
        } catch {
            // Offline or unavailable — keep the cached/bundled translations.
        }
    }
}

/// Localize an Arabic source string. Use for any user-facing text — both dynamic
/// String values and (via the wrapping applied across the views) literal labels.
func L(_ arabic: String) -> String { Localizer.shared.translate(arabic) }

/// Localize an Arabic template that contains `%@` placeholders, substituting the
/// given (already stringified) values in order. Used for interpolated strings
/// like "%@ دقيقة" -> "%@ minutes". Manual %@ replacement avoids String(format:)
/// pitfalls with `%` and integer specifiers.
func Lf(_ arabicTemplate: String, _ args: String...) -> String {
    var result = Localizer.shared.translate(arabicTemplate)
    for arg in args {
        guard let range = result.range(of: "%@") else { break }
        result.replaceSubrange(range, with: arg)
    }
    return result
}
