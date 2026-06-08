// AdvancedToolsView.swift
// Mirrors Android showAdvancedScreen(): Gemini-powered TEXT tools for
// study, writing, and organizing information (study cards, polite reply,
// table-as-text). Each opens the generic TextTaskView.

import SwiftUI

struct AdvancedToolsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.t(
                    "أدوات للكتابة والدراسة وتنظيم النصوص. راجع النتيجة قبل نسخها أو مشاركتها.",
                    "Tools for writing, studying, and organizing text. Review the result before copying or sharing it."
                ))
                .font(.callout)
                .foregroundStyle(.secondary)

                NavigationLink {
                    TextTaskView(
                        title: L10n.t("بطاقات مراجعة", "Study cards"),
                        hint: L10n.t("ألصق النص الذي تريد مراجعته.", "Paste the text you want to study."),
                        instruction: "Turn the text into direct Q&A study cards suitable for audio review."
                    )
                } label: {
                    BasirCard(
                        icon: "🗂",
                        title: L10n.t("إنشاء بطاقات مراجعة", "Create study cards"),
                        description: L10n.t(
                            "يحوّل النص إلى أسئلة وأجوبة مباشرة وسهلة للمراجعة الصوتية.",
                            "Turns text into direct questions and answers that are easy to review aloud."
                        )
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    TextTaskView(
                        title: L10n.t("مساعدة في الرد", "Reply assistant"),
                        hint: L10n.t("ألصق الرسالة التي تريد الرد عليها.", "Paste the message you want to reply to."),
                        instruction: "Explain the message tone and suggest a polite reply. Give Arabic and English versions."
                    )
                } label: {
                    BasirCard(
                        icon: "✍️",
                        title: L10n.t("اقتراح رد مناسب", "Suggest a reply"),
                        description: L10n.t(
                            "يفهم نبرة الرسالة ويقترح ردًا مناسبًا بالعربية والإنجليزية.",
                            "Understands the message tone and suggests a suitable reply in Arabic and English."
                        )
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    TextTaskView(
                        title: L10n.t("تحويل جدول إلى نص", "Turn a table into text"),
                        hint: L10n.t("ألصق بيانات الجدول هنا.", "Paste the table data here."),
                        instruction: "Convert the table-like text into clear plain-text rows with labels for each value."
                    )
                } label: {
                    BasirCard(
                        icon: "🧾",
                        title: L10n.t("تبسيط جدول لقارئ الشاشة", "Make a table screen-reader friendly"),
                        description: L10n.t(
                            "يرتب كل صف مع عناوينه ليصبح الجدول واضحًا عند الاستماع إليه.",
                            "Pairs each row with its headers so the table is clear when read aloud."
                        )
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .navigationTitle(L10n.t("أدوات الكتابة والدراسة", "Writing and study tools"))
    }
}
