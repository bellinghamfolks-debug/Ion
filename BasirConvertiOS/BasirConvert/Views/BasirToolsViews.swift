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
                           detail: l10n.t("على الهاتف دون إنترنت", "On the phone, no internet"),
                           systemImage: "bolt.horizontal.circle.fill") { tool = .instantRead }
                SourceTile(title: l10n.t("اسأل عن صورة", "Ask about a picture"),
                           detail: l10n.t("صوّر شيئًا واسأل عنه", "Photograph something and ask"),
                           systemImage: "eye.circle.fill") { tool = .imageQuestion }
                SourceTile(title: l10n.t("قارن نسختين", "Compare versions"),
                           detail: l10n.t("ما الذي تغيّر بين ملفين", "What changed between two files"),
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

    struct ReaderSession: Identifiable {
        let id = UUID()
        let title: String
        let blocks: [ReaderBlock]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BasirSpacing.l) {
                    Text(l10n.t("يقرأ بصير الصفحة على هاتفك فورًا ودون إنترنت، ثم يفتحها في القارئ. للدقة الكاملة في الجداول والعربية المعقدة استخدم التحويل.",
                                "Basir reads the page on your phone at once, with no internet, and opens it in the reader. For full accuracy with tables and complex Arabic, use conversion."))
                        .fixedSize(horizontal: false, vertical: true)
                    if !InstantReader.supportsArabic {
                        InlineMessage(text: l10n.t("القراءة على الهاتف لا تدعم العربية في هذا الإصدار من iOS؛ يقرأ النص الإنجليزي فقط. نص PDF المكتوب يُقرأ بأي لغة.",
                                                   "On-phone reading does not support Arabic on this iOS version; it reads English text only. Typed PDF text is read in any language."),
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
                        ProgressView(l10n.t("جارٍ القراءة على الهاتف…", "Reading on the phone…"))
                            .frame(maxWidth: .infinity)
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
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                try? InstantReader.read(urls, isArabic: arabic)
            }.value
            working = false
            guard let outcome, !outcome.blocks.isEmpty else {
                message = l10n.t("لم يجد بصير نصًا يمكن قراءته على الهاتف. جرّب التحويل.",
                                 "Basir found no text it could read on the phone. Try conversion.")
                UIAccessibility.post(notification: .announcement, argument: message ?? "")
                return
            }
            if outcome.pagesSkipped > 0 {
                message = l10n.t("قُرئت أول \(InstantReader.maximumPages) صفحة فقط. للملف كاملًا استخدم التحويل.",
                                 "Only the first \(InstantReader.maximumPages) pages were read. Use conversion for the whole file.")
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
                            .accessibilityLabel(l10n.t("الصورة المختارة", "The chosen picture"))
                        TextField(l10n.t("سؤالك عن الصورة (اختياري)", "Your question (optional)"), text: $question, axis: .vertical)
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
                        Text(l10n.t("صوّر علبة دواء أو فاتورة أو لافتة أو أي شيء، ثم اسأل عنه. تُرسل الصورة إلى خادم بصير لهذا السؤال فقط ولا تُحفظ.",
                                    "Photograph a medicine box, a bill, a sign or anything, then ask about it. The picture is sent to the Basir server for this question only and not kept."))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    AdaptiveStack {
                        CardActionButton(title: l10n.t("كاميرا", "Camera"), systemImage: "camera.fill", prominent: image == nil) {
                            showCamera = true
                        }
                        CardActionButton(title: l10n.t("الصور", "Photos"), systemImage: "photo") { showPhotos = true }
                    }
                    if working {
                        ProgressView(l10n.t("بصير ينظر إلى الصورة…", "Basir is looking at the picture…")).frame(maxWidth: .infinity)
                    }
                    if let errorText { InlineMessage(text: errorText, isError: true) }
                    ForEach(Array(answers.enumerated().reversed()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: BasirSpacing.s) {
                            Text(item.question).font(.subheadline.weight(.semibold)).foregroundStyle(BasirPalette.secondaryText)
                            Text(item.answer.answer).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            if !item.answer.visibleText.isEmpty {
                                Text(l10n.t("النص في الصورة: ", "Text in the picture: ") + item.answer.visibleText)
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
                    Text(l10n.t("اختر نسختين من ملفاتك المحوّلة. يقارن بصير النص فقرة فقرة على هاتفك، ويمكنه بعد ذلك تلخيص الفروق المهمة.",
                                "Choose two versions from your converted files. Basir compares them paragraph by paragraph on your phone, then can summarize what matters."))
                        .fixedSize(horizontal: false, vertical: true)
                    picker(l10n.t("النسخة القديمة", "Old version"), selection: $oldItem)
                    picker(l10n.t("النسخة الجديدة", "New version"), selection: $newItem)
                    PrimaryActionButton(title: l10n.t("قارن", "Compare"), systemImage: "arrow.left.arrow.right") { compare() }
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
        .accessibilityValue(selection.wrappedValue?.displayName ?? l10n.t("لم يُختر", "Not chosen"))
    }

    @ViewBuilder
    private func results(_ changes: [TextComparison.Change]) -> some View {
        SectionHeading(title: changes.isEmpty ? l10n.t("لا فروق في النص", "No differences in the text")
                                              : l10n.t("\(changes.count) فروق", "\(changes.count) differences"))
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
                SecondaryActionButton(title: l10n.t("لخّص الفروق المهمة", "Summarize what matters"), systemImage: "sparkles") {
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
                Text((change.kind == .changed ? l10n.t("كان: ", "Was: ") : "") + change.before)
                    .strikethrough(change.kind == .removed)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !change.after.isEmpty {
                Text((change.kind == .changed ? l10n.t("أصبح: ", "Now: ") : "") + change.after)
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
                : l10n.t("وجد بصير \(result.count) فروق.", "Basir found \(result.count) differences."))
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
