import SwiftUI

struct VisionView: View {
    var body: some View {
        NavigationStack {
            BasirScreen {
                BasirHero(
                    eyebrow: L10n.t("الرؤية", "VISION"),
                    title: L10n.t("افهم ما حولك", "Understand what is around you"),
                    subtitle: L10n.t(
                        "صِف صورة، افحص ما أمامك بسرعة، أو استمع إلى التغييرات المهمة في المشهد.",
                        "Describe a photo, take a quick look ahead, or hear important changes in the scene."
                    ),
                    systemImage: "eye.fill"
                )

                BasirSectionHeader(
                    title: L10n.t("أدوات الصور والمشهد", "Image and scene tools"),
                    subtitle: L10n.t(
                        "اختر الأداة حسب الموقف، وليس حسب نوع الكاميرا.",
                        "Choose the tool for the situation, not the camera type."
                    )
                )

                NavigationLink {
                    DescribeHubView()
                } label: {
                    BasirFeatureCard(
                        systemImage: "camera.fill",
                        title: L10n.t("وصف صورة بالتفصيل", "Describe an image in detail"),
                        description: L10n.t(
                            "التقط صورة أو اخترها، ثم حدد نوع الوصف: عام، نص بديل، لقطة شاشة، عملة أو مستند متخصص.",
                            "Take or choose a photo, then select a focused description: general, alt text, screenshot, currency, or specialist document."
                        )
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    WalkingModeView()
                } label: {
                    BasirFeatureCard(
                        systemImage: "viewfinder",
                        title: L10n.t("نظرة سريعة أمامك", "Quick look ahead"),
                        description: L10n.t(
                            "التقط صورة واحدة واستمع إلى وصف موجز للعوائق والعناصر البارزة أمامك.",
                            "Capture one image and hear a concise description of notable objects and possible obstacles ahead."
                        ),
                        tone: .info
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    LiveSceneGuidanceView()
                } label: {
                    BasirFeatureCard(
                        systemImage: "dot.radiowaves.left.and.right",
                        title: L10n.t("وصف المشهد بشكل متتابع", "Continuous scene description"),
                        description: L10n.t(
                            "يلتقط صورًا على فترات وينطق التغييرات المهمة، مع زر إيقاف واضح وفوري.",
                            "Captures images at intervals and announces important changes, with a clear immediate stop control."
                        ),
                        tone: .success,
                        badge: L10n.t("مباشر", "Live")
                    )
                }
                .buttonStyle(.plain)

                BasirStatusBanner(
                    text: L10n.t(
                        "هذه الأدوات للمساندة فقط. استخدم العصا البيضاء أو وسيلة التنقل المعتادة، ولا تعتمد على الكاميرا لعبور الشوارع أو تقدير الحواف والدرج.",
                        "These tools are assistive only. Keep using your cane or usual mobility aid, and never rely on the camera to cross roads or judge edges and stairs."
                    ),
                    tone: .warning,
                    title: L10n.t("تنبيه سلامة", "Safety notice")
                )
            }
            .navigationTitle(L10n.t("الرؤية", "Vision"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
