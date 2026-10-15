import ActivityKit
import SwiftUI
import UIKit
import UserNotifications

/// Settings › Sounds and notifications: what decides whether Basir's
/// notifications arrive on this iPhone, checked live, with a test button.
struct NotificationStatusView: View {
    @EnvironmentObject private var l10n: L10n
    @Environment(\.openURL) private var openURL
    @State private var checks: [Check] = []
    @State private var sentTest = false

    struct Check: Identifiable {
        let id: String
        let ok: Bool
        let text: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            Text(l10n.t("حالة الإشعارات على هذا الجهاز", "Notifications on this iPhone"))
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            ForEach(checks) { check in
                HStack(alignment: .firstTextBaseline, spacing: BasirSpacing.s) {
                    Image(systemName: check.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(check.ok ? BasirPalette.accent : .orange)
                        .accessibilityHidden(true)
                    Text(check.text)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel((check.ok ? l10n.t("جيد: ", "OK: ") : l10n.t("تنبيه: ", "Attention: ")) + check.text)
            }
            Text(l10n.t("بعد رفع الملف، تستمر معالجته حتى لو انتقلت إلى تطبيق آخر. يحدّث بصير الإشعار عند بلوغ 25 و50 و75 بالمئة، ثم عند الاكتمال. قد يؤخر iPhone التحديثات في الخلفية. تجنّب إغلاق بصير من مبدّل التطبيقات أثناء المهمة حتى يتمكن من متابعة تقدمها.",
                        "Once the file has uploaded, processing continues even when you switch apps. Basir updates the notification at 25, 50, and 75 percent, then on completion. Your iPhone may delay background updates. Avoid closing Basir from the app switcher during a task so it can keep checking progress."))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(l10n.t("إرسال إشعار تجريبي", "Send a test notification")) {
                    JobNotifier.sendTest(arabic: l10n.isArabic)
                    sentTest = true
                    UIAccessibility.post(notification: .announcement,
                                         argument: l10n.t("تمت جدولة إشعار تجريبي بعد ثلاث ثوانٍ.", "A test notification is scheduled for three seconds from now."))
                }
                .buttonStyle(.bordered)
                if checks.contains(where: { !$0.ok }) {
                    Button(l10n.t("فتح إعدادات iPhone", "Open iOS Settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.bordered)
                }
            }
            if sentTest {
                Text(l10n.t("إذا لم يظهر الإشعار، فتحقق من السماح بإشعارات بصير ومن إعدادات التركيز في iPhone.",
                            "If the notification does not appear, check Basir’s notification permissions and your iPhone’s Focus settings."))
                    .font(.footnote)
                    .foregroundStyle(BasirPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
    }

    @MainActor
    private func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        var list: [Check] = []
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            let lockScreen = settings.lockScreenSetting == .enabled
            list.append(Check(id: "allowed", ok: true,
                              text: lockScreen
                                ? l10n.t("الإشعارات مسموحة، وتظهر على شاشة القفل.", "Notifications are allowed and show on the Lock Screen.")
                                : l10n.t("الإشعارات مسموحة، لكنها لا تظهر على شاشة القفل.", "Notifications are allowed but hidden from the Lock Screen.")))
        case .denied:
            list.append(Check(id: "allowed", ok: false,
                              text: l10n.t("إشعارات بصير غير مسموحة. فعّلها من إعدادات iPhone لمتابعة حالة مهامك.",
                                           "Basir notifications are not allowed. Enable them in iPhone Settings to receive task updates.")))
        default:
            list.append(Check(id: "allowed", ok: false,
                              text: l10n.t("لم يُطلب إذن الإشعارات بعد. فعّل «إشعار عند اكتمال المهمة».",
                                           "Basir has not requested notification permission yet. Turn on “Notify when a task completes” to allow notifications.")))
        }
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available:
            list.append(Check(id: "refresh", ok: true,
                              text: l10n.t("تحديث التطبيقات في الخلفية مفعّل.", "Background App Refresh is on.")))
        default:
            list.append(Check(id: "refresh", ok: false,
                              text: l10n.t("تحديث التطبيقات في الخلفية متوقف لبصير؛ قد تتأخر الإشعارات حتى تفتحه.",
                                           "Background App Refresh is off for Basir. Notifications may be delayed until you open the app.")))
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            list.append(Check(id: "power", ok: false,
                              text: l10n.t("وضع توفير الطاقة مفعّل؛ قد يؤخر iOS متابعة المهام في الخلفية.",
                                           "Low Power Mode is on. Your iPhone may delay background progress updates.")))
        }
        if #available(iOS 16.2, *) {
            let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
            list.append(Check(id: "live", ok: enabled,
                              text: enabled
                                ? l10n.t("الأنشطة الحية مفعّلة: يظهر تقدم المهمة على شاشة القفل.", "Live Activities are on: progress shows on the Lock Screen.")
                                : l10n.t("الأنشطة الحية متوقفة لبصير.", "Live Activities are off for Basir.")))
        }
        checks = list
    }
}
