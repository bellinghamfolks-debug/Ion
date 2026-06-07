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
                    "أدوات تعتمد على Gemini للدراسة والكتابة وتنظيم المعلومات. راجع الناتج قبل نسخه أو إرساله.",
                    "Gemini-powered tools for study, writing, and information organization. Review the output before copying or sending it."
                ))
                .font(.callout)
                .foregroundStyle(.secondary)

                NavigationLink {
                    TextTaskView(
                        title: L10n.t("بطاقات مذاكرة", "Study cards"),
                        hint: L10n.t("الصق النص هنا.", "Paste the text here."),
                        instruction: "Turn the text into direct Q&A study cards suitable for audio review."
                    )
                } label: {
                    BasirCard(
                        icon: "🗂",
                        title: L10n.t("إنشاء بطاقات مذاكرة", "Create study cards"),
                        description: L10n.t(
                            "حوّل النص إلى أسئلة وأجوبة منظمة للمراجعة.",
                            "Turn text into organized questions and answers for review."
                        )
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    TextTaskView(
                        title: L10n.t("رد مناسب", "Suggested reply"),
                        hint: L10n.t("الصق الرسالة هنا.", "Paste the message here."),
                        instruction: "Explain the message tone and suggest a polite reply. Give Arabic and English versions."
                    )
                } label: {
                    BasirCard(
                        icon: "✍️",
                        title: L10n.t("صياغة رد مهذب", "Draft a polite reply"),
                        description: L10n.t(
                            "اقترح ردًا مناسبًا للسياق والنبرة بالعربية أو الإنجليزية.",
                            "Suggest a reply that matches the context and tone in Arabic or English."
                        )
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    TextTaskView(
                        title: L10n.t("قراءة جدول", "Table reading"),
                        hint: L10n.t("الصق نص الجدول هنا.", "Paste the table text here."),
                        instruction: "Convert the table-like text into clear plain-text rows with labels for each value."
                    )
                } label: {
                    BasirCard(
                        icon: "🧾",
                        title: L10n.t("قراءة جدول كنص", "Read a table as text"),
                        description: L10n.t(
                            "حوّل الجداول المعقدة إلى نص واضح ومناسب لقارئات الشاشة.",
                            "Convert complex tables into clear, screen-reader-friendly text."
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
