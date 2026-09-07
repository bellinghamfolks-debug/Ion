import Foundation

enum ServerEndpoint {
    static let defaultsKey = "EnglishNova.serverURL"

    /// Shared Basir Cloud Run service injected at build time from Codemagic/Xcode.
    /// EnglishNova owns a namespaced API below /api/englishnova, while Basir's
    /// existing conversion endpoints remain untouched.
    private static var bundledURLString: String {
        (Bundle.main.object(forInfoDictionaryKey: "EnglishNovaServerURL") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var currentURL: URL? {
        // A production build-time endpoint always wins over an old URL saved on
        // the device. This prevents a previous Railway/standalone test endpoint
        // from silently overriding the shared Google Cloud backend.
        if let bundled = normalizedBaseURL(bundledURLString) {
            return bundled
        }
        let saved = (UserDefaults.standard.string(forKey: defaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedBaseURL(saved)
    }

    static func save(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: defaultsKey)
        }
    }

    private static func normalizedBaseURL(_ value: String) -> URL? {
        guard !value.isEmpty,
              var components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.host != nil else { return nil }

        let path = components.path
            .split(separator: "/")
            .map(String.init)
        if Array(path.suffix(2)) != ["api", "englishnova"] {
            components.path = "/" + (path + ["api", "englishnova"]).joined(separator: "/")
        }
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
