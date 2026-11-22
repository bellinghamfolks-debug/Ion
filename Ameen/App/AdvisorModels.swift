import Foundation
import Security
#if canImport(FoundationModels)
import FoundationModels
#endif

enum DeviceAdvisor {
    static var available: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            return model.isAvailable && model.supportsLocale(Locale(identifier:"ar"))
        }
        #endif
        return false
    }
    static func answer(_ question: String, context: String) async throws -> AdvisorReply {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), available {
            let session = LanguageModelSession(instructions:"أجب بالعربية. فسّر الأرقام المقدمة فقط. اذكر الافتراضات، ولا تخترع بيانات مالية أو مستجدات أو معاملات.")
            let result = try await session.respond(to: context + "\nالسؤال: " + question)
            return AdvisorReply(text: result.content, origin:"نموذج Apple على الجهاز")
        }
        #endif
        throw AdvisorError.empty
    }
}

enum AdvisorKey {
    private static func item(_ provider: CloudProvider) -> [String:Any] { [
        kSecClass as String:kSecClassGenericPassword,
        kSecAttrService as String:"com.ameenledger.ios.advisor",
        kSecAttrAccount as String:provider.account
    ] }
    static func read(_ provider: CloudProvider) -> String? {
        var query = item(provider)
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data:data,encoding:.utf8)
    }
    static func save(_ key: String, for provider: CloudProvider) -> Bool {
        let item = item(provider)
        if key.isEmpty {
            let status = SecItemDelete(item as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let value: [String:Any] = [kSecValueData as String:Data(key.utf8), kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(item as CFDictionary,value as CFDictionary)
        if status == errSecItemNotFound { return SecItemAdd(item.merging(value) { _, new in new } as CFDictionary,nil) == errSecSuccess }
        return status == errSecSuccess
    }
}
