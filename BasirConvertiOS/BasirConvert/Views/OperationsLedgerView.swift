import SafariServices
import SwiftUI

/// The owner's server-side ledger retains records independently of local
/// files. Uses its own owner sign-in; the shared app token never grants access.
struct OperationsLedgerView: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    private struct Destination: Identifiable {
        let id = UUID()
        let url: URL
    }
    @State private var opened: Destination?
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(l10n.t("سجل العمليات والتكلفة", "Operations and cost ledger")).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text(l10n.t("تفاصيل كل عملية وطلبات النماذج والتوكنات والتكلفة التقديرية. يُحفظ السجل المستقل وفق إعدادات الاحتفاظ، ولا يؤدي حذف الملف من الهاتف إلى حذف سجل التكلفة.", "Review operations, model calls, tokens and estimated cost. The independent ledger follows your retention settings. Removing a phone file does not delete its cost record."))
                Text(l10n.t("يتطلب السجل تسجيل دخول مالك الخدمة. تكلفة الذكاء الاصطناعي تقديرية، ولا تمثّل فاتورة تشغيل الخادم والتخزين والشبكة.", "Owner sign-in is required. AI costs are estimates and do not represent server, storage or network billing."))
                if let base = settings.configuration.secureBaseURL {
                    Button(l10n.t("تسجيل الدخول", "Sign in")) { opened = Destination(url: base.appendingPathComponent("operations")) }
                    PrimaryActionButton(title: l10n.t("فتح السجل التفصيلي", "Open detailed ledger"), systemImage: "chart.bar.doc.horizontal") { opened = Destination(url: base.appendingPathComponent("operations")) }
                    Link(l10n.t("فتح السجل في Safari", "Open ledger in Safari"), destination: base.appendingPathComponent("operations"))
                } else { Text(l10n.t("اضبط عنوان الخادم الآمن أولًا.", "Configure the secure server address first.")) }
                Spacer()
            }.appScreenContent().background(BasirPalette.background)
                .navigationTitle(l10n.t("العمليات والتكلفة", "Operations and costs"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(l10n.t("إغلاق", "Close")) { dismiss() } } }
        }.sheet(item: $opened) { destination in
            LedgerBrowser(url: destination.url)
        }
    }
}
private struct LedgerBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
