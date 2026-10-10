import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The three tools on the New tab beside conversion: instant offline read,
/// asking about a picture, and comparing two versions of a document.
enum BasirTool: String, Identifiable {
    case instantRead, imageQuestion, compare
    var id: String { rawValue }
}

struct BasirToolsSection: View {
    @EnvironmentObject private var l10n: L10n
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var tool: BasirTool?

    var body: some View {
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: BasirSpacing.m), GridItem(.flexible(), spacing: BasirSpacing.m)]
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            SectionHeading(title: l10n.t("أدوات سريعة", "Quick tools"))
            LazyVGrid(columns: columns, spacing: BasirSpacing.m) {
                SourceTile(title: l10n.t("قراءة فورية", "Instant read"),
                           detail: l10n.t("اقرأ النص دون اتصال بالإنترنت", "Read text without an internet connection"),
                           systemImage: "bolt.horizontal.circle.fill") { tool = .instantRead }
                SourceTile(title: l10n.t("اسأل عن صورة", "Ask about a picture"),
                           detail: l10n.t("أضف صورة واكتب سؤالك", "Add a photo and ask a question"),
                           systemImage: "eye.circle.fill") { tool = .imageQuestion }
                SourceTile(title: l10n.t("قارن نسختين", "Compare versions"),
                           detail: l10n.t("اكتشف التغييرات بين ملفين", "Find changes between two files"),
                           systemImage: "arrow.left.arrow.right.circle.fill") { tool = .compare }
            }
        }
        .fullScreenCover(item: $tool) { tool in
            switch tool {
            case .instantRead: InstantReadView()
            case .imageQuestion: ImageQuestionView()
            case .compare: CompareVersionsView()
            }
        }
    }
}

// MARK: - Instant read

struct InstantReadView: View {
    @EnvironmentObject private var l10n: L10n
    @Environment(\.dismiss) private var dismiss
    @State private var showCapture = false
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var working = false
    @State private var message: String?
    @State private var result: ReaderSession?
    @State private var pageProgress: (done: Int, total: Int)?

    struct ReaderSession: Identifiable {
        let id = UUID()
        let title: String
        let blocks: [ReaderBlock]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BasirSpacing.l) {
                    Text(l10n.t("استخرج النص على جهازك وافتحه في القارئ دون اتصال بالإنترنت. للمستندات التي تتضمن جداول أو نصوصًا عربية معقدة، جرّب «تحويل إلى Word» للحصول على نتيجة أكثر تفصيلًا.",
                                "Extract text on your device and open it in the reader without an internet connection. For tables or complex Arabic text, try Convert to Word for a more detailed result."))
                        .fixedSize(horizontal: false, vertical: true)
                    if !InstantReader.supportsArabic {
                        InlineMessage(text: l10n.t("التعرف على النص داخل الصور متاح بالإنجليزية فقط في إصدار iOS الحالي على جهازك. أما ملفات PDF التي تحتوي على نص قابل للتحديد، فيمكن استخراج نصها بلغته الأصلية.",
                                                   "Text recognition in images is available only in English on your current iOS version. Selectable text in PDFs can still be extracted in its original language."),
                                      isError: false)
                    }
                    PrimaryActionButton(title: l10n.t("تصوير موجَّه", "Guided capture"), systemImage: "viewfinder") {
                        showCapture = true
                    }
                    SecondaryActionButton(title: l10n.t("صورة من المكتبة", "Photo from library"), systemImage: "photo") {
                        showPhotos = true
                    }
                    SecondaryActionButton(title: l10n.t("ملف PDF أو صورة", "PDF or image file"), systemImage: "folder") {
                        showFiles = true
                    }
                    if working {
                        if let pageProgress, pageProgress.total > 1 {
                            ProgressView(value: Double(pageProgress.done), total: Double(pageProgress.total)) {
                                Text(l10n.t("الصفحات المقروءة: \(pageProgress.done) من \(pageProgress.total)",
                                            "Pages read: \(pageProgress.done) of \(pageProgress.total)"))
                            }
                            .accessibilityElement(children: .combine)
                        } else {
                            ProgressView(l10n.t("جارٍ استخراج النص على جهازك…", "Extracting text on your device…"))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    if let message { InlineMessage(text: message, isError: true) }
                }
                .appScreenContent()
            }
            .background(BasirPalette.background.ignoresSafeArea())
            .foregroundStyle(BasirPalette.primaryText)
            .navigationTitle(l10n.t("قراءة فورية", "Instant read"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(l10n.t("إغلاق", "Close")) { dismiss() } }
            }
        }
        .escapeToDismiss { dismiss() }
        .fullScreenCover(isPresented: $showCapture) {
            GuidedCaptureView { pages in
                showCapture = false
                read(pages)
            } onCancel: { showCapture = false }
        }
        .fullScreenCover(isPresented: $showPhotos) {
            PhotoLibraryPicker { urls in
                showPhotos = false
                read(urls)
            } onError: { error in
                showPhotos = false
                message = error.localizedDescription
            } onCancel: { showPhotos = false }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showFiles) {
            BasirDocumentPicker(contentTypes: [.pdf, .image], allowsMultipleSelection: false) { urls in
                showFiles = false
                read(urls)
            } onCancel: { showFiles = false }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $result) { session in
            DocumentReaderView(title: session.title, blocks: session.blocks)
        }
    }

    private func read(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        working = true
        message = nil
        let arabic = l10n.isArabic
        let title = urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : l10n.t("قراءة فورية", "Instant read")
        pageProgress = nil
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                try? await InstantReader.read(urls, isArabic: arabic) { done, total in
                    Task { @MainActor in
                        pageProgress = (done, total)
                        // A spoken note every few pages, not on each one.
                        if total > 3, done < total, done % 3 == 0 {
                            UIAccessibility.post(notification: .announcement,
                                                 argument: l10n.t("الصفحات المقروءة: \(done) من \(total)", "Pages read: \(done) of \(total)"))
                        }
                    }
                }
            }.value
            working = false
            pageProgress = nil
            guard let outcome, !outcome.blocks.isEmpty else {
                message = l10n.t("تعذر استخراج نص قابل للقراءة على جهازك. جرّب «تحويل إلى Word».",
                                 "No readable text could be extracted on your device. Try Convert to Word.")
                UIAccessibility.post(notification: .announcement, argument: message ?? "")
                return
            }
            if outcome.pagesSkipped > 0 {
                message = l10n.t("تقتصر القراءة الفورية على أول \(InstantReader.maximumPages) صفحة. لمعالجة الملف كاملًا، استخدم «تحويل إلى Word».",
                                 "Instant read is limited to the first \(InstantReader.maximumPages) pages. Use Convert to Word to process the whole file.")
            }
            result = ReaderSession(title: title, blocks: outcome.blocks)
        }
    }
}

