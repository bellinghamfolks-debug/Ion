import SwiftUI

struct AppStatusView: View {
    @EnvironmentObject private var settings: BasirSettings

    private var version: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    private var connectionMode: String {
        settings.aiMode == "proxy"
            ? L10n.t("خادم وسيط", "Proxy server")
            : L10n.t("اتصال مباشر بـ Gemini", "Direct Gemini connection")
    }

    var body: some View {
        BasirScreen {
            BasirStatusBanner(
                text: settings.isConfigured
                    ? L10n.t("إعداد الاتصال مكتمل، ويمكن تشغيل ميزات الذكاء الاصطناعي.",
                             "Connection setup is complete and AI features can run.")
                    : L10n.t("إعداد الاتصال غير مكتمل. افتح الإعدادات وأضف مفتاح Gemini أو عنوان الخادم الوسيط.",
                             "Connection setup is incomplete. Open Settings and add a Gemini key or proxy server address."),
                tone: settings.isConfigured ? .success : .warning,
                title: settings.isConfigured
                    ? L10n.t("التطبيق جاهز", "App is ready")
                    : L10n.t("يلزم إكمال الإعداد", "Setup required")
            )

            BasirInfoRow(label: L10n.t("التطبيق", "App"), value: "بصير · Basir", systemImage: "app.fill")
            BasirInfoRow(label: L10n.t("الإصدار والبناء", "Version and build"), value: version, systemImage: "number")
            BasirInfoRow(label: L10n.t("طريقة الاتصال", "Connection method"), value: connectionMode, systemImage: "network")
            BasirInfoRow(label: L10n.t("اللغة", "Language"), value: settings.language.displayName, systemImage: "globe")
            BasirInfoRow(label: L10n.t("وضع الخصوصية", "Privacy mode"), value: settings.privacyMode ? L10n.t("مفعّل", "On") : L10n.t("غير مفعّل", "Off"), systemImage: "hand.raised.fill")

            NavigationLink { SettingsView() } label: {
                Label(L10n.t("فتح الإعدادات", "Open Settings"), systemImage: "gearshape.fill")
            }
            .buttonStyle(BasirPrimaryButtonStyle())
        }
        .navigationTitle(L10n.t("حالة التطبيق", "App status"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
