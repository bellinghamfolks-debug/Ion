import SwiftUI
import UniformTypeIdentifiers

struct BackupCenterView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var statusMessage: String?
    @State private var isWorking = false

    var body: some View {
        List {
            Section("نسخة كاملة محلية") {
                Text("تتضمن الاسم المحلي، المستوى، النقاط، التقدم، نتائج المهارات، كلمات المراجعة، تقارير النطق، دفتر الأخطاء، نتائج الاختبارات، سجل المحادثات، والإعدادات. لا تتضمن التسجيلات الصوتية الخام ولا مفاتيح سرية.")
                    .font(.subheadline).foregroundStyle(.secondary)

                Button {
                    Task { await createBackup() }
                } label: {
                    Label("إنشاء ملف نسخة احتياطية", systemImage: "square.and.arrow.up")
                }
                .disabled(isWorking)

                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("مشاركة النسخة المحفوظة", systemImage: "square.and.arrow.up.on.square")
                    }
                }
            }

            Section("الاستعادة") {
                Button {
                    showImporter = true
                } label: {
                    Label("اختيار ملف EnglishNova", systemImage: "square.and.arrow.down")
                }
                .disabled(isWorking)
                Text("الاستعادة تستبدل بيانات التقدم والقاموس والإعدادات الحالية بما في الملف.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let statusMessage {
                Section("الحالة") {
                    Text(statusMessage)
                }
            }

            Section("الخصوصية") {
                Text("إنشاء الملف يتم على الجهاز. لا يرفعه التطبيق إلى أي خادم. مكان حفظه أو مشاركته تحدده أنت من ورقة المشاركة.")
            }
        }
        .navigationTitle("النسخ الاحتياطي")
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            Task { await importBackup(result) }
        }
    }

    private func createBackup() async {
        isWorking = true
        defer { isWorking = false }
        do {
            exportURL = try await container.backupService.makeTemporaryBackupFile()
            statusMessage = "تم إنشاء النسخة. استخدم زر المشاركة لحفظها في الملفات أو إرسالها إلى جهازك الآخر."
        } catch {
            statusMessage = "تعذر إنشاء النسخة: \(error.localizedDescription)"
        }
    }

    private func importBackup(_ result: Result<URL, Error>) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= BackupService.maximumBackupBytes else {
                throw BackupService.BackupError.backupTooLarge
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            try await container.backupService.restore(from: data)
            statusMessage = "تمت استعادة البيانات بنجاح. ستظهر التغييرات عند العودة أو تحديث الشاشات."
        } catch {
            statusMessage = "تعذرت الاستعادة: \(error.localizedDescription)"
        }
    }
}
