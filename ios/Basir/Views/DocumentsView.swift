import SwiftUI

struct DocumentsView: View {
    @ObservedObject private var lastDoc = LastDocumentStore.shared

    var body: some View {
        NavigationStack {
            BasirScreen {
                BasirHero(
                    eyebrow: L10n.t("المستندات", "DOCUMENTS"),
                    title: L10n.t("حوّل الملف إلى محتوى قابل للعمل", "Turn a file into usable content"),
                    subtitle: L10n.t(
                        "افتح PDF أو Word أو PowerPoint، نظّم المحتوى، ترجم عند الحاجة، ثم صدّره إلى Word.",
                        "Open a PDF, Word, or PowerPoint file, organize the content, translate when needed, then export to Word."
                    ),
                    systemImage: "doc.text.magnifyingglass"
                )

                BasirSectionHeader(
                    title: L10n.t("قراءة وتحويل الملفات", "Read and convert files"),
                    subtitle: L10n.t(
                        "تظهر حالة كل مرحلة بوضوح، ولن يُخفى فشل أي صفحة أو جزء.",
                        "Every stage is shown clearly, and failed pages or sections are never hidden."
                    )
                )

                NavigationLink {
                    DocumentConvertView()
                } label: {
                    BasirFeatureCard(
                        systemImage: "doc.badge.gearshape.fill",
                        title: L10n.t("فتح ملف ومعالجته", "Open and process a file"),
                        description: L10n.t(
                            "استخرج النص والبنية والصور، اختر الترجمة أو وصف الرسومات، ثم أنشئ ملف Word قابلًا للمراجعة.",
                            "Extract text, structure, and images; choose translation or figure descriptions; then create a reviewable Word file."
                        ),
                        badge: L10n.t("PDF إلى Word", "PDF to Word")
                    )
                }
                .buttonStyle(.plain)

                if lastDoc.hasDocument {
                    NavigationLink {
                        DocumentQAView()
                    } label: {
                        BasirFeatureCard(
                            systemImage: "questionmark.bubble.fill",
                            title: L10n.t("اسأل عن آخر مستند", "Ask about the latest document"),
                            description: lastDocumentDescription,
                            tone: .info
                        )
                    }
                    .buttonStyle(.plain)
                }

                BasirSectionHeader(
                    title: L10n.t("الترجمة", "Translation"),
                    subtitle: L10n.t(
                        "للعبارات القصيرة أو المستندات التي تحتاج ترجمة مباشرة مع الحفاظ على المعنى.",
                        "For short passages or documents that need a direct, meaning-preserving translation."
                    )
                )

                NavigationLink {
                    TranslateView()
                } label: {
                    BasirFeatureCard(
                        systemImage: "character.book.closed.fill",
                        title: L10n.t("ترجمة نص أو مستند", "Translate text or a document"),
                        description: L10n.t(
                            "اختر اللغتين، ألصق النص أو استورده من ملف، ثم راجع الترجمة وانسخها أو شاركها.",
                            "Choose both languages, paste or import the text, then review, copy, or share the translation."
                        ),
                        tone: .success
                    )
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(L10n.t("المستندات", "Documents"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var lastDocumentDescription: String {
        if let name = lastDoc.sourceName, !name.isEmpty {
            return L10n.t(
                "تابع العمل على «\(name)» من دون إعادة فتح الملف.",
                "Continue working with “\(name)” without opening the file again."
            )
        }
        return L10n.t(
            "اطرح سؤالًا دقيقًا عن المستند الذي عالجته مؤخرًا.",
            "Ask a focused question about the document you processed most recently."
        )
    }
}
