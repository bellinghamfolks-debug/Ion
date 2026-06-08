// VisionView.swift  (Vision tab)
// Mirrors Android renderVisionTab(): section "Images and scenes" with
// Describe, Walking mode, and Live scene guidance. The other image
// reading tools live under "Advanced tools" in the More tab, exactly
// like Android.

import SwiftUI

struct VisionView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Hero()

                    SectionHeader(L10n.t("الصور والتنقل", "Images and mobility"))

                    NavigationLink {
                        DescribeHubView()
                    } label: {
                        BasirCard(
                            icon: "📷",
                            title: L10n.t("وصف صورة", "Describe an image"),
                            description: L10n.t(
                                "التقط صورة أو اخترها من مكتبة الصور، وسيصف بصير محتواها ويقرأ النص الظاهر فيها عند الإمكان.",
                                "Take a photo or choose one from your library. Basir describes it and reads visible text when possible."
                            )
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        WalkingModeView()
                    } label: {
                        BasirCard(
                            icon: "🚶",
                            title: L10n.t("وصف سريع لما أمامك", "Quick look ahead"),
                            description: L10n.t(
                                "التقط صورة واحدة لما أمامك واستمع إلى وصف موجز. استخدم دائمًا وسيلة التنقل المعتادة.",
                                "Capture one image of what is ahead and hear a brief description. Always use your usual mobility aid."
                            )
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        LiveSceneGuidanceView()
                    } label: {
                        BasirCard(
                            icon: "🟢",
                            title: L10n.t("الوصف المباشر",
                                          "Live scene description"),
                            description: L10n.t(
                                "يلتقط صورًا متتابعة وينطق التغييرات المهمة. هذه أداة مساعدة وليست بديلًا عن العصا أو وسيلة التنقل.",
                                "Captures a sequence of images and announces important changes. This is an aid, not a replacement for a cane or mobility tool."
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
