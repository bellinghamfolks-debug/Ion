// MoreView.swift  (More tab)
// Mirrors Android renderMoreTab(): Quick help, Tools, App, Legal, and
// an "App status" button at the bottom.

import SwiftUI

struct MoreView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Hero()

                    // MARK: Quick help
                    SectionHeader(L10n.t("مساعدة سريعة", "Quick help"))

                    NavigationLink {
                        EmergencyView()
                    } label: {
                        BasirCard(
                            icon: "🆘",
                            title: L10n.t("الطوارئ والمساعدة", "Emergency and help"),
                            description: L10n.t(
                                "جهّز رسالة طلب مساعدة لجهة محفوظة، مع موقع تقريبي عند السماح. ستراجع الرسالة وتؤكد إرسالها بنفسك.",
                                "Prepare a help message for a saved contact, with approximate location when permitted. You review and send it yourself."
                            )
                        )
                    }
                    .buttonStyle(.plain)

                    // MARK: Tools
                    SectionHeader(L10n.t("الأدوات", "Tools"))

                    NavigationLink {
                        AdvancedToolsView()
                    } label: {
                        BasirCard(
                            icon: "🛠",
                            title: L10n.t("أدوات متقدمة", "Advanced tools"),
                            description: L10n.t(
                                "أنشئ وصفًا بديلًا، واقرأ لقطات الشاشة والجداول والعملات والنصوص الطبية والقانونية، وحلّل أوراق الرياضيات.",
                                "Create alt text; read screenshots, tables, currency, and medical or legal text; and analyze math sheets."
                            )
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        MemoryView()
                    } label: {
                        BasirCard(
                            icon: "🧠",
                            title: L10n.t("محفوظاتي الخاصة", "My saved items"),
                            description: L10n.t(
                                "نظّم ملاحظات محلية عن الأشخاص والمنتجات والأدوية والأماكن للرجوع إليها لاحقًا.",
                                "Organize local notes about people, products, medications, and places for later reference."
                            )
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        ArchiveView()
                    } label: {
                        BasirCard(
                            icon: "📚",
                            title: L10n.t("المحفوظات", "Archive"),
                            description: L10n.t(
                                "استعرض النتائج التي اخترت حفظها محليًا على هذا الجهاز.",
                                "Review results you chose to save locally on this device."
                            )
                        )
                    }
                    .buttonStyle(.plain)

                    // MARK: App
                    SectionHeader(L10n.t("التطبيق", "App"))

                    NavigationLink {
                        SettingsView()
                    } label: {
                        BasirCard(
                            icon: "⚙️",
                            title: L10n.t("الإعدادات", "Settings"),
                            description: L10n.t(
                                "اللغة، الصوت، المظهر، الخصوصية، وإعداد Gemini.",
                                "Language, voice, appearance, privacy, and Gemini setup."
                            )
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        AboutView()
                    } label: {
                        BasirCard(
                            icon: "ℹ️",
                            title: L10n.t("حول التطبيق", "About"),
                            description: L10n.t(
                                "معلومات عن بصير وطرق التواصل مع المطوّر.",
                                "About Basir and how to contact the developer."
                            )
                        )
                    }
                    .buttonStyle(.plain)

                    // MARK: Legal
                    SectionHeader(L10n.t("سياسات قانونية", "Legal"))

                    NavigationLink {
                        TermsView()
                    } label: {
                        BasirCard(
                            icon: "📜",
                            title: L10n.t("الشروط والأحكام", "Terms and Conditions"),
                            description: L10n.t(
                                "شروط استخدام بصير ومسؤوليات المستخدم.",
                                "Basir terms of use and user responsibilities."
                            )
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        PrivacyView()
                    } label: {
                        BasirCard(
                            icon: "🔒",
                            title: L10n.t("سياسة الخصوصية", "Privacy Policy"),
                            description: L10n.t(
                                "اعرف ما يُحفظ محليًا وما يُرسل إلى Google Gemini.",
                                "Learn what is stored locally and what is sent to Google Gemini."
                            )
                        )
                    }
                    .buttonStyle(.plain)

                    // MARK: App status (outline button, like Android)
                    NavigationLink {
                        AppStatusView()
                    } label: {
                        Text(L10n.t("حالة التطبيق", "App status"))
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.accentColor, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
