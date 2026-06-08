// DescribeHubView.swift
// Mirrors Android showDescribeScreen(): the "Describe an image or scene"
// hub that lists the image-reading modes plus a written-scene tool.

import SwiftUI

struct DescribeHubView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.t(
                    "اختر ما تريد فهمه، ثم التقط صورة أو اخترها من مكتبة الصور.",
                    "Choose what you want to understand, then take a photo or select one from your library."
                ))
                .font(.callout)
                .foregroundStyle(.secondary)

                NavigationLink {
                    DescribeImageView(mode: .detailed)
                } label: {
                    BasirCard(
                        icon: "📝",
                        title: L10n.t("وصف الصورة بالتفصيل", "Describe an image in detail"),
                        description: L10n.t(
                            "يبدأ بخلاصة واضحة، ثم يذكر الأشخاص والأشياء ومواقعها والنصوص الظاهرة والتفاصيل المفيدة.",
                            "Starts with a clear summary, then covers people, objects, positions, visible text, and useful details."
                        )
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    DescribeImageView(mode: .altText)
                } label: {
                    BasirCard(
                        icon: "🖼",
                        title: L10n.t("إنشاء وصف بديل", "Create alt text"),
                        description: L10n.t(
                            "ينشئ وصفًا موجزًا ودقيقًا مناسبًا للنشر وقارئات الشاشة، بلا حشو أو افتراضات.",
                            "Creates concise, accurate alt text for publishing and screen readers, without filler or assumptions."
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
                            "يقرأ النصوص والأزرار والتنبيهات الظاهرة، ثم يشرح الخطوة التالية بناءً على الشاشة نفسها.",
                            "Reads visible text, buttons, and alerts, then explains the next step based only on the screenshot."
                        )
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    DescribeImageView(mode: .currencyOrReceipt)
                } label: {
                    BasirCard(
                        icon: "💵",
                        title: L10n.t("قراءة عملة أو فاتورة", "Read currency or a receipt"),
                        description: L10n.t(
                            "يتعرّف على فئة الورقة النقدية أو إجمالي الفاتورة من صورة واضحة. تحقّق من المبلغ قبل الدفع أو التسليم.",
                            "Identifies a banknote denomination or receipt total from a clear photo. Verify the amount before paying or handing it over."
                        )
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    MathExtractView()
                } label: {
                    BasirCard(
                        icon: "🧮",
                        title: L10n.t("قراءة معادلات من صورة", "Read equations from an image"),
                        description: L10n.t(
                            "يلتقط المعادلات من ورقة أو سبورة أو كتاب، ويعرضها بصيغة منطوقة مع LaTeX للمراجعة.",
                            "Extracts equations from a page, whiteboard, or textbook and presents spoken math with LaTeX for review."
                        )
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    TextTaskView(
                        title: L10n.t("إرشادات مكانية من وصفك", "Guidance from your description"),
                        hint: L10n.t(
                            "اكتب ما تعرفه عن المكان، وسيُلخّص بصير العوائق والاتجاهات ويقترح خطوة عملية دون اختراع تفاصيل.",
                            "Describe what you know about the place. Basir summarizes obstacles and directions and suggests one practical step without inventing details."
                        ),
                        instruction: "From the user's written description of a place, summarize obstacles, directions, and a single practical next step. This is not live scene recognition; do not invent details that were not described."
                    )
                } label: {
                    BasirCard(
                        icon: "🧭",
                        title: L10n.t("تحويل وصف المكان إلى إرشادات",
                                      "Turn place details into guidance"),
                        description: L10n.t(
                            "اكتب تفاصيل المكان لتحصل على تلخيص واضح للعوائق والاتجاهات والخطوة التالية.",
                            "Enter place details to receive a clear summary of obstacles, directions, and the next step."
                        )
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .navigationTitle(L10n.t("فهم صورة أو مشهد", "Understand an image or scene"))
    }
}
