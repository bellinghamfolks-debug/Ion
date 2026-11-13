import SwiftUI

/// The owner's server-side ledger retains records independently of local
/// files. Uses its own owner sign-in; the shared app token never grants access.
struct OperationsLedgerView: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var launchFailed = false
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(l10n.t("سجل العمليات والتكلفة", "Operations and cost ledger")).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text(l10n.t("تفاصيل كل عملية وطلبات النماذج والتوكنات والتكلفة التقديرية. يُحفظ السجل المستقل وفق إعدادات الاحتفاظ، ولا يؤدي حذف الملف من الهاتف إلى حذف سجل التكلفة.", "Review operations, model calls, tokens and estimated cost. The independent ledger follows your retention settings. Removing a phone file does not delete its cost record."))
                Text(l10n.t("يتطلب السجل تسجيل دخول مالك الخدمة. تكلفة الذكاء الاصطناعي تقديرية، ولا تمثّل فاتورة تشغيل الخادم والتخزين والشبكة.", "Owner sign-in is required. AI costs are estimates and do not represent server, storage or network billing."))
                if let base = settings.configuration.secureBaseURL {
                    Button(l10n.t("تسجيل الدخول", "Sign in")) { openLedger(base) }
                    PrimaryActionButton(title: l10n.t("فتح السجل التفصيلي", "Open detailed ledger"), systemImage: "chart.bar.doc.horizontal") { openLedger(base) }
                    Text(l10n.t("يُفتح السجل في المتصفح. يمكنك العودة إلى بصير بعد الانتهاء.", "The ledger opens in your browser. You can return to Basir when finished."))
                        .font(.footnote).foregroundStyle(BasirPalette.secondaryText)
                } else { Text(l10n.t("اضبط عنوان الخادم الآمن أولًا.", "Configure the secure server address first.")) }
                if launchFailed {
                    Text(l10n.t("تعذر فتح المتصفح. أعد المحاولة.", "The browser could not open. Please try again."))
                        .foregroundStyle(BasirPalette.warning)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer()
            }.appScreenContent().background(BasirPalette.background)
                .navigationTitle(l10n.t("العمليات والتكلفة", "Operations and costs"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(l10n.t("إغلاق", "Close")) { dismiss() } } }
        }
    }

    private func openLedger(_ base: URL) {
        launchFailed = false
        openURL(base.appendingPathComponent("operations")) { accepted in
            launchFailed = !accepted
        }
    }
}
