import Foundation

enum ServerEndpoint {
    static let defaultsKey = "EnglishNova.serverURL"

    /// Stable production Basir Cloud Run service. Codemagic/Xcode may override
    /// this value, but a normal unsigned Build 53 works without extra setup.
    private static let productionServiceURL = "https://basir-convert-api-1045442243599.europe-west4.run.app"

    /// Shared Basir Cloud Run service injected at build time from Codemagic/Xcode.
    /// EnglishNova owns a namespaced API below /api/englishnova, while Basir's
    /// existing conversion endpoints remain untouched.
    private static var bundledURLString: String {
        let injected = (Bundle.main.object(forInfoDictionaryKey: "EnglishNovaServerURL") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return injected.isEmpty || injected.contains("$(") ? productionServiceURL : injected
    }

    static var currentURL: URL? {
        // The production endpoint always wins over an old URL saved on the
        // device. This prevents a previous Railway/standalone test endpoint
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
