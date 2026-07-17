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
                Section("النسخ الاحتياطي عبر حسابك") {
                    Text("يُحفظ تقدّمك تلقائيًا في حسابك بعد كل درس، وتستعيده على أي جهاز بمجرد تسجيل الدخول.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button {
                        Task { await sync.push() }
                    } label: {
                        Label("احفظ الآن في حسابي", systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(sync.isSyncing)
                    Button {
                        Task { await sync.pull() }
                    } label: {
                        Label("استعادة من حسابي", systemImage: "icloud.and.arrow.down")
                    }
                    .disabled(sync.isSyncing)
                    if let message = sync.syncMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Section("احفظ تقدّمك في السحابة") {
                    NavigationLink {
                        AccountView()
                    } label: {
                        Label("أنشئ حسابًا أو سجّل الدخول", systemImage: "person.crop.circle.badge.plus")
                    }
                    Text("النسخ الاحتياطي أصبح عبر الحساب: أنشئ حسابًا ليُحفظ تقدّمك تلقائيًا في الخادم ويُزامَن عبر أجهزتك.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("تصدير محلي (اختياري)") {
                Button {
                    Task { await createBackup() }
                } label: {
                    Label("تصدير نسخة كملف", systemImage: "square.and.arrow.up")
                }
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("مشاركة الملف", systemImage: "square.and.arrow.up.on.square")
                    }
                }
                Text("للاحتفاظ بنسخة إضافية على جهازك أو مشاركتها. الاستعادة الأساسية تتم من حسابك.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let statusMessage {
                Section("الحالة") { Text(statusMessage) }
            }
        }
        .navigationTitle("النسخ الاحتياطي")
    }

    private func createBackup() async {
        do {
            exportURL = try await container.backupService.makeTemporaryBackupFile()
            statusMessage = "تم إنشاء الملف. استخدم زر المشاركة لحفظه في الملفات أو إرساله."
            ToastCenter.shared.show("تم إنشاء ملف النسخة")
        } catch {
            statusMessage = "تعذّر إنشاء الملف: \(error.localizedDescription)"
            ToastCenter.shared.show("تعذّر إنشاء الملف", style: .error)
        }
    }
}
