import SwiftUI

struct AboutView: View {
    private let contactEmail = "ubdallahalrashdee@gmail.com"

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        BasirScreen {
            BasirHero(
                eyebrow: L10n.t("عن التطبيق", "ABOUT"),
                title: L10n.t("بصير", "Basir"),
                subtitle: L10n.t(
                    "مساعد وصول للصور والمستندات والنصوص والمحادثة، صُمّم ليكون واضحًا مع قارئ الشاشة.",
                    "An accessibility assistant for images, documents, text, and conversation, designed to work clearly with a screen reader."
                ),
                systemImage: "accessibility"
            )

            BasirSectionHeader(title: L10n.t("ما الذي يقدمه؟", "What does it do?"))
            Text(L10n.t(
                "يصف بصير الصور، ويقرأ المستندات، ويترجم النصوص، ويدعم الأسئلة والمحادثة الصوتية، ويحفظ النتائج التي تختار الاحتفاظ بها على جهازك.",
                "Basir describes images, reads documents, translates text, supports questions and voice conversation, and saves the results you choose to keep on your device."
            ))
            .font(.body)
            .basirCardSurface()

            BasirStatusBanner(
                text: L10n.t(
                    "بصير أداة مساعدة، وليس بديلًا عن العصا البيضاء أو المرافق أو المختص أو خدمات الطوارئ. راجع المعلومات المؤثرة قبل استخدامها.",
                    "Basir is an assistive tool, not a replacement for a cane, human guide, qualified professional, or emergency services. Verify consequential information before using it."
                ),
                tone: .warning,
                title: L10n.t("حدود الاستخدام", "Use limitations")
            )

            BasirStatusBanner(
                text: L10n.t(
                    "لا يتطلب التطبيق حسابًا لدى المطور ولا يعرض إعلانات. عند تشغيل ميزة ذكاء اصطناعي، يُرسل المحتوى الذي اخترته إلى Gemini أو إلى الخادم الوسيط الذي أعددته.",
                    "The app does not require a developer account and shows no ads. When you run an AI feature, the content you chose is sent to Gemini or the proxy server you configured."
                ),
                tone: .info,
                title: L10n.t("الخصوصية باختصار", "Privacy at a glance")
            )

            BasirSectionHeader(title: L10n.t("معلومات الإصدار", "Version information"))
            BasirInfoRow(label: L10n.t("الإصدار", "Version"), value: appVersion, systemImage: "number")
            BasirInfoRow(label: L10n.t("رقم البناء", "Build"), value: buildNumber, systemImage: "hammer.fill")
            BasirInfoRow(label: L10n.t("المطور", "Developer"), value: L10n.t("عبدالله الراشدي", "Abdullah Al-Rashidi"), systemImage: "person.fill")
            BasirInfoRow(label: L10n.t("البريد", "Email"), value: contactEmail, systemImage: "envelope.fill")

            Button {
                if let url = URL(string: "mailto:\(contactEmail)?subject=Basir%20feedback") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label(L10n.t("إرسال ملاحظة للمطور", "Send feedback to the developer"),
                      systemImage: "envelope.fill")
            }
            .buttonStyle(BasirPrimaryButtonStyle())
            .accessibilityHint(L10n.t("يفتح تطبيق البريد برسالة جديدة.",
                                      "Opens the email app with a new message."))
        }
        .navigationTitle(L10n.t("عن بصير", "About Basir"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
