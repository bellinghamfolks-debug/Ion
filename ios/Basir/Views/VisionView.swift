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

                    SectionHeader(L10n.t("الصور والمشاهد", "Images and scenes"))

                    NavigationLink {
                        DescribeImageView(mode: .detailed)
                    } label: {
                        BasirCard(
                            icon: "📷",
                            title: L10n.t("وصف صورة أو مشهد", "Describe an image or scene"),
                            description: L10n.t(
                                "التقط صورة أو اخترها من الجهاز للحصول على وصف منظم لما يظهر فيها، مع قراءة النصوص الظاهرة عند الإمكان.",
                                "Take or choose an image to receive a structured description of what is visible, including readable text when possible."
                            )
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        WalkingModeView()
                    } label: {
                        BasirCard(
                            icon: "🚶",
                            title: L10n.t("وضع المشي", "Walking mode"),
                            description: L10n.t(
                                "التقط صورة واحدة لما أمامك واستمع إلى وصف موجز. هذه الميزة مساعدة وليست وسيلة تنقل مستقلة.",
                                "Capture one image of what is ahead and hear a brief description. This is an aid, not an independent mobility tool."
                            )
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        LiveSceneGuidanceView()
                    } label: {
                        BasirCard(
                            icon: "🟢",
                            title: L10n.t("الوصف المباشر أثناء التنقل",
                                          "Live scene guidance"),
                            description: L10n.t(
                                "يحلل بصير صورًا متتابعة للمشهد وينطق التغييرات المهمة. لا تعتمد عليه وحده لعبور الطرق أو تجنب الأخطار.",
                                "Basir analyzes a sequence of scene images and announces important changes. Never rely on it alone to cross roads or avoid hazards."
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
