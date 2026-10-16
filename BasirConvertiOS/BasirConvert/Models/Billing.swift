import Foundation
import Security

/// Basir's plans, as the app shows and counts them. The server decides; these
/// mirror basir/billing/plans.py so the app can say before a task starts how
/// many pages it will use.
enum BillingPlanID: String, Codable, CaseIterable, Sendable {
    case free, basic, reader, scholar, library

    static let paid: [BillingPlanID] = [.basic, .reader, .scholar, .library]

    var pagesPerMonth: Int {
        switch self {
        case .free: return 20
        case .basic: return 55
        case .reader: return 150
        case .scholar: return 320
        case .library: return 650
        }
    }

    func productID(yearly: Bool) -> String? {
        self == .free ? nil : "com.basir.convert.ios.\(rawValue).\(yearly ? "yearly" : "monthly")"
    }

    static func plan(forProduct productID: String) -> BillingPlanID? {
        paid.first { $0.productID(yearly: false) == productID || $0.productID(yearly: true) == productID }
    }

    static var allProductIDs: [String] {
        paid.flatMap { [$0.productID(yearly: false), $0.productID(yearly: true)].compactMap { $0 } }
    }

    @MainActor
    func name(_ l10n: L10n) -> String {
        switch self {
        case .free: return l10n.t("مجاني", "Free")
        case .basic: return l10n.t("أساسي", "Basic")
        case .reader: return l10n.t("قارئ", "Reader")
        case .scholar: return l10n.t("باحث", "Scholar")
        case .library: return l10n.t("مكتبة", "Library")
        }
    }

    /// Who the plan is for, in a sentence a screen reader can say on its own.
    @MainActor
    func audience(_ l10n: L10n) -> String {
        switch self {
        case .free: return l10n.t("للتجربة: مستندات قصيرة كل شهر.", "To try Basir: a few short documents a month.")
        case .basic: return l10n.t("للرسائل والمستندات اليومية.", "For letters and everyday documents.")
        case .reader: return l10n.t("لمن يقرأ كتابًا أو اثنين في الشهر.", "For one or two books a month.")
        case .scholar: return l10n.t("للطلاب والباحثين: مراجع ومقررات كاملة.", "For students and researchers: whole textbooks and references.")
        case .library: return l10n.t("للقراءة الكثيفة: عدة كتب طويلة كل شهر.", "For heavy reading: several long books a month.")
        }
    }
}

/// Pages a piece of work counts, the same rule as the server's.
enum BillingEstimate {
    static func pages(documentPages: Int, preferredModel: String?) -> Int {
        max(0, documentPages) * (preferredModel == AIModelChoice.accurate.rawValue ? 2 : 1)
    }
}

/// What the server says about this device's plan.
struct BillingStatus: Codable, Equatable, Sendable {
    let mode: String
    let plan: String
    let planName: String
    let pagesPerMonth: Int
    let pagesUsed: Int
    let pagesRemaining: Int
    let periodEnd: Date?
    let productID: String?
    let expiresAt: Date?
    let willRenew: Bool?

    enum CodingKeys: String, CodingKey {
        case mode, plan
        case planName = "plan_name"
        case pagesPerMonth = "pages_per_month"
        case pagesUsed = "pages_used"
        case pagesRemaining = "pages_remaining"
        case periodEnd = "period_end"
        case productID = "product_id"
        case expiresAt = "expires_at"
        case willRenew = "will_renew"
    }

    var planID: BillingPlanID { BillingPlanID(rawValue: plan) ?? .free }
    /// Plans exist on the server but nothing is limited yet.
    var isEnforced: Bool { mode == "enforce" }
    var isActive: Bool { mode != "off" }

    /// Whether a task of this many pages can start now.
    func fits(_ pages: Int) -> Bool { !isEnforced || pages <= pagesRemaining }

    static func decode(_ data: Data) throws -> BillingStatus {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let full = ISO8601DateFormatter()
            full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = full.date(from: text) ?? ISO8601DateFormatter().date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: text))
        }
        return try decoder.decode(BillingStatus.self, from: data)
    }
}

/// The identifier Basir counts this device's pages on.
///
/// Random, kept in the Keychain so it survives deleting and reinstalling the
/// app, and carries nothing about the person. A purchase is made with it as
/// its app account token, which is how the server ties a subscription to it.
enum BillingAccount {
    private static let service = "com.basir.convert.ios.billing"
    private static let account = "account-id"
    private static let lock = NSLock()
    private static var cached: UUID?

    static var identifier: UUID {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let value = read() ?? create()
        cached = value
        return value
    }

    static var header: String { identifier.uuidString.lowercased() }

    private static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func read() -> UUID? {
        var request = query()
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let text = String(data: data, encoding: .utf8) else { return nil }
        return UUID(uuidString: text)
    }

    private static func create() -> UUID {
        let value = UUID()
        var item = query()
        item[kSecValueData as String] = Data(value.uuidString.utf8)
        // Readable in the background (iOS wakes Basir to follow a task), and
        // never copied to another device through a backup.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemDelete(query() as CFDictionary)
        SecItemAdd(item as CFDictionary, nil)
        return value
    }
}
