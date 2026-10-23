import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Natural style: a text written by a person and later over-edited by a
/// machine (a novel after an AI proofread, say) brought back to a natural
/// human voice. The server reads the whole text first, then edits it part
/// by part with the whole in mind, keeping every name, event and paragraph.
struct RestyleView: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runner = RestyleRunner.shared
    @State private var pasted = ""
    @State private var file: PickedFile?
    @State private var title = ""
    @State private var sample = ""
    @State private var notes = ""
    @AppStorage("restyle_strength") private var strength = "full"
    @State private var showFiles = false
    @State private var fileError: String?
    @State private var entries: [RestyleStore.Entry] = []
    @State private var open: RestyleStore.Entry?

    struct PickedFile: Equatable {
        var name: String
        var data: Data
        var words: Int
    }

    private var words: Int { file?.words ?? Self.words(in: pasted) }
    private var hasText: Bool { file != nil || words >= 20 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BasirSpacing.l) {
                    switch runner.phase {
                    case .working(let detail, let done, let total):
                        progress(detail: detail, done: done, total: total)
                    case .failed(let message):
                        InlineMessage(text: message, isError: true)
                        form
                    case .idle, .finished:
                        form
                    }
                    if !entries.isEmpty { library }
                }
                .appScreenContent()
            }
            .background(BasirPalette.background.ignoresSafeArea())
            .foregroundStyle(BasirPalette.primaryText)
            .navigationTitle(l10n.t("أسلوب طبيعي", "Natural style"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(l10n.t("إغلاق", "Close")) { dismiss() } }
            }
            .navigationDestination(isPresented: Binding(get: { open != nil }, set: { if !$0 { open = nil } })) {
                if let open { RestyleResultView(entry: open) }
            }
        }
        .escapeToDismiss { dismiss() }
        .fullScreenCover(isPresented: $showFiles) {
            BasirDocumentPicker(contentTypes: [.basirDOCX, .plainText, UTType(filenameExtension: "md") ?? .plainText],
                                allowsMultipleSelection: false) { urls in
                showFiles = false
                if let url = urls.first { pick(url) }
            } onCancel: { showFiles = false }
            .ignoresSafeArea()
        }
        .onAppear {
            runner.resumeIfNeeded(configuration: settings.configuration, l10n: l10n)
            entries = RestyleStore.entries()
        }
        .onChange(of: runner.phase) { phase in
            if case .finished(let id) = phase {
                entries = RestyleStore.entries()
                open = entries.first { $0.id == id }
            }
        }
    }

    // MARK: The request

    private var form: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.l) {
            Text(l10n.t("لنص كتبه إنسان ثم صار أسلوبه آليًا بعد التدقيق بالذكاء الاصطناعي، كرواية أو مقال. يقرأ بصير النص كاملًا أولًا ليعرف شخصياته وأسماءه وصوت كاتبه، ثم يعيد صياغته جزءًا جزءًا بأسلوب إنساني طبيعي: يزيل العبارات المستهلكة والإيقاع الرتيب، ويضبط علامات الترقيم مثل الإفراط في «؛» و«—»، دون أن يغير حدثًا أو اسمًا أو رقمًا.",
                        "For a text a person wrote that came to sound machine-made after an AI proofread, such as a novel or an article. Basir reads the whole text first to learn its characters, names and the author's voice, then rewrites it part by part in a natural human voice: it removes stock phrases and the even rhythm and fixes punctuation such as overused semicolons and long dashes, without changing any event, name or number."))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: BasirSpacing.s) {
                SectionHeading(title: l10n.t("النص", "The text"))
                PrimaryActionButton(title: l10n.t("اختر ملف Word أو ملفًا نصيًا", "Choose a Word or text file"),
                                    systemImage: "doc.text") { showFiles = true }
                if let file {
                    HStack {
                        Label("\(file.name) · \(l10n.t("\(file.words) كلمة", "\(file.words) words"))", systemImage: "doc.fill")
                            .accessibilityElement(children: .combine)
                        Spacer()
                        Button(l10n.t("إزالة", "Remove")) { self.file = nil }
                    }
                } else {
                    Text(l10n.t("أو الصق النص هنا", "Or paste the text here")).font(.subheadline.weight(.semibold))
                    TextEditor(text: $pasted)
                        .frame(minHeight: 140)
                        .padding(8)
                        .background(BasirPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel(l10n.t("النص", "The text"))
                    if !pasted.isEmpty {
                        Text(l10n.t("\(words) كلمة", "\(words) words")).font(.footnote).foregroundStyle(BasirPalette.secondaryText)
                    }
                }
                if let fileError { InlineMessage(text: fileError, isError: true) }
                TextField(l10n.t("العنوان (اختياري)", "Title (optional)"), text: $title)
                    .padding(12)
                    .background(BasirPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .glassSurface()

            VStack(alignment: .leading, spacing: BasirSpacing.s) {
                SectionHeading(title: l10n.t("مقدار التحرير", "How much to edit"))
                Picker(l10n.t("مقدار التحرير", "How much to edit"), selection: $strength) {
                    Text(l10n.t("كامل", "Full")).tag("full")
                    Text(l10n.t("خفيف", "Light")).tag("light")
                }
                .pickerStyle(.segmented)
                Text(strength == "full"
                     ? l10n.t("يعيد صياغة كل فقرة بأسلوب طبيعي، والمعنى والأحداث كما هي.",
                              "Every paragraph is rewritten in a natural voice; meaning and events stay the same.")
                     : l10n.t("يغيّر فقط الجمل التي تبدو آلية ويصحح ترقيمها، ويبقي الباقي حرفيًا.",
                              "Only sentences that read as machine-made are changed and their punctuation fixed; the rest stays word for word."))
                    .font(.footnote)
                    .foregroundStyle(BasirPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .glassSurface()

            VStack(alignment: .leading, spacing: BasirSpacing.s) {
                SectionHeading(title: l10n.t("صوتك أنت (اختياري)", "Your own voice (optional)"))
                Text(l10n.t("الصق فصلًا أو صفحات كتبتها بنفسك قبل التدقيق الآلي، فيعيد بصير النص إلى أسلوبك أنت: طول جملك ومفرداتك وترقيمك.",
                            "Paste a chapter or a few pages you wrote yourself before any machine editing, and Basir brings the text back to your own style: your sentence length, words and punctuation."))
                    .font(.footnote)
                    .foregroundStyle(BasirPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                TextEditor(text: $sample)
                    .frame(minHeight: 90)
                    .padding(8)
                    .background(BasirPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel(l10n.t("نموذج من كتابتك", "A sample of your writing"))
                TextField(l10n.t("تعليمات خاصة، مثل: أبقِ اللهجة النجدية في الحوار", "Special instructions, e.g. keep the dialect in dialogue"),
                          text: $notes, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(12)
                    .background(BasirPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .glassSurface()

            PrimaryActionButton(title: l10n.t("ابدأ التحرير", "Start editing"), systemImage: "wand.and.stars") { start() }
                .disabled(!hasText)
            Text(l10n.t("استخدمها لنصوصك أو لنصوص لك حق تحريرها. يُرسل النص كاملًا إلى خادم بصير للمعالجة، ويستغرق نص طويل كرواية من عشرين دقيقة إلى ساعة، ويمكنك الانتقال إلى تطبيق آخر أثناءها. تشير نتيجة التحرير إلى أسلوب طبيعي، ولا تضمن أي أداة ما ستقوله أدوات كشف الذكاء الاصطناعي.",
                        "Use it for your own texts or texts you have the right to edit. The whole text is sent to Basir's server; a long text such as a novel takes twenty minutes to an hour, and you can use other apps meanwhile. The result aims at a natural style; no tool can promise what an AI detector will say."))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func progress(detail: String, done: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            Text(l10n.t("جارٍ التحرير", "Editing")).font(.headline).accessibilityAddTraits(.isHeader)
            if total > 0 {
                ProgressView(value: Double(done), total: Double(total)) { Text(detail) }
                    .accessibilityElement(children: .combine)
            } else {
                ProgressView(detail).frame(maxWidth: .infinity)
            }
            Text(l10n.t("يمكنك إغلاق هذه الشاشة أو الانتقال إلى تطبيق آخر؛ يستمر العمل وتصلك رسالة عند الانتهاء.",
                        "You can close this screen or switch apps; the work goes on and you'll be told when it's done."))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            SecondaryActionButton(title: l10n.t("إلغاء", "Cancel"), systemImage: "xmark.circle") {
                runner.cancel(configuration: settings.configuration)
            }
        }
        .glassSurface()
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            SectionHeading(title: l10n.t("نصوص حررها بصير", "Texts Basir edited"))
            ForEach(entries) { entry in
                Button { open = entry } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title).font(.headline)
                        Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened) + " · "
                             + l10n.t("\(entry.words) كلمة", "\(entry.words) words"))
                            .font(.footnote).foregroundStyle(BasirPalette.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(BasirSpacing.m)
                .background(BasirPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    // MARK: Actions

    static func words(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private func pick(_ url: URL) {
        fileError = nil
        do {
            let data = try Data(contentsOf: url)
            let name = url.lastPathComponent
            let isWord = url.pathExtension.lowercased() == "docx"
            let count: Int
            if isWord {
                let text = ((try? DocxExtractor.parse(url: url))?.blocks ?? []).compactMap(\.markdown).joined(separator: "\n")
                count = Self.words(in: text)
            } else {
                count = Self.words(in: String(decoding: data, as: UTF8.self))
            }
            file = PickedFile(name: name, data: data, words: count)
            if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
        } catch {
            fileError = l10n.t("تعذّر فتح الملف.", "The file could not be opened.")
        }
    }

    private func start() {
        var body = RestyleRequestBody(title: title.trimmingCharacters(in: .whitespacesAndNewlines))
        if let file {
            body.documentBase64 = file.data.base64EncodedString()
            body.documentName = file.name
        } else {
            body.text = pasted
        }
        body.styleSample = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        body.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        body.strength = strength
        runner.start(body, configuration: settings.configuration, l10n: l10n)
    }
}

/// One edited text: what changed, the text to read, the Word file, and the
/// paragraphs before and after.
struct RestyleResultView: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    let entry: RestyleStore.Entry
    @State private var result: RestyleResult?
    @State private var reading = false
    @State private var copied = false

    private var wordFile: URL? {
        guard let name = entry.wordFile, let folder = try? FileAccess.outputDirectory() else { return nil }
        let url = folder.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BasirSpacing.l) {
                if let result {
                    report(result)
                    actions(result)
                    changes(result)
                } else {
                    InlineMessage(text: l10n.t("تعذّر فتح هذا النص.", "This text could not be opened."), isError: true)
                }
            }
            .appScreenContent()
        }
        .background(BasirPalette.background.ignoresSafeArea())
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { result = RestyleStore.result(for: entry.id) }
        .fullScreenCover(isPresented: $reading) {
            if let result {
                DocumentReaderView(title: entry.title, blocks: result.readerBlocks())
                    .environmentObject(l10n)
                    .environmentObject(settings)
            }
        }
    }

    private func report(_ result: RestyleResult) -> some View {
        let r = result.report
        let arrow = l10n.isArabic ? "←" : "→"
        return VStack(alignment: .leading, spacing: BasirSpacing.s) {
            SectionHeading(title: l10n.t("ما تغيّر", "What changed"))
            Text(l10n.t("عُدّلت \(r.paragraphsChanged) فقرة من \(r.paragraphsTotal).",
                        "\(r.paragraphsChanged) of \(r.paragraphsTotal) paragraphs edited."))
            Text(l10n.t("الفاصلة المنقوطة «؛»: \(r.before.semicolons) \(arrow) \(r.after.semicolons)",
                        "Semicolons: \(r.before.semicolons) \(arrow) \(r.after.semicolons)"))
            Text(l10n.t("الشرطة الطويلة «—»: \(r.before.dashes) \(arrow) \(r.after.dashes)",
                        "Long dashes: \(r.before.dashes) \(arrow) \(r.after.dashes)"))
            Text(l10n.t("عبارات مستهلكة: \(r.before.stockPhrases) \(arrow) \(r.after.stockPhrases)",
                        "Stock phrases: \(r.before.stockPhrases) \(arrow) \(r.after.stockPhrases)"))
            Text(l10n.t("تنوع أطوال الجمل: \(Self.number(r.before.sentenceLengthSpread)) \(arrow) \(Self.number(r.after.sentenceLengthSpread))",
                        "Sentence-length variety: \(Self.number(r.before.sentenceLengthSpread)) \(arrow) \(Self.number(r.after.sentenceLengthSpread))"))
            if result.isPartial {
                InlineMessage(text: l10n.t("بقيت بعض الأجزاء على نصها الأصلي لتعذر تحريرها: \(r.partsKeptOriginal.map(String.init).joined(separator: "، ")).",
                                           "Some parts kept their original text: \(r.partsKeptOriginal.map(String.init).joined(separator: ", "))."),
                              isError: false)
            }
            Text(l10n.t("هذه مؤشرات للمراجعة لا شهادة. اقرأ النص بنفسك قبل نشره.",
                        "These are indicators to help you review, not a certificate. Read the text yourself before publishing it."))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
        }
        .glassSurface()
        .accessibilityElement(children: .combine)
    }

    private func actions(_ result: RestyleResult) -> some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            PrimaryActionButton(title: l10n.t("اقرأ النص", "Read the text"), systemImage: "book") { reading = true }
            if let wordFile {
                ShareLink(item: wordFile) {
                    Label(l10n.t("حفظ أو مشاركة ملف Word", "Save or share the Word file"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
                .tint(BasirPalette.accent)
            }
            SecondaryActionButton(title: copied ? l10n.t("نُسخ النص", "Text copied") : l10n.t("انسخ النص كاملًا", "Copy the whole text"),
                                  systemImage: "doc.on.doc") {
                UIPasteboard.general.string = result.plainText
                copied = true
                UIAccessibility.post(notification: .announcement, argument: l10n.t("نُسخ النص.", "Text copied."))
            }
        }
    }

    private func changes(_ result: RestyleResult) -> some View {
        let changed = result.blocks.filter(\.changed)
        return VStack(alignment: .leading, spacing: BasirSpacing.s) {
            SectionHeading(title: l10n.t("قبل وبعد (\(changed.count))", "Before and after (\(changed.count))"))
            LazyVStack(alignment: .leading, spacing: BasirSpacing.s) {
                ForEach(changed) { block in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: BasirSpacing.s) {
                            Text(l10n.t("قبل", "Before")).font(.caption.weight(.semibold)).foregroundStyle(BasirPalette.secondaryText)
                            Text(block.original).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            Text(l10n.t("بعد", "After")).font(.caption.weight(.semibold)).foregroundStyle(BasirPalette.secondaryText)
                            Text(block.text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                        .padding(.top, BasirSpacing.s)
                    } label: {
                        Text(block.text).lineLimit(2)
                    }
                    .padding(BasirSpacing.m)
                    .background(BasirPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    static func number(_ value: Double) -> String { String(format: "%.2f", value) }
}