// MARK: - Ask about a picture

struct ImageQuestionView: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var imageData: Data?
    @State private var question = ""
    @State private var answers: [(question: String, answer: ImageAnswer)] = []
    @State private var showCamera = false
    @State private var showPhotos = false
    @State private var working = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BasirSpacing.l) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityLabel(l10n.t("الصورة المرفقة بالسؤال", "Photo attached to your question"))
                        TextField(l10n.t("اكتب سؤالك عن الصورة (اختياري)", "Ask a question about the photo (optional)"), text: $question, axis: .vertical)
                            .lineLimit(1...3)
                            .padding(12)
                            .background(BasirPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        PrimaryActionButton(title: question.isEmpty ? l10n.t("ما الذي في الصورة؟", "What is in the picture?")
                                                                    : l10n.t("اسأل", "Ask"),
                                            systemImage: "eye") { ask() }
                            .disabled(working)
                        AdaptiveStack {
                            ForEach(quickQuestions, id: \.self) { quick in
                                CardActionButton(title: quick, systemImage: "text.bubble") { question = quick; ask() }
                                    .disabled(working)
                            }
                        }
                    } else {
                        Text(l10n.t("التقط صورة أو اخترها من مكتبتك، ثم اسأل عن محتواها أو النص المكتوب فيها. تُرسل الصورة إلى خادم بصير للإجابة عن سؤالك، ولا تُحفظ على الخادم.",
                                    "Take a photo or choose one from your library, then ask about its content or text. The photo is sent to Basir’s server to answer your question and is not stored there."))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    AdaptiveStack {
                        CardActionButton(title: l10n.t("كاميرا", "Camera"), systemImage: "camera.fill", prominent: image == nil) {
                            showCamera = true
                        }
                        CardActionButton(title: l10n.t("الصور", "Photos"), systemImage: "photo") { showPhotos = true }
                    }
                    if working {
                        ProgressView(l10n.t("جارٍ تحليل الصورة…", "Analyzing the photo…")).frame(maxWidth: .infinity)
                    }
                    if let errorText { InlineMessage(text: errorText, isError: true) }
                    ForEach(Array(answers.enumerated().reversed()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: BasirSpacing.s) {
                            Text(item.question).font(.subheadline.weight(.semibold)).foregroundStyle(BasirPalette.secondaryText)
                            Text(item.answer.answer).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            if !item.answer.visibleText.isEmpty {
                                Text(l10n.t("النص الظاهر في الصورة: ", "Visible text: ") + item.answer.visibleText)
                                    .font(.footnote)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                        }
                        .glassSurface()
                    }
                }
                .appScreenContent()
            }
            .background(BasirPalette.background.ignoresSafeArea())
            .foregroundStyle(BasirPalette.primaryText)
            .navigationTitle(l10n.t("اسأل عن صورة", "Ask about a picture"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(l10n.t("إغلاق", "Close")) { dismiss() } }
            }
        }
        .escapeToDismiss { dismiss() }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { url in
                showCamera = false
                load(url)
            } onError: { error in
                showCamera = false
                errorText = error.localizedDescription
            } onCancel: { showCamera = false }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showPhotos) {
            PhotoLibraryPicker { urls in
                showPhotos = false
                if let first = urls.first { load(first) }
            } onError: { error in
                showPhotos = false
                errorText = error.localizedDescription
            } onCancel: { showPhotos = false }
            .ignoresSafeArea()
        }
    }

    private var quickQuestions: [String] {
        [l10n.t("اقرأ النص المكتوب", "Read the text"),
         l10n.t("ما تاريخ الانتهاء؟", "What is the expiry date?")]
    }

    private func load(_ url: URL) {
        guard let picked = UIImage(contentsOfFile: url.path) else { return }
        // Large enough to read small print, small enough to send quickly.
        let longest = max(picked.size.width, picked.size.height)
        let scale = min(1, 2_000 / max(longest, 1))
        let size = CGSize(width: picked.size.width * scale, height: picked.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in picked.draw(in: CGRect(origin: .zero, size: size)) }
        image = resized
        imageData = resized.jpegData(compressionQuality: 0.85)
        answers = []
        question = ""
        ask()
    }

    private func ask() {
        guard let imageData, !working else { return }
        let asked = question.trimmingCharacters(in: .whitespacesAndNewlines)
        working = true
        errorText = nil
        Task {
            defer { working = false }
            do {
                var body = AssistRequestBody(task: .image, language: l10n.isArabic ? "ar" : "en", question: asked)
                body.imageBase64 = imageData.base64EncodedString()
                body.imageMime = "image/jpeg"
                let answer = try await DocumentAssistant.send(body, as: ImageAnswer.self, configuration: settings.configuration)
                answers.append((asked.isEmpty ? l10n.t("ما الذي في الصورة؟", "What is in the picture?") : asked, answer))
                question = ""
                UIAccessibility.post(notification: .announcement, argument: answer.answer)
            } catch {
                errorText = DocumentAssistant.message(for: error, l10n: l10n)
                UIAccessibility.post(notification: .announcement, argument: errorText ?? "")
            }
        }
    }
}

