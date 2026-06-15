import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var settings: BasirSettings

    var body: some View {
        NavigationStack {
            BasirScreen {
                BasirHero(
                    eyebrow: L10n.t("الأدوات والإعدادات", "TOOLS & SETTINGS"),
                    title: L10n.t("كل ما تحتاجه خارج المهام اليومية", "Everything beyond daily tasks"),
                    subtitle: L10n.t(
                        "الوصول إلى المساعدة، الأدوات المتقدمة، المحفوظات، الإعدادات، والخصوصية.",
                        "Access help, advanced tools, saved items, settings, and privacy information."
                    ),
                    systemImage: "square.grid.2x2.fill"
                )

                if !settings.isConfigured {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        BasirStatusBanner(
                            text: L10n.t(
                                "أكمل إعداد الاتصال بالذكاء الاصطناعي لتعمل ميزات التحليل والوصف.",
                                "Finish setting up the AI connection to use analysis and description features."
                            ),
                            tone: .warning,
                            title: L10n.t("الإعداد غير مكتمل", "Setup is incomplete")
                        )
                    }
                    .buttonStyle(.plain)
                }

                BasirSectionHeader(title: L10n.t("السلامة والمساعدة", "Safety and help"))

                NavigationLink { EmergencyView() } label: {
                    BasirFeatureCard(
                        systemImage: "sos.circle.fill",
                        title: L10n.t("إعداد رسالة مساعدة", "Prepare a help message"),
                        description: L10n.t(
                            "أنشئ رسالة لجهة موثوقة وأضف موقعك التقريبي، ثم راجعها بنفسك قبل الإرسال.",
                            "Create a message for a trusted contact, add your approximate location, then review it before sending."
                        ),
                        tone: .danger
                    )
                }
                .buttonStyle(.plain)

                BasirSectionHeader(title: L10n.t("الإنتاجية والحفظ", "Productivity and saved content"))

                NavigationLink { AdvancedToolsView() } label: {
                    BasirFeatureCard(
                        systemImage: "wand.and.stars",
                        title: L10n.t("أدوات الكتابة والدراسة", "Writing and study tools"),
                        description: L10n.t(
                            "أنشئ بطاقات مراجعة، صغ ردًا مناسبًا، أو حوّل جدولًا إلى نص واضح لقارئ الشاشة.",
                            "Create study cards, draft a suitable reply, or turn a table into clear screen-reader text."
                        )
                    )
                }
                .buttonStyle(.plain)

                NavigationLink { MemoryView() } label: {
                    BasirFeatureCard(
                        systemImage: "note.text.badge.plus",
                        title: L10n.t("ملاحظاتي المحلية", "My local notes"),
                        description: L10n.t(
                            "احفظ أسماء وملاحظات عن أشخاص أو منتجات أو أماكن على هذا الجهاز فقط.",
                            "Save names and notes about people, products, or places on this device only."
                        ),
                        tone: .success
                    )
                }
                .buttonStyle(.plain)

                NavigationLink { ArchiveView() } label: {
                    BasirFeatureCard(
                        systemImage: "archivebox.fill",
                        title: L10n.t("النتائج المحفوظة", "Saved results"),
                        description: L10n.t(
                            "ابحث في الأوصاف والترجمات والإجابات التي اخترت الاحتفاظ بها.",
                            "Browse descriptions, translations, and answers you chose to keep."
                        ),
                        tone: .info
                    )
                }
                .buttonStyle(.plain)

                BasirSectionHeader(title: L10n.t("التطبيق والخصوصية", "App and privacy"))

                NavigationLink { SettingsView() } label: {
                    BasirFeatureCard(
                        systemImage: "gearshape.fill",
                        title: L10n.t("الإعدادات", "Settings"),
                        description: L10n.t(
                            "عدّل اللغة والصوت وحجم النص والمظهر والخصوصية وطريقة الاتصال.",
                            "Adjust language, speech, text size, appearance, privacy, and connection settings."
                        )
                    )
                }
                .buttonStyle(.plain)

                NavigationLink { AppStatusView() } label: {
                    BasirFeatureCard(
                        systemImage: "checkmark.shield.fill",
                        title: L10n.t("حالة التطبيق والاتصال", "App and connection status"),
                        description: L10n.t(
                            "تحقق من الإصدار وطريقة الاتصال وما إذا كان التطبيق جاهزًا للعمل.",
                            "Check the version, connection method, and whether the app is ready to work."
                        ),
                        tone: settings.isConfigured ? .success : .warning
                    )
                }
                .buttonStyle(.plain)

                NavigationLink { AboutView() } label: {
                    BasirFeatureCard(
                        systemImage: "info.circle.fill",
                        title: L10n.t("عن بصير", "About Basir"),
                        description: L10n.t(
                            "اقرأ فكرة التطبيق وحدود استخدامه ومعلومات الإصدار والتواصل.",
                            "Read about the app, its limitations, version details, and contact information."
                        ),
                        tone: .info
                    )
                }
                .buttonStyle(.plain)

                NavigationLink { TermsView() } label: {
                    BasirFeatureCard(
                        systemImage: "doc.plaintext.fill",
                        title: L10n.t("الشروط والأحكام", "Terms and Conditions"),
                        description: L10n.t(
                            "ضوابط الاستخدام، حدود الخدمة، ومسؤوليات المستخدم.",
                            "Usage rules, service limitations, and user responsibilities."
                        ),
                        tone: .neutral
                    )
                }
                .buttonStyle(.plain)

                NavigationLink { PrivacyView() } label: {
                    BasirFeatureCard(
                        systemImage: "lock.shield.fill",
                        title: L10n.t("سياسة الخصوصية", "Privacy Policy"),
                        description: L10n.t(
                            "ما يبقى على جهازك، وما يُرسل عند تشغيل ميزات الذكاء الاصطناعي.",
                            "What stays on your device and what is sent when AI features run."
                        ),
                        tone: .success
                    )
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(L10n.t("المزيد", "More"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
