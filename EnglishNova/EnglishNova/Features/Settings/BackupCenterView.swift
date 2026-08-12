import SwiftUI

struct BackupCenterView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var sync: ProgressSyncService
    @State private var exportURL: URL?
    @State private var statusMessage: String?

    var body: some View {
        List {
            if account.isAuthenticated {
                Section(L("نسخة الحساب")) {
                    Text(L("يمكنك حفظ نسخة من تقدّمك في حسابك واستعادتها عند الانتقال إلى جهاز آخر."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        Task { await sync.push() }
                    } label: {
                        Label(L("حفظ نسخة الآن"), systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(sync.isSyncing)

                    Button {
                        Task { await sync.pull() }
                    } label: {
                        Label(L("استعادة النسخة المحفوظة"), systemImage: "icloud.and.arrow.down")
                    }
                    .disabled(sync.isSyncing)

                    Text(L("الاستعادة تستبدل بيانات التعلّم المحلية بالنسخة الموجودة في الحساب. استخدمها عندما تكون متأكدًا أن نسخة الحساب هي التي تريدها."))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let message = sync.syncMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Section(L("المزامنة تحتاج إلى حساب")) {
                    NavigationLink { AccountView() } label: {
                        Label(L("تسجيل الدخول أو إنشاء حساب"), systemImage: "person.crop.circle.badge.plus")
                    }
                    Text(L("من دون حساب يبقى تقدّمك محفوظًا محليًا على هذا الجهاز."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L("نسخة كملف")) {
                Button {
                    Task { await createBackup() }
                } label: {
                    Label(L("إنشاء ملف نسخة احتياطية"), systemImage: "doc.badge.plus")
                }

                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label(L("حفظ أو مشاركة الملف"), systemImage: "square.and.arrow.up")
                    }
                }

                Text(L("هذه نسخة إضافية يمكنك حفظها في تطبيق الملفات أو في مكان تختاره بنفسك."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let statusMessage {
                Section(L("آخر عملية")) {
                    Text(statusMessage)
                }
            }
        }
        .navigationTitle(L("النسخ الاحتياطي"))
    }

    private func createBackup() async {
        do {
            exportURL = try await container.backupService.makeTemporaryBackupFile()
            statusMessage = L("تم إنشاء الملف. يمكنك الآن حفظه أو مشاركته.")
            ToastCenter.shared.show(L("تم إنشاء النسخة الاحتياطية"))
        } catch {
            statusMessage = Lf("تعذر إنشاء الملف: %@", error.localizedDescription)
            ToastCenter.shared.show(L("تعذر إنشاء النسخة الاحتياطية"), style: .error)
        }
    }
}
