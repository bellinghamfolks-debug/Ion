import Foundation
import Combine

/// Syncs the full local progress blob (produced by `BackupService`) with the
/// server. Push after study sessions; pull on sign-in to restore progress on a
/// new device. Simple last-write-wins by server timestamp.
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
    func push() async -> Bool {
        guard let token = account.token else { return false }
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
            return true
        } catch {
            syncMessage = "تعذّرت المزامنة: \((error as? LocalizedError)?.errorDescription ?? "خطأ")"
            return false
        }
    }

    /// Download and apply the server's progress (used on sign-in / new device).
    @discardableResult
    func pull() async -> Bool {
        guard let token = account.token else { return false }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let response = try await api.get(path: "progress",
                                             response: ProgressPullResponse.self,
                                             bearerToken: token)
            guard let value = response.data else {
                syncMessage = "لا يوجد تقدّم محفوظ في الخادم بعد."
                return true
            }
            let blob = try value.encodedData()
            try await backup.restore(from: blob)
            lastSyncedAt = Date()
            syncMessage = "تمت استعادة تقدّمك من حسابك."
            return true
        } catch {
            syncMessage = "تعذّرت الاستعادة: \((error as? LocalizedError)?.errorDescription ?? "خطأ")"
            return false
        }
    }
}
