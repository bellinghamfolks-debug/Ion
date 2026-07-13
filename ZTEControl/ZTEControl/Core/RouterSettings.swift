import Foundation
import Combine

/// Persisted connection settings for the router. The admin password is stored
/// in the Keychain; the host/IP in UserDefaults.
@MainActor
final class RouterSettings: ObservableObject {
    static let shared = RouterSettings()

    @Published var host: String {
        didSet { UserDefaults.standard.set(host, forKey: Keys.host) }
    }
    @Published var password: String {
        didSet { KeychainStore.set(password, for: Keys.password) }
    }

    private enum Keys {
        static let host = "zte.host"
        static let password = "zte.password"
    }

    init() {
        // ZTE MU5001 default gateway.
        host = UserDefaults.standard.string(forKey: Keys.host) ?? "192.168.0.1"
        password = KeychainStore.get(Keys.password) ?? ""
    }

    var baseURL: URL? {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        let withScheme = trimmed.hasPrefix("http") ? trimmed : "http://\(trimmed)"
        return URL(string: withScheme)
    }
}

/// Minimal Keychain wrapper for the admin password.
enum KeychainStore {
    private static let service = "com.ztecontrol.credentials"

    static func set(_ value: String, for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
