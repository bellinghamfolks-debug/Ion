// DocumentsView.swift  (Documents tab)
// Mirrors Android renderDocumentsTab(): "Documents and conversion"
// section + a "Language" section with Translate and explain.

import SwiftUI

struct DocumentsView: View {
    @ObservedObject private var lastDoc = LastDocumentStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Hero()

                    SectionHeader(L10n.t("قراءة المستندات ومعالجتها",
                                          "Read and process documents"))

                    NavigationLink {
                        DocumentConvertView()
                    } label: {
                        BasirCard(
                            icon: "📄",
                            title: L10n.t("فتح مستند ومعالجته",
                                          "Open and process a document"),
                            description: L10n.t(
                                "افتح PDF أو Word أو PowerPoint أو ملفًا نصيًا، ثم نظّم محتواه أو ترجمه وصدّر النتيجة إلى Word.",
                                "Open a PDF, Word, PowerPoint, or text file, then organize or translate its content and export the result to Word."
                            )
                        )
                    }
                    .buttonStyle(.plain)

                    // Shown only after a document has been converted, like
                    // Android's conditional "Ask about the latest document".
                    if lastDoc.hasDocument {
                        NavigationLink {
                            DocumentQAView()
                        } label: {
                            BasirCard(
                                icon: "❓",
                                title: L10n.t("اسأل عن المستند الأخير",
                                              "Ask about your last document"),
                                description: lastDoc.sourceName.map { name in
                                    L10n.t("المستند: ", "Document: ") + name
                                } ?? L10n.t(
                                    "اطرح سؤالًا عن محتوى المستند الذي عالجته مؤخرًا.",
                                    "Ask a question about the document you processed most recently."
                                )
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    SectionHeader(L10n.t("الترجمة", "Translation"))

                    NavigationLink {
                        TranslateView()
                    } label: {
                        BasirCard(
                            icon: "🌐",
                            title: L10n.t("ترجمة النصوص", "Translate text"),
                            description: L10n.t(
                                "ترجم نصًا أو مستندًا، واطلب شرح المعنى أو النبرة أو المصطلحات عند الحاجة.",
                                "Translate text or a document, and ask for clarification of meaning, tone, or terminology when needed."
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
