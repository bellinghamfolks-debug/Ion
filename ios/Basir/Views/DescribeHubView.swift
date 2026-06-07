// DescribeHubView.swift
// Mirrors Android showDescribeScreen(): the "Describe an image or scene"
// hub that lists the image-reading modes plus a written-scene tool.

import SwiftUI

struct DescribeHubView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.t(
                    "اختر صورة من المعرض، أو التقط صورة جديدة، أو اكتب وصفًا للمشهد.",
                    "Choose an image from the gallery, take a new photo, or type a scene description."
                ))
                .font(.callout)
                .foregroundStyle(.secondary)

                NavigationLink {
                    DescribeImageView(mode: .detailed)
                } label: {
                    BasirCard(
                        icon: "📝",
                        title: L10n.t("وصف تفصيلي للصورة", "Detailed image description"),
                        description: L10n.t(
                            "وصف يبدأ بالخلاصة، ثم الأشخاص والأشياء وترتيبها والنص الظاهر والتفاصيل العملية.",
                            "A description that starts with a summary, then covers people, objects, layout, visible text, and practical details."
                        )
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    DescribeImageView(mode: .altText)
                } label: {
                    BasirCard(
                        icon: "🖼",
                        title: L10n.t("إنشاء وصف بديل للصورة", "Generate image alt text"),
                        description: L10n.t(
                            "أنشئ وصفًا بديلًا مركزًا يشرح الغرض والمحتوى المهم دون حشو أو تخمين.",
                            "Create focused alt text that explains the purpose and important content without filler or guesswork."
                        )
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    DescribeImageView(mode: .screenshot)
                } label: {
                    BasirCard(
                        icon: "🖥",
                        title: L10n.t("قراءة لقطة شاشة", "Read a screenshot"),
                        description: L10n.t(
                            "اقرأ النص الظاهر وأسماء الأزرار والرسائل، واشرح الخطوة التالية اعتمادًا على ما يظهر فقط.",
                            "Read visible text, button names, and messages, and explain the next step using only what is shown."
                        )
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    DescribeImageView(mode: .currencyOrReceipt)
                } label: {
                    BasirCard(
                        icon: "💵",
                        title: L10n.t("قراءة العملات والفواتير", "Read currency and receipts"),
                        description: L10n.t(
                            "التقط صورة واضحة للعملة أو الفاتورة لقراءة الفئة أو الإجمالي. تحقّق من الرقم قبل الدفع أو التسليم.",
                            "Take a clear photo of currency or a receipt to read the denomination or total. Verify the amount before paying or handing it over."
                        )
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    MathExtractView()
                } label: {
                    BasirCard(
                        icon: "🧮",
                        title: L10n.t("تحليل ورقة رياضيات", "Analyze a math sheet"),
                        description: L10n.t(
                            "التقط صورة لمعادلات أو سبورة أو صفحة كتاب. يحاول بصير استخراج الصيغ بصيغة منطوقة مع LaTeX للمراجعة؛ قارِن الناتج بالصورة قبل اعتماده.",
                            "Photograph equations, a whiteboard, or a textbook page. Basir attempts to extract spoken math with LaTeX for review; compare the result with the image before relying on it."
                        )
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    TextTaskView(
                        title: L10n.t("وصف المشهد", "Scene description"),
                        hint: L10n.t(
                            "اكتب ما تعرفه عن المكان للحصول على تلخيص للعوائق والاتجاهات والخطوة التالية، دون اعتباره وصفًا حيًا للمشهد.",
                            "Write what you know about the place to get a summary of obstacles, directions, and a next step; this is not live scene recognition."
                        ),
                        instruction: "From the user's written description of a place, summarize obstacles, directions, and a single practical next step. This is not live scene recognition; do not invent details that were not described."
                    )
                } label: {
                    BasirCard(
                        icon: "🧭",
                        title: L10n.t("تحويل وصف مكتوب إلى إرشادات",
                                      "Turn written scene details into guidance"),
                        description: L10n.t(
                            "حوّل وصفك المكتوب للمكان إلى تلخيص للعوائق والاتجاهات والخطوة التالية.",
                            "Turn your written description of a place into a summary of obstacles, directions, and a next step."
                        )
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .navigationTitle(L10n.t("وصف صورة أو مشهد", "Describe an image or scene"))
    }
}
