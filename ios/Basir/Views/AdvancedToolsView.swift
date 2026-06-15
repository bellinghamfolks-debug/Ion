import SwiftUI

struct AdvancedToolsView: View {
    var body: some View {
        BasirScreen {
            BasirPageIntro(
                text: L10n.t(
                    "أدوات مخصصة لتنظيم النصوص للدراسة والكتابة. اختر المهمة، ثم الصق النص أو استورده من ملف.",
                    "Focused tools for studying, writing, and organizing text. Choose a task, then paste text or import it from a file."
                )
            )

            NavigationLink {
                TextTaskView(
                    title: L10n.t("بطاقات مراجعة", "Study cards"),
                    hint: L10n.t(
                        "ألصق المادة، وسيحوّلها بصير إلى أسئلة وأجوبة مباشرة مع الحفاظ على النقاط الأساسية.",
                        "Paste the material and Basir will turn it into direct questions and answers while preserving the key points."
                    ),
                    instruction: GeminiPrompts.studyCardsInstruction,
                    task: .studyCards
                )
            } label: {
                BasirFeatureCard(
                    systemImage: "rectangle.stack.fill",
                    title: L10n.t("إنشاء بطاقات مراجعة", "Create study cards"),
                    description: L10n.t(
                        "حوّل النص الطويل إلى أسئلة وأجوبة مناسبة للمراجعة بقارئ الشاشة.",
                        "Turn long text into questions and answers suited to screen-reader review."
                    )
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                TextTaskView(
                    title: L10n.t("صياغة رد", "Draft a reply"),
                    hint: L10n.t(
                        "ألصق الرسالة وحدد طلبك داخل النص عند الحاجة. سيقترح بصير ردًا واضحًا ومحترمًا من دون اختراع معلومات شخصية.",
                        "Paste the message and include any preference you have. Basir suggests a clear, respectful reply without inventing personal details."
                    ),
                    instruction: GeminiPrompts.replyAssistantInstruction,
                    task: .reply
                )
            } label: {
                BasirFeatureCard(
                    systemImage: "text.cursor",
                    title: L10n.t("اقتراح رد مناسب", "Suggest a suitable reply"),
                    description: L10n.t(
                        "افهم نبرة الرسالة واحصل على مسودة قابلة للتعديل قبل الإرسال.",
                        "Understand the tone and get an editable draft before sending."
                    ),
                    tone: .info
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                TextTaskView(
                    title: L10n.t("تبسيط جدول", "Simplify a table"),
                    hint: L10n.t(
                        "ألصق بيانات الجدول. سيذكر بصير عناوين الأعمدة مع كل صف حتى يصبح الاستماع إليه أوضح.",
                        "Paste the table data. Basir repeats column headers with each row so it is easier to follow by listening."
                    ),
                    instruction: GeminiPrompts.screenReaderTableTextInstruction,
                    task: .linearizeTable
                )
            } label: {
                BasirFeatureCard(
                    systemImage: "tablecells.fill",
                    title: L10n.t("تحويل جدول إلى نص واضح", "Turn a table into clear text"),
                    description: L10n.t(
                        "يرتب كل صف مع عناوينه بدل قراءة الخلايا بلا سياق.",
                        "Pairs every row with its headers instead of reading cells without context."
                    ),
                    tone: .success
                )
            }
            .buttonStyle(.plain)

            BasirStatusBanner(text: BasirCopy.verifyImportantInformation, tone: .warning)
        }
        .navigationTitle(L10n.t("أدوات الكتابة والدراسة", "Writing and study tools"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
