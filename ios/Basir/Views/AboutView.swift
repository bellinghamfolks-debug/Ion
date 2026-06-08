// AboutView.swift
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.t(
                    "بصير مساعد ذكي صُمّم للمكفوفين وضعاف البصر. يصف الصور، ويقرأ المستندات، ويترجم النصوص، ويدعم المحادثة الصوتية، ويحفظ النتائج التي تختارها.",
                    "Basir is an AI assistant designed for blind and low-vision users. It describes images, reads documents, translates text, supports voice conversation, and saves the results you choose."
                ))

                Text(L10n.t(
                    "للسلامة: بصير أداة مساعدة، ولا يحل محل العصا البيضاء أو الكلب المرشد أو المرافق أو المختص أو خدمات الطوارئ. راجع المعلومات المهمة قبل الاعتماد عليها.",
                    "For safety, Basir is an assistive tool. It does not replace a white cane, guide dog, human guide, qualified professional, or emergency services. Verify important information before relying on it."
                ))
                .foregroundStyle(.secondary)

                Text(L10n.t(
                    "الخصوصية: لا يتطلب بصير حسابًا لدى المطوّر، ولا يعرض إعلانات. عند استخدام ميزة تعتمد على الذكاء الاصطناعي، يُرسل المحتوى الذي اخترته إلى Google Gemini أو إلى الخادم الوسيط الذي أعددته. راجع سياسة الخصوصية للتفاصيل.",
                    "Privacy: Basir does not require a developer account and contains no ads. When you use an AI feature, the content you choose is sent to Google Gemini or to the proxy server you configured. See the Privacy Policy for details."
                ))
                .foregroundStyle(.secondary)

                Group {
                    Text(L10n.t("إصدار التطبيق: ", "App version: ") + appVersion)
                    Text(L10n.t("رقم البناء: ", "Build: ") + buildNumber)
                    Text(L10n.t("المطوّر: عبدالله الراشدي",
                                 "Developer: Abdullah Al-Rashidi"))
                    Text(L10n.t("البريد: ", "Email: ") + contactEmail)
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Button {
                    if let url = URL(string: "mailto:\(contactEmail)?subject=Basir%20feedback") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "envelope.fill")
                        Text(L10n.t("التواصل مع المطوّر", "Contact the developer"))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityHint(L10n.t("يفتح تطبيق البريد برسالة جديدة.",
                                          "Opens the email app with a new message."))
            }
            .padding(20)
        }
        .navigationTitle(L10n.t("حول بصير", "About Basir"))
    }
}
