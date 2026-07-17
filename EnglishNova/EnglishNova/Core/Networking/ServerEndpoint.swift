import Foundation

enum ServerEndpoint {
    static let defaultsKey = "EnglishNova.serverURL"

    /// The built-in production server. The app ships pointing here so accounts
    /// and progress sync work for everyone out of the box — no manual setup.
    static let defaultURLString = "https://ion-production-da28.up.railway.app"

    static var currentURL: URL? {
        let saved = (UserDefaults.standard.string(forKey: defaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Fall back to the built-in server when the user hasn't overridden it.
        let value = saved.isEmpty ? defaultURLString : saved
        return URL(string: value)
    }

    static func save(_ value: String) {
        UserDefaults.standard.set(value, forKey: defaultsKey)
    }
}
