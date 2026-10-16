import StoreKit
import SwiftUI

/// Settings › My plan: the pages left this month, the plans, buying,
/// restoring and managing — written to be heard as well as read.
struct SubscriptionView: View {
    @EnvironmentObject private var l10n: L10n
    @StateObject private var store = SubscriptionStore.shared
    @State private var yearly = false
    @State private var showManage = false
    @State private var outcome: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: BasirSpacing.l) {
                    Text(l10n.t("اشتراكي", "My plan"))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    currentCard
                    if let message = outcome ?? store.message {
                        InlineMessage(text: message, isError: false)
                    }
                    SectionHeading(title: l10n.t("الخطط", "Plans"))
                    Picker(l10n.t("مدة الاشتراك", "Billing period"), selection: $yearly) {
                        Text(l10n.t("شهري", "Monthly")).tag(false)
                        Text(l10n.t("سنوي: شهران مجانًا", "Yearly: two months free")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    ForEach(BillingPlanID.paid, id: \.self) { planCard($0) }
                    countingCard
                    actions
                    disclosure
                }
                .appScreenContent(bottomPadding: 28)
            }
            .refreshable { await store.refresh() }
        }
        .foregroundStyle(BasirPalette.primaryText)
        .navigationTitle(l10n.t("اشتراكي", "My plan"))
        .navigationBarTitleDisplayMode(.inline)
        .manageSubscriptionsSheet(isPresented: $showManage)
        .task { store.start(language: l10n.isArabic ? "ar" : "en") }
    }

    // MARK: The pages left

    private var currentCard: some View {
        let status = store.status
        let plan = status?.planID ?? .free
        let total = status?.pagesPerMonth ?? plan.pagesPerMonth
        let remaining = status?.pagesRemaining ?? total
        return VStack(alignment: .leading, spacing: BasirSpacing.s) {
            Text(l10n.t("خطتك: \(plan.name(l10n))", "Your plan: \(plan.name(l10n))"))
                .font(.title3.weight(.bold))
            Text(l10n.t("باقي لك \(remaining) من \(total) صفحة هذا الشهر.",
                        "\(remaining) of \(total) pages left this month."))
            ProgressView(value: Double(max(0, total - remaining)), total: Double(max(1, total)))
                .tint(BasirPalette.accent)
                .accessibilityHidden(true)
            if let end = status?.periodEnd {
                Text(l10n.t("تتجدد صفحاتك في \(Self.date(end, l10n)).", "Your pages renew on \(Self.date(end, l10n))."))
                    .font(.footnote).foregroundStyle(BasirPalette.secondaryText)
            }
            if let expires = status?.expiresAt, plan != .free {
                Text(status?.willRenew == false
                     ? l10n.t("ينتهي اشتراكك في \(Self.date(expires, l10n)) ولن يتجدد.",
                              "Your plan ends on \(Self.date(expires, l10n)) and will not renew.")
                     : l10n.t("يتجدد اشتراكك تلقائيًا في \(Self.date(expires, l10n)).",
                              "Your plan renews automatically on \(Self.date(expires, l10n))."))
                    .font(.footnote).foregroundStyle(BasirPalette.secondaryText)
            }
            if status == nil {
                Text(l10n.t("تعذر جلب رصيدك الآن. اسحب للأسفل للتحديث.",
                            "Your balance could not be loaded. Pull down to refresh."))
                    .font(.footnote).foregroundStyle(BasirPalette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
        .accessibilityElement(children: .combine)
    }

    // MARK: Plans

    private func planCard(_ plan: BillingPlanID) -> some View {
        let product = store.product(plan, yearly: yearly)
        let current = store.status?.productID == plan.productID(yearly: yearly)
        let price = product?.displayPrice ?? l10n.t("السعر غير متاح الآن", "Price unavailable")
        let period = yearly ? l10n.t("سنويًا", "a year") : l10n.t("شهريًا", "a month")
        return VStack(alignment: .leading, spacing: BasirSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.name(l10n)).font(.title3.weight(.bold))
                Spacer()
                Text("\(price) \(period)").font(.headline)
            }
            Text(l10n.t("\(plan.pagesPerMonth) صفحة كل شهر", "\(plan.pagesPerMonth) pages every month"))
                .font(.body.weight(.semibold))
            Text(plan.audience(l10n)).font(.subheadline).foregroundStyle(BasirPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if current {
                Label(l10n.t("خطتك الحالية", "Your current plan"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(BasirPalette.success)
            } else if let product {
                Button {
                    Task { await buy(product, plan: plan) }
                } label: {
                    HStack {
                        if store.purchasingProductID == product.id { ProgressView() }
                        Text(l10n.t("اشترك في \(plan.name(l10n))", "Subscribe to \(plan.name(l10n))"))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.purchasingProductID != nil)
                .accessibilityHint(l10n.t("\(price) \(period). يتجدد تلقائيًا حتى تلغيه.",
                                          "\(price) \(period). Renews automatically until you cancel."))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
        .accessibilityElement(children: .contain)
    }

    private var countingCard: some View {
        InfoCard(
            title: l10n.t("كيف تُحسب الصفحات", "How pages are counted"),
            text: l10n.t("""
                كل صفحة PDF أو صورة تُقرأ أو تُترجم أو تُوصف صفحة واحدة، وبخيار «الأدق» صفحتان. \
                الصفحات التي تعذرت قراءتها والصفحات الفارغة والمهام الملغاة لا تُحسب. \
                التلخيص صفحة لكل 20 ألف حرف، والسؤال عن مستند صفحة لكل 25 ألف حرف. \
                القراءة الفورية على جهازك مجانية دائمًا وغير محدودة.
                """,
                """
                Each PDF page or image read, translated or described counts as one page; with Most accurate, two. \
                Pages that could not be read, blank pages and cancelled tasks are not counted. \
                A summary counts one page per 20,000 characters, a question about a document one per 25,000. \
                Instant reading on your device is always free and unlimited.
                """),
            systemImage: "doc.text.magnifyingglass")
    }

    private var actions: some View {
        VStack(spacing: BasirSpacing.s) {
            Button(l10n.t("استعادة المشتريات", "Restore purchases")) {
                Task { outcome = nil; await store.restore(l10n: l10n) }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            if store.status?.planID != .free {
                Button(l10n.t("إدارة الاشتراك أو إلغاؤه", "Manage or cancel your plan")) { showManage = true }
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .buttonStyle(.bordered)
    }

    /// What App Review and the person need to know before paying.
    private var disclosure: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            Text(l10n.t("""
                يُدفع الاشتراك من حساب Apple عند تأكيد الشراء، ويتجدد تلقائيًا بنفس السعر والمدة ما لم تُلغه قبل \
                24 ساعة على الأقل من نهاية المدة الحالية. تديره أو تلغيه من إعدادات حسابك في App Store. \
                الصفحات غير المستخدمة لا تنتقل إلى الشهر التالي.
                """,
                """
                Payment is charged to your Apple ID when you confirm the purchase. The plan renews automatically at the \
                same price and length unless you cancel at least 24 hours before the current period ends. Manage or \
                cancel it in your App Store account settings. Unused pages do not carry over to the next month.
                """))
                .font(.footnote).foregroundStyle(BasirPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: BasirSpacing.m) {
                Button(l10n.t("شروط الاستخدام", "Terms of Use")) { open("/legal/terms") }
                Button(l10n.t("سياسة الخصوصية", "Privacy Policy")) { open("/legal/privacy") }
            }
            .font(.footnote.weight(.semibold))
        }
    }

    // MARK: Actions

    private func buy(_ product: Product, plan: BillingPlanID) async {
        outcome = nil
        switch await store.purchase(product, l10n: l10n) {
        case .purchased:
            outcome = l10n.t("تم اشتراكك في \(plan.name(l10n)). صار لك \(plan.pagesPerMonth) صفحة هذا الشهر.",
                             "You’re subscribed to \(plan.name(l10n)). You have \(plan.pagesPerMonth) pages this month.")
        case .pending:
            outcome = l10n.t("الشراء بانتظار الموافقة. سيُطبَّق فور اعتماده.",
                             "The purchase is waiting for approval. It will apply as soon as it is approved.")
        case .cancelled:
            break
        case .failed(let message):
            outcome = message
        }
        if let outcome { UIAccessibility.post(notification: .announcement, argument: outcome) }
    }

    private func open(_ path: String) {
        if let url = BasirPublicLinks.url(path, isArabic: l10n.isArabic) { openURL(url) }
    }

    private static func date(_ value: Date, _ l10n: L10n) -> String {
        let formatter = DateFormatter()
        formatter.locale = l10n.locale
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: value)
    }
}
