import Foundation
import Combine

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

    @discardableResult
    func push(showFeedback: Bool = true) async -> Bool {
        guard let token = account.token else { return false }
        if isSyncing { return false }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let blob = try await backup.makeBackupData()
            let value = try JSONValue.from(data: blob)
            _ = try await api.send(
                path: "progress",
                method: "PUT",
                body: ProgressPushBody(data: value),
                response: ProgressPushResponse.self,
                bearerToken: token
            )
            lastSyncedAt = Date()
            syncMessage = L("تم حفظ نسخة من تقدّمك في الحساب.")
            if showFeedback {
                ToastCenter.shared.show(L("تم حفظ التقدّم"))
            }
            return true
        } catch {
            let detail = (error as? LocalizedError)?.errorDescription ?? L("خطأ غير معروف")
            syncMessage = Lf("تعذر حفظ التقدّم: %@", detail)
            if showFeedback {
                ToastCenter.shared.show(L("تعذر حفظ التقدّم"), style: .error)
            }
            return false
        }
    }

    @discardableResult
    func pushIfStale(maxAge: TimeInterval = 5 * 60) async -> Bool {
        if let lastSyncedAt, Date().timeIntervalSince(lastSyncedAt) < maxAge {
            return true
        }
        return await push(showFeedback: false)
    }

    @discardableResult
    func pull() async -> Bool {
        guard let token = account.token else { return false }
        if isSyncing { return false }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let response = try await api.get(
                path: "progress",
                response: ProgressPullResponse.self,
                bearerToken: token
            )
            guard let value = response.data else {
                syncMessage = L("لا توجد نسخة محفوظة في الحساب حتى الآن.")
                ToastCenter.shared.show(L("لا توجد نسخة محفوظة"), style: .info)
                return true
            }

            let blob = try value.encodedData()
            try await backup.restore(from: blob)
            lastSyncedAt = Date()
            syncMessage = L("تمت استعادة النسخة المحفوظة إلى هذا الجهاز.")
            ToastCenter.shared.show(L("تمت استعادة التقدّم"))
            return true
        } catch {
            let detail = (error as? LocalizedError)?.errorDescription ?? L("خطأ غير معروف")
            syncMessage = Lf("تعذرت استعادة التقدّم: %@", detail)
            ToastCenter.shared.show(L("تعذرت استعادة التقدّم"), style: .error)
            return false
        }
    }
}
