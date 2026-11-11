import SwiftUI

/// Only disposable exports created by these tools are listed. Source files,
/// the output library, active jobs and the operations ledger are excluded.
struct ExportStorageView: View {
    @EnvironmentObject private var l10n: L10n
    @State private var files: [URL] = []
    @State private var pending: URL?
    @State private var failure = false
    private func size(_ url: URL) -> Int64 { ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0 }
    private func refresh() {
        let root = FileManager.default.temporaryDirectory
        files = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("Basir-redacted-") || $0.lastPathComponent.hasPrefix("Basir-described-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    var body: some View {
        List {
            Section {
                Text(l10n.t("نسخ التصدير المؤقتة فقط. لا يشمل التنظيف الملفات الأصلية أو نتائج المكتبة أو المهام أو سجل التكلفة.", "Temporary exported copies only. Cleanup excludes originals, library results, jobs and the cost ledger."))
                Text(l10n.t("المساحة: ", "Space: ") + ByteCountFormatter.string(fromByteCount: files.reduce(0) { $0 + size($1) }, countStyle: .file))
            }
            Section {
                ForEach(files, id: \.self) { url in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(url.lastPathComponent).font(.headline)
                        Text(ByteCountFormatter.string(fromByteCount: size(url), countStyle: .file)).font(.caption)
                        ShareLink(item: url) { Label(l10n.t("مراجعة ومشاركة", "Review and share"), systemImage: "square.and.arrow.up") }
                        Button(l10n.t("حذف النسخة المؤقتة", "Delete temporary copy"), role: .destructive) { pending = url }
                    }.padding(.vertical, 8)
                }
                if files.isEmpty { Text(l10n.t("لا توجد نسخ تصدير مؤقتة.", "No temporary exports.")) }
            }
            if failure { Text(l10n.t("تعذر حذف النسخة. حاول مرة أخرى.", "Could not delete the copy. Try again.")) }
        }.navigationTitle(l10n.t("مساحة ملفات التصدير", "Export storage"))
            .onAppear { refresh() }
            .confirmationDialog(l10n.t("حذف النسخة المؤقتة؟", "Delete temporary copy?"), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                Button(l10n.t("حذف النسخة المحددة", "Delete selected copy"), role: .destructive) {
                    if let pending { do { try FileManager.default.removeItem(at: pending); failure = false } catch { failure = true } }
                    pending = nil; refresh()
                }
            }
    }
}
