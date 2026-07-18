import SwiftUI

/// Backup is now account-based: progress is saved to the server automatically
/// and restored on any device by signing in. A local file export remains as an
/// optional extra, but the primary, reliable backup is the account.
struct BackupCenterView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var sync: ProgressSyncService
    @State private var exportURL: URL?
    @State private var statusMessage: String?

    var body: some View {
        List {
            if account.isAuthenticated {
                Section(L("النسخ الاحتياطي عبر حسابك")) {
                    Text(L("يُحفظ تقدّمك تلقائيًا في حسابك بعد كل درس، وتستعيده على أي جهاز بمجرد تسجيل الدخول."))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button {
                        Task { await sync.push() }
                    } label: {
                        Label(L("احفظ الآن في حسابي"), systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(sync.isSyncing)
                    Button {
                        Task { await sync.pull() }
                    } label: {
                        Label(L("استعادة من حسابي"), systemImage: "icloud.and.arrow.down")
                    }
                    .disabled(sync.isSyncing)
                    if let message = sync.syncMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Section(L("احفظ تقدّمك في السحابة")) {
                    NavigationLink {
                        AccountView()
                    } label: {
                        Label(L("أنشئ حسابًا أو سجّل الدخول"), systemImage: "person.crop.circle.badge.plus")
                    }
                    Text(L("النسخ الاحتياطي أصبح عبر الحساب: أنشئ حسابًا ليُحفظ تقدّمك تلقائيًا في الخادم ويُزامَن عبر أجهزتك."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section(L("تصدير محلي (اختياري)")) {
                Button {
                    Task { await createBackup() }
                } label: {
                    Label(L("تصدير نسخة كملف"), systemImage: "square.and.arrow.up")
                }
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label(L("مشاركة الملف"), systemImage: "square.and.arrow.up.on.square")
                    }
                }
                Text(L("للاحتفاظ بنسخة إضافية على جهازك أو مشاركتها. الاستعادة الأساسية تتم من حسابك."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let statusMessage {
                Section(L("الحالة")) { Text(statusMessage) }
            }
        }
        .navigationTitle(L("النسخ الاحتياطي"))
    }

    private func createBackup() async {
        do {
            exportURL = try await container.backupService.makeTemporaryBackupFile()
            statusMessage = L("تم إنشاء الملف. استخدم زر المشاركة لحفظه في الملفات أو إرساله.")
            ToastCenter.shared.show(L("تم إنشاء ملف النسخة"))
        } catch {
            statusMessage = Lf("تعذّر إنشاء الملف: %@", "\(error.localizedDescription)")
            ToastCenter.shared.show(L("تعذّر إنشاء الملف"), style: .error)
        }
    }
}