// MARK: - Compare two versions

struct CompareVersionsView: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var library: OutputLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var oldItem: OutputRecord?
    @State private var newItem: OutputRecord?
    @State private var changes: [TextComparison.Change]?
    @State private var summary: DocumentComparison?
    @State private var oldText = ""
    @State private var newText = ""
    @State private var working = false
    @State private var errorText: String?

    private var readable: [OutputRecord] { library.items.filter(\.isReadable) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BasirSpacing.l) {
                    Text(l10n.t("اختر نسختين من ملفاتك المحوّلة لمقارنة النص على جهازك. بعد عرض التغييرات، يمكنك طلب ملخص لأبرز الفروق.",
                                "Choose two converted files to compare their text on your device. After reviewing the changes, you can request a summary of the main differences."))
                        .fixedSize(horizontal: false, vertical: true)
                    picker(l10n.t("النسخة السابقة", "Earlier version"), selection: $oldItem)
                    picker(l10n.t("النسخة الجديدة", "New version"), selection: $newItem)
                    PrimaryActionButton(title: l10n.t("مقارنة النسختين", "Compare versions"), systemImage: "arrow.left.arrow.right") { compare() }
                        .disabled(oldItem == nil || newItem == nil || oldItem == newItem || working)
                    if working { ProgressView().frame(maxWidth: .infinity) }
                    if let errorText { InlineMessage(text: errorText, isError: true) }
                    if let changes { results(changes) }
                }
                .appScreenContent()
            }
            .background(BasirPalette.background.ignoresSafeArea())
            .foregroundStyle(BasirPalette.primaryText)
            .navigationTitle(l10n.t("قارن نسختين", "Compare versions"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(l10n.t("إغلاق", "Close")) { dismiss() } }
            }
        }
        .escapeToDismiss { dismiss() }
        .onAppear { library.refresh() }
    }

    private func picker(_ title: String, selection: Binding<OutputRecord?>) -> some View {
        Menu {
            ForEach(readable) { item in
                Button(item.displayName) { selection.wrappedValue = item; changes = nil; summary = nil }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(BasirPalette.secondaryText)
                Text(selection.wrappedValue?.displayName ?? l10n.t("اختر ملفًا", "Choose a file"))
                    .font(.headline)
                    .foregroundStyle(BasirPalette.primaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .glassSurface(padding: BasirSpacing.m)
        }
        .accessibilityLabel(title)
        .accessibilityValue(selection.wrappedValue?.displayName ?? l10n.t("لم يُحدد ملف", "No file selected"))
    }

    @ViewBuilder
    private func results(_ changes: [TextComparison.Change]) -> some View {
        SectionHeading(title: changes.isEmpty ? l10n.t("النص متطابق في النسختين", "The text is identical")
                                              : l10n.t("الفروق: \(changes.count)", "Differences: \(changes.count)"))
        if !changes.isEmpty {
            if let summary {
                VStack(alignment: .leading, spacing: BasirSpacing.s) {
                    Text(l10n.t("الملخص", "Summary")).font(.headline).accessibilityAddTraits(.isHeader)
                    Text(summary.summary).fixedSize(horizontal: false, vertical: true)
                    ForEach(summary.changes.filter(\.important)) { change in
                        Text("• " + (change.after.isEmpty ? change.before : change.after))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .glassSurface()
            } else {
                SecondaryActionButton(title: l10n.t("تلخيص أبرز الفروق", "Summarize key differences"), systemImage: "sparkles") {
                    summarize()
                }
                .disabled(working)
            }
            ForEach(changes) { change in changeRow(change) }
        }
    }

    private func changeRow(_ change: TextComparison.Change) -> some View {
        let label: String
        switch change.kind {
        case .added: label = l10n.t("أُضيف", "Added")
        case .removed: label = l10n.t("حُذف", "Removed")
        case .changed: label = l10n.t("تغيّر", "Changed")
        }
        return VStack(alignment: .leading, spacing: BasirSpacing.xs) {
            Text(label).font(.subheadline.weight(.bold))
                .foregroundStyle(change.kind == .removed ? BasirPalette.danger : BasirPalette.accent)
            if !change.before.isEmpty {
                Text((change.kind == .changed ? l10n.t("قبل التعديل: ", "Before: ") : "") + change.before)
                    .strikethrough(change.kind == .removed)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !change.after.isEmpty {
                Text((change.kind == .changed ? l10n.t("بعد التعديل: ", "After: ") : "") + change.after)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(padding: BasirSpacing.m)
        .accessibilityElement(children: .combine)
    }

    private func compare() {
        guard let oldItem, let newItem else { return }
        working = true
        errorText = nil
        summary = nil
        Task {
            let parsed = await Task.detached(priority: .userInitiated) { () -> ([ReaderBlock], [ReaderBlock])? in
                guard let old = try? DocxExtractor.parse(url: oldItem.url),
                      let new = try? DocxExtractor.parse(url: newItem.url) else { return nil }
                return (ReaderContent.blocks(from: old), ReaderContent.blocks(from: new))
            }.value
            working = false
            guard let parsed else {
                errorText = l10n.t("تعذر فتح أحد الملفين.", "One of the files could not be opened.")
                return
            }
            let result = TextComparison.compare(old: TextComparison.paragraphs(of: parsed.0),
                                                new: TextComparison.paragraphs(of: parsed.1))
            oldText = DocumentAssistant.text(of: parsed.0)
            newText = DocumentAssistant.text(of: parsed.1)
            changes = result
            UIAccessibility.post(notification: .announcement, argument: result.isEmpty
                ? l10n.t("النسختان متطابقتان في النص.", "The two versions have the same text.")
                : l10n.t("اكتملت المقارنة. الفروق: \(result.count).", "Comparison complete. Differences found: \(result.count)."))
        }
    }

    private func summarize() {
        working = true
        errorText = nil
        Task {
            defer { working = false }
            do {
                let result = try await DocumentAssistant.send(
                    AssistRequestBody(task: .compare, language: l10n.isArabic ? "ar" : "en", text: newText, otherText: oldText),
                    as: DocumentComparison.self, configuration: settings.configuration)
                summary = result
                UIAccessibility.post(notification: .announcement, argument: result.summary)
            } catch {
                errorText = DocumentAssistant.message(for: error, l10n: l10n)
            }
        }
    }
}
