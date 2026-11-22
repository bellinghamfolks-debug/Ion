import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) var dismiss
    @AppStorage("sounds") var sounds = true
    @State var budget = ""
    @State var export = false
    @State var importing = false
    @State var pending: Book?
    @State var confirm = false
    @State var message: String?
    var body: some View {
        Form {
            Section("التفضيلات") {
                Toggle("أصوات الحفظ والسداد", isOn: $sounds)
                TextField("الميزانية الشهرية بالريال", text: $budget).keyboardType(.decimalPad).accessibilityLabel("الميزانية الشهرية بالريال")
                Button("حفظ الميزانية") {
                    let raw = budget.trimmingCharacters(in: .whitespacesAndNewlines)
                    let amount = raw.isEmpty ? 0 : Money.parse(raw)
                    guard let amount else { report("أدخل مبلغًا صحيحًا، أو اترك الحقل فارغًا لإلغاء الميزانية."); return }
                    do { try store.update { $0.budget = amount }; report("تم حفظ الميزانية") } catch { report(error.localizedDescription) }
                }
            }
            Section {
                Button("تصدير نسخة احتياطية") { export = true }.disabled(store.loadError != nil)
                Button("استعادة نسخة من الملفات") { importing = true }
            } header: { Text("النسخ الاحتياطي") } footer: { Text("تُحفظ العمليات على جهازك. ملف النسخة المصدّرة يحتوي الأسماء والمبالغ بصيغة قابلة للقراءة.") }
            if let message { Text(message) }
        }.navigationTitle("الإعدادات").onAppear { budget = store.book.budget == 0 ? "" : Money.input(store.book.budget) }
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } } }
        .fileExporter(isPresented: $export, document: Backup(store.book), contentType: .json, defaultFilename: "Ameen-Backup") { result in
            switch result { case .success: report("تم تصدير النسخة"); case .failure(let error): report(error.localizedDescription) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let book = try JSONDecoder().decode(Book.self, from: Data(contentsOf: url))
                try book.validate()
                pending = book; confirm = true
            } catch { report("تعذّرت استعادة الملف. " + error.localizedDescription) }
        }
        .confirmationDialog("استبدال السجل الحالي بنسخة تضم \(pending?.entries.count ?? 0) عملية؟", isPresented: $confirm, titleVisibility: .visible) {
            Button("استبدال واستعادة", role: .destructive) {
                guard let pending else { return }
                do { try store.restore(pending); budget = pending.budget == 0 ? "" : Money.input(pending.budget); report("تمت الاستعادة") }
                catch { report(error.localizedDescription) }
                self.pending = nil
            }
        }
    }
    func report(_ s: String) { message = s; UIAccessibility.post(notification: .announcement, argument: s) }
}
