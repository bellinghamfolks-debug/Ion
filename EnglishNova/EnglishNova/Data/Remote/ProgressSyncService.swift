import Foundation
import Combine

/// Syncs the full local learning state with the EnglishNova server. User-driven
/// syncs show feedback; AI personalization can request a quiet, throttled sync
/// so the server profile stays current without producing a toast on every visit.
@MainActor
final class ProgressSyncService: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncedAt: Date?
    @Published var syncMessage: String?

    private let api: APIClient
    private let account: AccountService
    private let backup: BackupService

    init(account: AccountService,
         backup: BackupService,
         api: APIClient = APIClient(configuration: APIConfiguration(baseURL: nil))) {
        self.account = account
        self.backup = backup
        self.api = api
    }

    /// Upload the current local progress to the server.
    @discardableResult
    func push(showFeedback: Bool = true) async -> Bool {
        guard let token = account.token else { return false }
        if isSyncing { return false }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let blob = try await backup.makeBackupData()
            let value = try JSONValue.from(data: blob)
            _ = try await api.send(path: "progress", method: "PUT",
                                   body: ProgressPushBody(data: value),
                                   response: ProgressPushResponse.self,
                                   bearerToken: token)
            lastSyncedAt = Date()
            syncMessage = "تم حفظ تقدّمك في حسابك."
            if showFeedback { ToastCenter.shared.show("تم حفظ تقدّمك") }
            return true
        } catch {
            syncMessage = "تعذّرت المزامنة: \((error as? LocalizedError)?.errorDescription ?? "خطأ")"
            if showFeedback { ToastCenter.shared.show("تعذّرت المزامنة", style: .error) }
            return false
        }
    }

    /// Keep the server-side learner profile reasonably fresh for AI requests,
    /// while avoiding repeated uploads when Home is opened several times.
    @discardableResult
    func pushIfStale(maxAge: TimeInterval = 5 * 60) async -> Bool {
        if let lastSyncedAt, Date().timeIntervalSince(lastSyncedAt) < maxAge { return true }
        return await push(showFeedback: false)
    }

    /// Download and apply the server's progress (used on sign-in / new device).
    @discardableResult
    func pull() async -> Bool {
        guard let token = account.token else { return false }
        if isSyncing { return false }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let response = try await api.get(path: "progress",
                                             response: ProgressPullResponse.self,
                                             bearerToken: token)
            guard let value = response.data else {
                syncMessage = "لا يوجد تقدّم محفوظ في الخادم بعد."
                ToastCenter.shared.show("لا يوجد تقدّم محفوظ بعد", style: .info)
                return true
            }
            let blob = try value.encodedData()
            try await backup.restore(from: blob)
            lastSyncedAt = Date()
            syncMessage = "تمت استعادة تقدّمك من حسابك."
            ToastCenter.shared.show("تمت استعادة تقدّمك")
            return true
        } catch {
            syncMessage = "تعذّرت الاستعادة: \((error as? LocalizedError)?.errorDescription ?? "خطأ")"
            ToastCenter.shared.show("تعذّرت الاستعادة", style: .error)
            return false
        }
    }
}
