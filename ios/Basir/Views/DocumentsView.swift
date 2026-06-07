// DocumentsView.swift  (Documents tab)
// Mirrors Android renderDocumentsTab(): "Documents and conversion"
// section + a "Language" section with Translate and explain.

import SwiftUI

struct DocumentsView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Hero()

                    SectionHeader(L10n.t("المستندات والتحويل",
                                          "Documents and conversion"))

                    NavigationLink {
                        DocumentConvertView()
                    } label: {
                        BasirCard(
                            icon: "📄",
                            title: L10n.t("قراءة وتحويل المستندات",
                                          "Read and convert documents"),
                            description: L10n.t(
                                "استخرج النص من PDF حتى 500 صفحة، أو من ملف Word (DOCX) أو PowerPoint (PPTX) أو نص، ثم نظّمه أو ترجمه عبر Gemini على دفعات. يمكنك إنشاء ملف Word من النتيجة. اترك التطبيق مفتوحًا أثناء التشغيل.",
                                "Extract text from a PDF of up to 500 pages, a Word (DOCX) file, a PowerPoint (PPTX) file, or a text file, then structure or translate it with Gemini in batches. You can build a Word file from the result. Keep the app open while it runs."
                            )
                        )
                    }
                    .buttonStyle(.plain)

                    SectionHeader(L10n.t("اللغة", "Language"))

                    NavigationLink {
                        TranslateView()
                    } label: {
                        BasirCard(
                            icon: "🌐",
                            title: L10n.t("ترجمة وشرح", "Translate and explain"),
                            description: L10n.t(
                                "ترجم النصوص أو المستندات، مع توضيح المعنى والنبرة والسياق عند طلبك.",
                                "Translate text or documents, with explanations of meaning, tone, and context when requested."
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
