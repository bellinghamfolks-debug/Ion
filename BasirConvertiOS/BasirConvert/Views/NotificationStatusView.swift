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
            Text(l10n.t("يتابع بصير مهامك على الخادم ولو أغلقت الشاشة أو انتقلت لتطبيق آخر، ويصلك إشعار عند كل ربع من التقدم وعند الاكتمال. لا تُغلق بصير بسحبه من مبدّل التطبيقات أثناء مهمة: iOS يوقف عندها كل متابعة حتى تفتحه.",
                        "Basir follows your tasks on the server even when the screen is off or you are in another app, and notifies you at each quarter and when done. Do not swipe Basir away in the app switcher during a task: iOS then stops all following until you open it."))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(l10n.t("أرسل إشعارًا تجريبيًا", "Send a test notification")) {
                    JobNotifier.sendTest(arabic: l10n.isArabic)
                    sentTest = true
                    UIAccessibility.post(notification: .announcement,
                                         argument: l10n.t("سيصل الإشعار بعد ثلاث ثوانٍ.", "It arrives in three seconds."))
                }
                .buttonStyle(.bordered)
                if checks.contains(where: { !$0.ok }) {
                    Button(l10n.t("افتح إعدادات iOS", "Open iOS Settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.bordered)
                }
            }
            if sentTest {
                Text(l10n.t("إن لم يصل خلال ثوانٍ، فالإشعارات متوقفة في إعدادات iOS أو التركيز مفعّل.",
                            "If it does not arrive within seconds, notifications are off in iOS Settings or a Focus is on."))
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
                              text: l10n.t("الإشعارات متوقفة لبصير في إعدادات iOS. فعّلها ليصلك خبر مهامك.",
                                           "Notifications are off for Basir in iOS Settings. Turn them on to hear about your tasks.")))
        default:
            list.append(Check(id: "allowed", ok: false,
                              text: l10n.t("لم يُطلب إذن الإشعارات بعد. فعّل «إشعار عند اكتمال المهمة».",
                                           "Notification permission was not asked yet. Turn on “Notify when a task completes”.")))
        }
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available:
            list.append(Check(id: "refresh", ok: true,
                              text: l10n.t("تحديث التطبيقات في الخلفية مفعّل.", "Background App Refresh is on.")))
        default:
            list.append(Check(id: "refresh", ok: false,
                              text: l10n.t("تحديث التطبيقات في الخلفية متوقف لبصير؛ قد تتأخر الإشعارات حتى تفتحه.",
                                           "Background App Refresh is off for Basir; notices may wait until you open it.")))
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            list.append(Check(id: "power", ok: false,
                              text: l10n.t("وضع توفير الطاقة مفعّل؛ قد يؤخر iOS متابعة المهام في الخلفية.",
                                           "Low Power Mode is on; iOS may delay following tasks in the background.")))
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
