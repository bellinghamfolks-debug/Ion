import SwiftUI

struct DescribeHubView: View {
    var body: some View {
        BasirScreen {
            BasirPageIntro(
                text: L10n.t(
                    "اختر المهمة أولًا، لأن بصير يغيّر طريقة القراءة بحسب الصورة: وصف عام، نص بديل، لقطة شاشة، عملة، معادلات، أو مستند متخصص.",
                    "Choose the task first. Basir changes how it reads the image for general description, alt text, screenshots, currency, equations, or specialist documents."
                )
            )

            BasirSectionHeader(
                title: L10n.t("نوع القراءة", "Reading mode"),
                subtitle: L10n.t(
                    "كل وضع يركز على المعلومات الأكثر فائدة للمهمة.",
                    "Each mode focuses on the details that matter most for that task."
                )
            )

            modeLink(.detailed,
                     image: "photo.fill.on.rectangle.fill",
                     title: L10n.t("وصف شامل للصورة", "Detailed image description"),
                     description: L10n.t(
                        "خلاصة أولًا، ثم الأشخاص والأشياء والمواقع والنص الظاهر والتفاصيل المهمة.",
                        "A summary first, followed by people, objects, positions, visible text, and useful detail."
                     ))

            modeLink(.altText,
                     image: "accessibility",
                     title: L10n.t("كتابة وصف بديل", "Write alt text"),
                     description: L10n.t(
                        "وصف موجز ودقيق مناسب للنشر وقارئات الشاشة، من دون افتراضات أو حشو.",
                        "Concise, accurate alt text for publishing and screen readers, without assumptions or filler."
                     ),
                     tone: .success)

            modeLink(.screenshot,
                     image: "rectangle.on.rectangle.angled",
                     title: L10n.t("فهم لقطة شاشة", "Understand a screenshot"),
                     description: L10n.t(
                        "يقرأ النص والأزرار والتنبيهات، ثم يشرح ما يظهر وما الخطوة الممكنة التالية.",
                        "Reads text, buttons, and alerts, then explains what is visible and the likely next action."
                     ),
                     tone: .info)

            modeLink(.currencyOrReceipt,
                     image: "banknote.fill",
                     title: L10n.t("قراءة عملة أو فاتورة", "Read currency or a receipt"),
                     description: L10n.t(
                        "يتعرف على الفئة أو المبلغ الظاهر في صورة واضحة. النتيجة ليست إثباتًا لأصالة العملة.",
                        "Identifies a visible denomination or amount from a clear image. The result does not verify authenticity."
                     ),
                     tone: .warning)

            NavigationLink { MathExtractView() } label: {
                BasirFeatureCard(
                    systemImage: "function",
                    title: L10n.t("قراءة المعادلات", "Read equations"),
                    description: L10n.t(
                        "يستخرج المعادلات من ورقة أو سبورة ويعرضها بصيغة منطوقة مع LaTeX.",
                        "Extracts equations from a page or whiteboard and presents spoken math with LaTeX."
                    ),
                    tone: .info
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                TextTaskView(
                    title: L10n.t("تنظيم وصف المكان", "Organize place details"),
                    hint: L10n.t(
                        "اكتب ما تعرفه عن المكان، وسيحوّل بصير الوصف إلى عوائق واتجاهات وخطوة عملية واضحة من دون اختراع تفاصيل.",
                        "Describe what you know about the place. Basir organizes it into obstacles, directions, and one clear practical step without inventing details."
                    ),
                    instruction: GeminiPrompts.placeDescriptionInstruction,
                    task: .organizePlaceDescription
                )
            } label: {
                BasirFeatureCard(
                    systemImage: "map.fill",
                    title: L10n.t("تحويل وصف المكان إلى نقاط عملية", "Turn place details into practical steps"),
                    description: L10n.t(
                        "ينظم وصفك المكتوب إلى معلومات مكانية أسهل للاستماع والمراجعة.",
                        "Organizes your written description into spatial information that is easier to hear and review."
                    ),
                    tone: .neutral
                )
            }
            .buttonStyle(.plain)
        }
        .navigationTitle(L10n.t("وصف صورة", "Describe an image"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func modeLink(_ mode: DescribeImageMode,
                          image: String,
                          title: String,
                          description: String,
                          tone: BasirTone = .brand) -> some View {
        NavigationLink { DescribeImageView(mode: mode) } label: {
            BasirFeatureCard(
                systemImage: image,
                title: title,
                description: description,
                tone: tone
            )
        }
        .buttonStyle(.plain)
    }
}
