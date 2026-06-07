// AdvancedToolsView.swift
// Mirrors Android showAdvancedScreen(): the secondary image-reading and
// extraction tools, grouped out of the main Vision tab.

import SwiftUI

struct AdvancedToolsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.t(
                    "أدوات إضافية لقراءة الصور واستخراج المحتوى. راجع المعلومات المهمة قبل الاعتماد عليها.",
                    "Extra tools for reading images and extracting content. Verify important information before relying on it."
                ))
                .font(.callout)
                .foregroundStyle(.secondary)

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
                    DescribeImageView(mode: .table)
                } label: {
                    BasirCard(
                        icon: "🧾",
                        title: L10n.t("قراءة جدول", "Read a table"),
                        description: L10n.t(
                            "صوّر جدولًا (جدول حصص، نتائج، مواعيد، فاتورة جداول) وستقرأه بصير صفًا بصف بترتيب يسهل سماعه.",
                            "Photograph a table (timetable, results, schedule, line-item invoice) and Basir reads it row by row in a screen-reader-friendly order."
                        )
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    DescribeImageView(mode: .medical)
                } label: {
                    BasirCard(
                        icon: "🩺",
                        title: L10n.t("قراءة نص طبي", "Read medical text"),
                        description: L10n.t(
                            "تقرأ بصير وصفة أو نشرة دواء أو نتيجة تحليل ظاهرة في الصورة. هذه قراءة فقط؛ راجِع طبيبك أو الصيدلي قبل أي قرار.",
                            "Basir reads a prescription, drug leaflet, or lab result visible in the image. This is text reading only — consult your doctor or pharmacist before any decision."
                        )
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    DescribeImageView(mode: .legal)
                } label: {
                    BasirCard(
                        icon: "⚖️",
                        title: L10n.t("قراءة نص قانوني", "Read legal text"),
                        description: L10n.t(
                            "تقرأ بصير عقدًا أو وثيقة قانونية وتشرح بنودها بإيجاز. هذه قراءة عامة وليست رأيًا قانونيًا؛ راجِع محاميًا قبل التوقيع.",
                            "Basir reads a contract or legal document and summarizes its clauses. This is general reading, not legal advice — consult a lawyer before signing."
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
                            "صوّر معادلات أو سبورة أو صفحة كتاب. يحاول بصير استخراج المعادلات بصيغة منطوقة مع LaTeX للمراجعة؛ قارِن الناتج بالصورة قبل اعتماده.",
                            "Photograph equations, a whiteboard, or a textbook page. Basir attempts to extract spoken math with LaTeX for review; compare the result with the image before relying on it."
                        )
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .navigationTitle(L10n.t("أدوات متقدمة", "Advanced tools"))
    }
}
