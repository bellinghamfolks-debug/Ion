import SafariServices
import SwiftUI

/// The owner's server-side ledger retains records independently of local
/// files. Uses its own owner sign-in; the shared app token never grants access.
struct OperationsLedgerView: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var opened: URL?
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(l10n.t("سجل العمليات والتكلفة", "Operations and cost ledger")).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text(l10n.t("تفاصيل كل عملية وطلبات النماذج والتوكنات والتكلفة التقديرية. يُحفظ السجل المستقل ١٢ شهرًا من آخر نشاط، ولا يؤدي حذف الملف من الهاتف إلى حذف سجل التكلفة.", "Review operations, model calls, tokens and estimated cost. The independent ledger is retained for 12 months from last activity. Removing a phone file does not delete its cost record."))
                Text(l10n.t("يتطلب السجل تسجيل دخول مالك الخدمة. تكلفة الذكاء الاصطناعي تقديرية، ولا تمثّل فاتورة تشغيل الخادم والتخزين والشبكة.", "Owner sign-in is required. AI costs are estimates and do not represent server, storage or network billing."))
                if let base = settings.configuration.secureBaseURL {
                    Button(l10n.t("تسجيل الدخول", "Sign in")) { opened = base }
                    PrimaryActionButton(title: l10n.t("فتح السجل التفصيلي", "Open detailed ledger"), systemImage: "chart.bar.doc.horizontal") { opened = base.appendingPathComponent("operations") }
                } else { Text(l10n.t("اضبط عنوان الخادم الآمن أولًا.", "Configure the secure server address first.")) }
                Spacer()
            }.appScreenContent().background(BasirPalette.background)
                .navigationTitle(l10n.t("العمليات والتكلفة", "Operations and costs"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(l10n.t("إغلاق", "Close")) { dismiss() } } }
        }.sheet(isPresented: Binding(get: { opened != nil }, set: { if !$0 { opened = nil } })) {
            if let opened { LedgerBrowser(url: opened) }
        }
    }
}
private struct LedgerBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
