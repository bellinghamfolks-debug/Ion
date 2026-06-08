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
                    SectionHeader(L10n.t("السلامة والمساعدة", "Safety and help"))

                    NavigationLink {
                        EmergencyView()
                    } label: {
                        BasirCard(
                            icon: "🆘",
                            title: L10n.t("طلب مساعدة", "Get help"),
                            description: L10n.t(
                                "أنشئ رسالة لجهة موثوقة، ويمكن إضافة موقعك التقريبي. لن تُرسل الرسالة إلا بعد مراجعتك.",
                                "Create a message for a trusted contact and optionally add your approximate location. Nothing is sent until you review it."
                            )
                        )
                    }
                    .buttonStyle(.plain)

                    // MARK: Tools
                    SectionHeader(L10n.t("أدوات إضافية", "More tools"))

                    NavigationLink {
                        AdvancedToolsView()
                    } label: {
                        BasirCard(
                            icon: "🛠",
                            title: L10n.t("أدوات الكتابة والدراسة", "Writing and study tools"),
                            description: L10n.t(
                                "حوّل النصوص إلى بطاقات مراجعة، واقترح ردودًا مناسبة، واجعل الجداول أسهل للقراءة بقارئ الشاشة.",
                                "Turn text into study cards, draft suitable replies, and make tables easier to read with a screen reader."
                            )
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        MemoryView()
                    } label: {
                        BasirCard(
                            icon: "🧠",
                            title: L10n.t("ملاحظاتي", "My notes"),
                            description: L10n.t(
                                "احفظ ملاحظات عن الأشخاص والمنتجات والأدوية والأماكن على هذا الجهاز فقط.",
                                "Save notes about people, products, medications, and places on this device only."
                            )
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        ArchiveView()
                    } label: {
                        BasirCard(
                            icon: "📚",
                            title: L10n.t("النتائج المحفوظة", "Saved results"),
                            description: L10n.t(
                                "ارجع إلى الأوصاف والترجمات والإجابات التي حفظتها على هذا الجهاز.",
                                "Return to descriptions, translations, and answers you saved on this device."
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
                                "خصّص اللغة والصوت والمظهر والخصوصية وطريقة الاتصال بالذكاء الاصطناعي.",
                                "Customize language, voice, appearance, privacy, and how the app connects to AI."
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
                                "تعرّف على بصير، وإصدار التطبيق، ووسيلة التواصل مع المطوّر.",
                                "Learn about Basir, the app version, and how to contact the developer."
                            )
                        )
                    }
                    .buttonStyle(.plain)

                    // MARK: Legal
                    SectionHeader(L10n.t("الشروط والخصوصية", "Terms and privacy"))

                    NavigationLink {
                        TermsView()
                    } label: {
                        BasirCard(
                            icon: "📜",
                            title: L10n.t("الشروط والأحكام", "Terms and Conditions"),
                            description: L10n.t(
                                "اقرأ ضوابط استخدام بصير وحدود الخدمة ومسؤوليات المستخدم.",
                                "Read the rules for using Basir, service limitations, and user responsibilities."
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
                                "اعرف ما يبقى على جهازك، وما يُرسل عند استخدام ميزات الذكاء الاصطناعي.",
                                "See what stays on your device and what is sent when you use AI features."
                            )
                        )
                    }
                    .buttonStyle(.plain)

                    // MARK: App status (outline button, like Android)
                    NavigationLink {
                        AppStatusView()
                    } label: {
                        Text(L10n.t("حالة التطبيق والاتصال", "App and connection status"))
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
