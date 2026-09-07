import Foundation

enum ServerEndpoint {
    static let defaultsKey = "EnglishNova.serverURL"

    /// Production backend injected at build time from Codemagic/Xcode.
    /// This intentionally has no Railway fallback: once Build 50+ is moved to
    /// the standalone EnglishNova server, every hosted feature uses the same
    /// Google Cloud backend.
    private static var bundledURLString: String {
        (Bundle.main.object(forInfoDictionaryKey: "EnglishNovaServerURL") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var currentURL: URL? {
        let saved = (UserDefaults.standard.string(forKey: defaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let value = saved.isEmpty ? bundledURLString : saved
        guard !value.isEmpty,
              let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host != nil else { return nil }
        return url
    }

    static func save(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: defaultsKey)
        }
    }
}
