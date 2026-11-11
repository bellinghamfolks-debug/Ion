import SwiftUI
import UniformTypeIdentifiers

struct PrivacyReviewView: View {
    @EnvironmentObject private var l10n: L10n
    @Environment(\.dismiss) private var dismiss
    @State private var source: URL?
    @State private var findings: [PrivateDocumentRedactor.Finding] = []
    @State private var selected = Set<UUID>()
    @State private var phrases = ""
    @State private var picker = false
    @State private var busy = false
    @State private var status = ""
    @State private var output: URL?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(l10n.t("مراجعة محلية قبل الإرسال", "Local review before upload")).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text(l10n.t("يبحث بصير عن أرقام الاتصال والهويات والحسابات والبريد الإلكتروني. قد يفوّت التعرف الآلي بيانات أو أسماء؛ أضف عباراتك وراجع النتيجة قبل مشاركتها. يُحجب السطر كاملًا لضمان تغطية موضعه. لا تُرسل البيانات إلى الخادم.", "Basir detects phone numbers, identifiers, accounts and email addresses locally. Recognition may miss data or names. Add phrases and review the output before sharing. Entire matching lines are covered. Nothing is uploaded."))
                    CardActionButton(title: l10n.t("اختيار PDF أو صورة", "Choose PDF or image"), systemImage: "doc") { picker = true }.disabled(busy)
                    if let source {
                        Text(source.lastPathComponent).font(.headline)
                        TextField(l10n.t("عبارات إضافية للحجب، عبارة في كل سطر", "Additional phrases, one per line"), text: $phrases, axis: .vertical).textFieldStyle(.roundedBorder)
                        PrimaryActionButton(title: l10n.t("فحص المعلومات الحساسة", "Scan sensitive information"), systemImage: "magnifyingglass") { scan(source) }.disabled(busy)
                    }
                    if busy { ProgressView(status) }
                    if let error { InlineMessage(text: error, isError: true) }
                    if !status.isEmpty && !busy { Text(status).accessibilityAddTraits(.isHeader) }
                    ForEach(findings) { finding in
                        Toggle(isOn: Binding(get: { selected.contains(finding.id) }, set: { value in
                            if value { selected.insert(finding.id) } else { selected.remove(finding.id) }; output = nil
                        })) { Text(l10n.t("الصفحة \(finding.page): \(finding.text)", "Page \(finding.page): \(finding.text)")) }
                            .padding().background(BasirPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if !findings.isEmpty {
                        PrimaryActionButton(title: l10n.t("إنشاء نسخة بالمعلومات المحجوبة", "Create redacted copy"), systemImage: "hand.raised.fill") { export() }.disabled(busy || selected.isEmpty)
                    }
                    if let output { ShareLink(item: output) { Label(l10n.t("مراجعة النسخة ومشاركتها", "Review and share copy"), systemImage: "square.and.arrow.up") } }
                }.appScreenContent()
            }.background(BasirPalette.background).navigationTitle(l10n.t("حماية بيانات المستند", "Document privacy"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(l10n.t("إغلاق", "Close")) { dismiss() } } }
        }.fullScreenCover(isPresented: $picker) {
            BasirDocumentPicker(contentTypes: [.pdf, .image], allowsMultipleSelection: false, onPick: { urls in
                source = urls.first; findings = []; selected = []; output = nil; status = ""; picker = false
            }, onCancel: { picker = false })
        }
    }
    private func scan(_ source: URL) {
        busy = true; error = nil; output = nil
        let phrases = phrases.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        Task {
            defer { busy = false }
            do {
                findings = try await Task.detached { try PrivateDocumentRedactor.scan(source, phrases: phrases) { _, _ in } }.value
                selected = Set(findings.map(\.id))
                status = l10n.t("نتائج تحتاج مراجعتك: \(findings.count) سطر. عدم العثور على نتائج لا يثبت خلو المستند من البيانات الحساسة.", "Review \(findings.count) matching lines. No matches does not prove the document has no sensitive information.")
            } catch { self.error = l10n.t("تعذر فحص الملف محليًا. لم يُرسل شيء.", "Local scan failed. Nothing was uploaded.") }
        }
    }
    private func export() {
        guard let source else { return }; busy = true; error = nil
        let chosen = findings.filter { selected.contains($0.id) }
        Task {
            defer { busy = false }
            do { output = try await Task.detached { try PrivateDocumentRedactor.export(source, findings: chosen) }.value }
            catch { self.error = l10n.t("تعذر إنشاء النسخة المحجوبة.", "Could not create the redacted copy.") }
        }
    }
}
