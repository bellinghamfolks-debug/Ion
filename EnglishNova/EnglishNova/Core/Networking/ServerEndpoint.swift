import Foundation

enum ServerEndpoint {
    static let defaultsKey = "EnglishNova.serverURL"

    static var currentURL: URL? {
        let value = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        return URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func save(_ value: String) {
        UserDefaults.standard.set(value, forKey: defaultsKey)
    }
}
