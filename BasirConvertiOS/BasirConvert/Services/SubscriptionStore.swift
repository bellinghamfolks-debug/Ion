import Foundation
import StoreKit

/// Plans, purchases and the pages left, for every screen that needs them.
///
/// Purchases are made with StoreKit 2. Each one carries this device's
/// ``BillingAccount`` as its app account token, and the transaction Apple
/// signed is sent to the server, which verifies it and changes the plan. The
/// app never decides on its own that a plan is active: what it shows is what
/// the server answered.
@MainActor
final class SubscriptionStore: ObservableObject {
    static let shared = SubscriptionStore()

    enum PurchaseOutcome: Equatable {
        case purchased
        case pending
        case cancelled
        case failed(String)
    }

    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var status: BillingStatus?
    @Published private(set) var loading = false
    @Published private(set) var purchasingProductID: String?
    @Published var message: String?

    private var updates: Task<Void, Never>?
    private var language = "ar"

    /// Starts following purchases made anywhere (renewals, Ask to Buy,
    /// another device) and loads the plan. Safe to call more than once.
    func start(language: String) {
        self.language = language
        if updates == nil {
            updates = Task.detached(priority: .background) { [weak self] in
                for await result in Transaction.updates {
                    await self?.deliver(result)
                }
            }
        }
        Task { await refresh() }
    }

    func refresh() async {
        loading = true
        defer { loading = false }
        if products.isEmpty {
            if let loaded = try? await Product.products(for: BillingPlanID.allProductIDs) {
                products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            }
        }
        await refreshStatus()
    }

    func refreshStatus() async {
        guard let client = client() else { return }
        if let fresh = try? await client.billingStatus(language: language) { status = fresh }
    }

    func product(_ plan: BillingPlanID, yearly: Bool) -> Product? {
        plan.productID(yearly: yearly).flatMap { products[$0] }
    }

    func purchase(_ product: Product, l10n: L10n) async -> PurchaseOutcome {
        purchasingProductID = product.id
        defer { purchasingProductID = nil }
        do {
            let result = try await product.purchase(options: [.appAccountToken(BillingAccount.identifier)])
            switch result {
            case .success(let verification):
                let delivered = await deliver(verification)
                return delivered ? .purchased
                    : .failed(l10n.t("تم الشراء، لكن تعذر تأكيده مع بصير الآن. سيُطبَّق تلقائيًا عند عودة الاتصال، أو اضغط «استعادة المشتريات».",
                                     "The purchase went through but could not be confirmed with Basir yet. It will apply when you’re back online, or tap Restore purchases."))
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .cancelled
            }
        } catch {
            return .failed(l10n.t("تعذر إتمام الشراء: \(error.localizedDescription)",
                                  "The purchase could not be completed: \(error.localizedDescription)"))
        }
    }

    /// Restore purchases: everything this Apple ID owns, confirmed again.
    func restore(l10n: L10n) async {
        try? await AppStore.sync()
        var signed: [String] = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               BillingPlanID.plan(forProduct: transaction.productID) != nil {
                signed.append(result.jwsRepresentation)
            }
        }
        guard !signed.isEmpty else {
            message = l10n.t("لا توجد اشتراكات فعّالة في حساب Apple هذا.", "There are no active plans on this Apple ID.")
            return
        }
        guard let client = client() else { return }
        do {
            status = try await client.submitPurchases(signed, language: language)
            message = l10n.t("استُعيد اشتراكك: \(status?.planName ?? "").", "Your plan was restored: \(status?.planName ?? "").")
        } catch {
            message = ErrorLocalizer.message(for: error, l10n: l10n)
        }
    }

    /// Sends one signed transaction to the server and finishes it once the
    /// server has it. An unconfirmed transaction is left open, so StoreKit
    /// offers it again on the next launch.
    @discardableResult
    private func deliver(_ result: VerificationResult<Transaction>) async -> Bool {
        guard case .verified(let transaction) = result else { return false }
        guard BillingPlanID.plan(forProduct: transaction.productID) != nil else {
            await transaction.finish()
            return false
        }
        guard let client = client() else { return false }
        do {
            status = try await client.submitPurchases([result.jwsRepresentation], language: language)
            await transaction.finish()
            return true
        } catch {
            DiagnosticLogger.recordGlobal("BILLING submit failed product=\(transaction.productID) description=\(error.localizedDescription)")
            return false
        }
    }

    private func client() -> ProxyClient? {
        let configuration = BundledServerConfiguration.current()
        guard configuration.secureBaseURL != nil else { return nil }
        return ProxyClient(configuration: configuration)
    }
}
