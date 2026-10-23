import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Human style: a text written (or heavily edited) by an AI turned into a
/// person's prose, or a person's own text brought back to their voice. The
/// server measures every window of the text against human writing of the same
/// kind, writes several versions of each part, chooses by measurement, and
/// checks that no fact was lost, changed or added.
struct RestyleView: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runner = RestyleRunner.shared
    @State private var pasted = ""
    @State private var file: PickedFile?
    @State private var title = ""
    @State private var sample = ""
    @State private var sampleSource = "author"
    @State private var draft = ""
    @State private var draftFile: PickedFile?
    @State private var notes = ""
    @AppStorage("restyle_strength") private var strength = "full"
    @AppStorage("restyle_mode") private var mode = "humanize"
    @AppStorage("restyle_domain") private var domain = "auto"
    @State private var picking: Picking?
    @State private var fileError: String?
    @State private var entries: [RestyleStore.Entry] = []
    @State private var open: RestyleStore.Entry?
    @State private var analysis: RestyleAnalysis?
    @State private var analyzing = false
    @State private var suggestions: RestyleSampleAnswer?
    @State private var chosen: Set<String> = []
    @State private var suggesting = false
    @State private var callError: String?

    enum Picking: String, Identifiable {
        case text, draft
        var id: String { rawValue }
    }

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
            .navigationTitle(l10n.t("أسلوب بشري", "Human style"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(l10n.t("إغلاق", "Close")) { dismiss() } }
            }
            .navigationDestination(isPresented: Binding(get: { open != nil }, set: { if !$0 { open = nil } })) {
                if let open { RestyleResultView(entry: open) }
            }
            .sheet(isPresented: Binding(get: { suggestions != nil }, set: { if !$0 { suggestions = nil } })) {
                if let suggestions { suggestionSheet(suggestions) }
            }
        }
        .escapeToDismiss { dismiss() }
        .fullScreenCover(item: $picking) { target in
            BasirDocumentPicker(contentTypes: [.basirDOCX, .plainText, UTType(filenameExtension: "md") ?? .plainText],
                                allowsMultipleSelection: false) { urls in
                picking = nil
                if let url = urls.first { pick(url, for: target) }
            } onCancel: { picking = nil }
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
            VStack(alignment: .leading, spacing: BasirSpacing.s) {
                SectionHeading(title: l10n.t("ما تريد", "What you want"))
                Picker(l10n.t("ما تريد", "What you want"), selection: $mode) {
                    Text(l10n.t("نص آلي إلى بشري", "Machine text to human")).tag("humanize")
                    Text(l10n.t("نصي إلى أسلوبي", "My text, my voice")).tag("restore")
                }
                .pickerStyle(.segmented)
                Text(mode == "humanize"
                     ? l10n.t("لنص كتبه الذكاء الاصطناعي أو أعاد صياغته. يقيس بصير كل مقطع من نحو مئتي كلمة على كتابة بشرية من النوع نفسه، فيترك ما يُقاس بشريًا كما هو، ويعيد كتابة ما يُقاس آليًا بثلاث صياغات يختار بينها بالقياس، ثم يتحقق نموذج مستقل من أن كل واقعة بقيت كما هي.",
                              "For a text an AI wrote or rewrote. Basir measures every stretch of about two hundred words against human writing of the same kind, leaves what measures as human exactly as it is, rewrites what measures as machine-made in three versions and picks one by measurement, then a separate model checks that every fact is unchanged.")
                     : l10n.t("لنص كتبته أنت ثم صار أسلوبه آليًا بعد تدقيقه بالذكاء الاصطناعي. يعيده بصير إلى أسلوبك بأقل تعديل: يغيّر ما وُجدت فيه علامة آلية فقط، ويرجع كل جملة أخرى كما كتبتها.",
                              "For a text you wrote that came to sound machine-made after an AI proofread. Basir brings it back to your voice with the fewest edits: only what carries a machine sign changes, and every other sentence comes back as you wrote it."))
                    .font(.footnote)
                    .foregroundStyle(BasirPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .glassSurface()

            VStack(alignment: .leading, spacing: BasirSpacing.s) {
                SectionHeading(title: l10n.t("النص", "The text"))
                PrimaryActionButton(title: l10n.t("اختر ملف Word أو ملفًا نصيًا", "Choose a Word or text file"),
                                    systemImage: "doc.text") { picking = .text }
                if let file {
                    HStack {
                        Label("\(file.name) · \(l10n.t("\(file.words) كلمة", "\(file.words) words"))", systemImage: "doc.fill")
                            .accessibilityElement(children: .combine)
                        Spacer()
                        Button(l10n.t("إزالة", "Remove")) { self.file = nil; analysis = nil }
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
                Picker(l10n.t("نوع النص", "Kind of text"), selection: $domain) {
                    Text(l10n.t("يحدده بصير", "Basir decides")).tag("auto")
                    Text(l10n.t("أدبي: رواية أو قصة أو مقالة أدبية", "Literary: novel, story, literary essay")).tag("literary")
                    Text(l10n.t("مقالة رأي", "Essay")).tag("essay")
                    Text(l10n.t("خبر", "News")).tag("news")
                    Text(l10n.t("أكاديمي", "Academic")).tag("academic")
                    Text(l10n.t("مراجعة", "Review")).tag("review")
                }
                SecondaryActionButton(title: analyzing ? l10n.t("جارٍ القياس…", "Measuring…")
                                                      : l10n.t("افحص النص قبل الإرسال", "Measure the text first"),
                                      systemImage: "waveform.path.ecg") { analyze() }
                    .disabled(!hasText || analyzing)
                if let analysis { analysisSummary(analysis) }
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
                     ? l10n.t("ما يُقاس آليًا يُكتب من جديد بأسلوب إنسان، والمعنى والوقائع كما هي.",
                              "What measures as machine-made is written again as a person would write it; meaning and facts stay.")
                     : l10n.t("يغيّر فقط الكلمات والجمل التي وُجدت فيها علامة آلية، ويبقي الباقي حرفيًا.",
                              "Only the words and sentences with a machine sign change; the rest stays word for word."))
                    .font(.footnote)
                    .foregroundStyle(BasirPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .glassSurface()

            sampleSection

            if mode == "restore" { draftSection }

            VStack(alignment: .leading, spacing: BasirSpacing.s) {
                SectionHeading(title: l10n.t("تعليمات خاصة (اختياري)", "Special instructions (optional)"))
                TextField(l10n.t("مثل: أبقِ اللهجة النجدية في الحوار", "E.g. keep the dialect in dialogue"),
                          text: $notes, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(12)
                    .background(BasirPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .glassSurface()

            if let callError { InlineMessage(text: callError, isError: true) }
            PrimaryActionButton(title: l10n.t("ابدأ", "Start"), systemImage: "wand.and.stars") { start() }
                .disabled(!hasText)
            Text(l10n.t("استخدمها لنصوصك أو لنصوص لك حق تحريرها. يُرسل النص كاملًا إلى خادم بصير، ويستغرق نص طويل كرواية من نصف ساعة إلى ساعتين، ويمكنك الانتقال إلى تطبيق آخر أثناءها. لا تستطيع أي أداة أن تضمن أن نصًا «بشري 100%» ولا ما ستقوله أدوات الكشف؛ يعرض لك التقرير ما قيس فعلًا، مع نسبة خطأ المقياس.",
                        "Use it for your own texts or texts you have the right to edit. The whole text is sent to Basir's server; a long text such as a novel takes half an hour to two hours, and you can use other apps meanwhile. No tool can guarantee a text is \"100% human\" or what a detector will say; the report shows what was actually measured, with the measure's error rate."))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sampleSection: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            SectionHeading(title: l10n.t("كتابة بشرية يُقاس عليها", "Human writing to measure against"))
            Text(mode == "restore"
                 ? l10n.t("أهم ما تضيفه: فصل أو صفحات كتبتها بنفسك قبل أي تدقيق آلي، ويُفضّل ألفا كلمة أو أكثر. يرى المحرر نصفها أمثلةً لأسلوبك، ويُحجب النصف الآخر ليقيس التقرير المسافة إلى أسلوبك دون أن يكون المحرر قد رآه.",
                          "The most useful thing to add: a chapter or pages you wrote yourself before any machine editing, ideally two thousand words or more. The editor sees half as examples of your voice; the other half is held back so the report can measure the distance to your voice on writing the editor never saw.")
                 : l10n.t("اختياري: صفحات كتبها إنسان بالأسلوب الذي تريده، أو مقاطع من نصك تختارها أنت. الأمثلة البشرية الحقيقية أنفع ما يُعطى للمحرر.",
                          "Optional: pages a person wrote in the style you want, or passages of your text you choose. Real human examples are the most useful thing to give the editor."))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $sample)
                .frame(minHeight: 90)
                .padding(8)
                .background(BasirPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel(l10n.t("كتابة بشرية", "Human writing"))
                .onChange(of: sample) { value in if value.isEmpty { sampleSource = "author" } }
            if !sample.isEmpty {
                Text(sampleSource == "internal"
                     ? l10n.t("\(Self.words(in: sample)) كلمة من مقاطع نصك التي اخترتها", "\(Self.words(in: sample)) words from the passages of your text you chose")
                     : l10n.t("\(Self.words(in: sample)) كلمة", "\(Self.words(in: sample)) words"))
                    .font(.footnote).foregroundStyle(BasirPalette.secondaryText)
            }
            SecondaryActionButton(title: suggesting ? l10n.t("جارٍ البحث…", "Looking…")
                                                    : l10n.t("اقترح مقاطع من نصي تبدو بشرية", "Suggest passages of my text that read as human"),
                                  systemImage: "text.magnifyingglass") { suggest() }
                .disabled(!hasText || suggesting)
        }
        .glassSurface()
    }

    private var draftSection: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            SectionHeading(title: l10n.t("مسودتك الأولى (اختياري)", "Your first draft (optional)"))
            Text(l10n.t("إن كانت عندك نسختك من النص قبل أن يدققه الذكاء الاصطناعي، أضفها: تصير المرجع الأول، فتعود جملتك حيث لم يصحح التدقيق خطأً حقيقيًا.",
                        "If you still have your version of the text from before the AI proofread, add it: it becomes the first reference, and your own sentence comes back wherever the proofread fixed no real error."))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let draftFile {
                HStack {
                    Label("\(draftFile.name) · \(l10n.t("\(draftFile.words) كلمة", "\(draftFile.words) words"))", systemImage: "doc.fill")
                        .accessibilityElement(children: .combine)
                    Spacer()
                    Button(l10n.t("إزالة", "Remove")) { self.draftFile = nil }
                }
            } else {
                SecondaryActionButton(title: l10n.t("اختر ملف المسودة", "Choose the draft file"), systemImage: "doc.badge.clock") {
                    picking = .draft
                }
                TextEditor(text: $draft)
                    .frame(minHeight: 70)
                    .padding(8)
                    .background(BasirPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel(l10n.t("مسودتك الأولى", "Your first draft"))
            }
        }
        .glassSurface()
    }

    private func analysisSummary(_ analysis: RestyleAnalysis) -> some View {
        let m = analysis.machine
        return VStack(alignment: .leading, spacing: BasirSpacing.xs) {
            if m.available, m.windows > 0 {
                Text(l10n.t("يُقاس آليًا \(m.judgeFlaggedBefore) مقطع من \(m.windows).",
                            "\(m.judgeFlaggedBefore) of \(m.windows) stretches measure as machine-made."))
                    .font(.subheadline.weight(.semibold))
                Text(Self.errorLine(m, l10n: l10n))
                    .font(.footnote).foregroundStyle(BasirPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(l10n.t("تعذّر القياس لهذه اللغة.", "This language could not be measured.")).font(.footnote)
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func errorLine(_ m: RestyleResult.Machine, l10n: L10n) -> String {
        let fpr = Int((m.judgeFalsePositiveRate * 100).rounded())
        let tpr = Int((m.judgeTruePositiveRate * 100).rounded())
        return l10n.t("هذا المقياس يعدّ نحو \(fpr)% من النصوص البشرية آلية خطأً، ويلتقط نحو \(tpr)% من النصوص الآلية؛ فهو مؤشر لا حكم.",
                      "This measure wrongly flags about \(fpr)% of human text and catches about \(tpr)% of machine text: an indicator, not a verdict.")
    }

    private func suggestionSheet(_ answer: RestyleSampleAnswer) -> some View {
        NavigationStack {
            List {
                Section {
                    Text(l10n.t("هذه مقاطع من نصك لا تظهر فيها علامة آلية. اختر منها ما تعرف أنه كتابتك أنت، فتُستعمل أمثلةً لأسلوبك.",
                                "These passages of your text show no machine sign. Choose the ones you know are your own writing; they will be used as examples of your voice."))
                        .font(.footnote)
                }
                if answer.passages.isEmpty {
                    Text(l10n.t("لم يجد بصير مقطعًا خاليًا من العلامات الآلية.", "Basir found no passage free of machine signs."))
                }
                ForEach(answer.passages) { passage in
                    Button {
                        if chosen.contains(passage.id) { chosen.remove(passage.id) } else { chosen.insert(passage.id) }
                    } label: {
                        HStack(alignment: .top) {
                            Image(systemName: chosen.contains(passage.id) ? "checkmark.circle.fill" : "circle")
                                .accessibilityHidden(true)
                            Text(passage.text).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityAddTraits(chosen.contains(passage.id) ? .isSelected : [])
                }
            }
            .navigationTitle(l10n.t("مقاطع تبدو بشرية", "Passages that read as human"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(l10n.t("إلغاء", "Cancel")) { suggestions = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(l10n.t("اعتمدها", "Use them")) {
                        sample = answer.passages.filter { chosen.contains($0.id) }.map(\.text).joined(separator: "\n")
                        sampleSource = "internal"
                        suggestions = nil
                    }
                    .disabled(chosen.isEmpty)
                }
            }
        }
    }

    private func progress(detail: String, done: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            Text(l10n.t("جارٍ العمل", "Working")).font(.headline).accessibilityAddTraits(.isHeader)
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

    private func pick(_ url: URL, for target: Picking) {
        fileError = nil
        do {
            let data = try Data(contentsOf: url)
            let name = url.lastPathComponent
            let count: Int
            if url.pathExtension.lowercased() == "docx" {
                let text = ((try? DocxExtractor.parse(url: url))?.blocks ?? []).compactMap(\.markdown).joined(separator: "\n")
                count = Self.words(in: text)
            } else {
                count = Self.words(in: String(decoding: data, as: UTF8.self))
            }
            let picked = PickedFile(name: name, data: data, words: count)
            switch target {
            case .text:
                file = picked
                analysis = nil
                if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
            case .draft:
                draftFile = picked
            }
        } catch {
            fileError = l10n.t("تعذّر فتح الملف.", "The file could not be opened.")
        }
    }

    /// The text alone, for the calls answered at once.
    private func textBody() -> Data? {
        var object: [String: String] = ["language": "auto", "domain": domain]
        if let file {
            object["document_base64"] = file.data.base64EncodedString()
            object["document_name"] = file.name
        } else {
            object["text"] = pasted
        }
        return try? JSONSerialization.data(withJSONObject: object)
    }

    private func analyze() {
        guard let body = textBody() else { return }
        analyzing = true
        callError = nil
        Task {
            defer { analyzing = false }
            do {
                let data = try await ProxyClient(configuration: settings.configuration).restyleCall("analyze", body: body)
                analysis = try RestyleAnalysis.decode(data)
                if let analysis {
                    UIAccessibility.post(notification: .announcement,
                                         argument: l10n.t("يُقاس آليًا \(analysis.machine.judgeFlaggedBefore) مقطع من \(analysis.machine.windows).",
                                                          "\(analysis.machine.judgeFlaggedBefore) of \(analysis.machine.windows) stretches measure as machine-made."))
                }
            } catch {
                callError = DocumentAssistant.message(for: error, l10n: l10n)
            }
        }
    }

    private func suggest() {
        guard let body = textBody() else { return }
        suggesting = true
        callError = nil
        Task {
            defer { suggesting = false }
            do {
                let data = try await ProxyClient(configuration: settings.configuration).restyleCall("sample", body: body)
                let answer = try RestyleSampleAnswer.decode(data)
                chosen = Set(answer.passages.map(\.id))
                suggestions = answer
            } catch {
                callError = DocumentAssistant.message(for: error, l10n: l10n)
            }
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
        body.sampleSource = body.styleSample.isEmpty ? "author" : sampleSource
        if mode == "restore" {
            if let draftFile {
                body.authorDraftBase64 = draftFile.data.base64EncodedString()
                body.authorDraftName = draftFile.name
            } else {
                body.authorDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        body.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        body.strength = strength
        body.mode = mode
        body.domain = domain
        runner.start(body, configuration: settings.configuration, l10n: l10n)
    }
}

/// One edited text: what was measured, the text to read, every edit with its
/// reason (each paragraph accepted or refused), a blind comparison, and the
/// Word file made again from the author's choices.
struct RestyleResultView: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    let entry: RestyleStore.Entry
    @State private var result: RestyleResult?
    @State private var choices = RestyleStore.Choices()
    @State private var reading = false
    @State private var copied = false
    @State private var blind = false
    @State private var exporting = false
    @State private var exportError: String?
    @State private var wordName: String?

    private var wordFile: URL? {
        guard let name = wordName ?? entry.wordFile, let folder = try? FileAccess.outputDirectory() else { return nil }
        let url = folder.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private var final: RestyleResult? { result?.applying(refused: choices.refused) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BasirSpacing.l) {
                if let result {
                    report(result)
                    actions(result)
                    if let windows = result.report.windows, !windows.isEmpty { stretches(windows) }
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
        .onAppear {
            result = RestyleStore.result(for: entry.id)
            choices = RestyleStore.choices(for: entry.id)
        }
        .fullScreenCover(isPresented: $reading) {
            if let final {
                DocumentReaderView(title: entry.title, blocks: final.readerBlocks())
                    .environmentObject(l10n)
                    .environmentObject(settings)
            }
        }
        .sheet(isPresented: $blind) {
            if let result {
                BlindTestView(result: result, test: Binding(get: { choices.blind }, set: { value in
                    choices.blind = value
                    RestyleStore.setChoices(choices, for: entry.id)
                }))
                .environmentObject(l10n)
            }
        }
    }

    private func report(_ result: RestyleResult) -> some View {
        let r = result.report
        let arrow = l10n.isArabic ? "←" : "→"
        return VStack(alignment: .leading, spacing: BasirSpacing.s) {
            SectionHeading(title: l10n.t("ما قيس وما تغيّر", "What was measured and changed"))
            if let kept = r.paragraphsKept, let rewritten = r.paragraphsRewritten {
                Text(l10n.t("الفقرات \(r.paragraphsTotal): بقيت \(kept) كما هي لأنها تُقاس بشرية، وأُعيدت كتابة \(rewritten)، وتغيّرت \(r.paragraphsChanged) في المجموع.",
                            "\(r.paragraphsTotal) paragraphs: \(kept) measured as human and were left as they were, \(rewritten) were rewritten, \(r.paragraphsChanged) changed in all."))
            } else {
                Text(l10n.t("عُدّلت \(r.paragraphsChanged) فقرة من \(r.paragraphsTotal).",
                            "\(r.paragraphsChanged) of \(r.paragraphsTotal) paragraphs edited."))
            }
            if let percent = r.wordsChangedPercent {
                Text(l10n.t("الكلمات المتغيرة: \(Self.number(percent, digits: 1))%", "Words changed: \(Self.number(percent, digits: 1))%"))
            }
            if let m = r.machine, m.available, m.windows > 0 {
                Text(l10n.t("مقاطع تُقاس آلية، بمقياس مستقل لم يُستعمل في اختيار الصياغة: \(m.judgeFlaggedBefore) \(arrow) \(m.judgeFlaggedAfter) من \(m.windows)",
                            "Stretches that measure as machine-made, by an independent measure never used to choose the wording: \(m.judgeFlaggedBefore) \(arrow) \(m.judgeFlaggedAfter) of \(m.windows)"))
                    .font(.body.weight(.semibold))
                Text(l10n.t("قراءات الإشارات ضمن المدى البشري لهذا النوع: \(Int((m.inRangeBefore * 100).rounded()))% \(arrow) \(Int((m.inRangeAfter * 100).rounded()))%",
                            "Signal readings inside the human range for this kind of text: \(Int((m.inRangeBefore * 100).rounded()))% \(arrow) \(Int((m.inRangeAfter * 100).rounded()))%"))
                Text(RestyleView.errorLine(m, l10n: l10n))
                    .font(.footnote).foregroundStyle(BasirPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if !m.uniformSignals.isEmpty {
                    InlineMessage(text: l10n.t("بعض الإشارات صارت متجانسة عبر النص أكثر مما في نص بشري واحد؛ راجع الإيقاع بين الفصول.",
                                               "Some signals became more uniform across the text than in one human document; check the rhythm between chapters."),
                                  isError: false)
                }
            }
            if let checked = r.meaningChecked, checked > 0 {
                Text(l10n.t("فحص المعنى بنموذج مستقل: \(checked) فقرة، أُعيدت منها \(r.meaningFailed ?? 0) إلى نصها الأصلي لأن واقعة فيها تغيّرت.",
                            "Meaning checked by a separate model: \(checked) paragraphs; \(r.meaningFailed ?? 0) went back to their original because a fact changed."))
            }
            if let d = r.distance, d.available {
                Text(l10n.t("المسافة إلى كتابتك المحجوبة (الأقل أقرب): \(Self.number(d.deltaBefore)) \(arrow) \(Self.number(d.deltaAfter))؛ وتتفاوت كتابتك نفسها بنحو \(Self.number(d.deltaAuthor)).",
                            "Distance to your held-back writing (lower is closer): \(Self.number(d.deltaBefore)) \(arrow) \(Self.number(d.deltaAfter)); your own writing varies by about \(Self.number(d.deltaAuthor))."))
            }
            if let categories = r.editCategories, !categories.isEmpty {
                Text(l10n.t("أنواع التعديلات: ", "Kinds of edit: ")
                     + categories.sorted { $0.value > $1.value }.map { "\(Self.category($0.key, l10n: l10n)) \($0.value)" }
                        .joined(separator: l10n.isArabic ? "، " : ", "))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(l10n.t("الفاصلة المنقوطة «؛»: \(r.before.semicolons) \(arrow) \(r.after.semicolons) · الشرطة الطويلة «—»: \(r.before.dashes) \(arrow) \(r.after.dashes) · متوسط الجملة: \(Self.number(r.before.averageSentenceWords, digits: 0)) \(arrow) \(Self.number(r.after.averageSentenceWords, digits: 0)) كلمة",
                        "Semicolons: \(r.before.semicolons) \(arrow) \(r.after.semicolons) · Long dashes: \(r.before.dashes) \(arrow) \(r.after.dashes) · Average sentence: \(Self.number(r.before.averageSentenceWords, digits: 0)) \(arrow) \(Self.number(r.after.averageSentenceWords, digits: 0)) words"))
                .font(.footnote)
            if result.isPartial {
                InlineMessage(text: l10n.t("بقيت بعض الأجزاء على نصها الأصلي لتعذر تحريرها: \(r.partsKeptOriginal.map(String.init).joined(separator: "، ")).",
                                           "Some parts kept their original text: \(r.partsKeptOriginal.map(String.init).joined(separator: ", "))."),
                              isError: false)
            }
            Text(l10n.t("هذه قياسات للمراجعة لا شهادة. لا يملك أحد مقياسًا يشهد بأن نصًا «بشري 100%»، ولا ما ستقوله أدوات الكشف. اقرأ النص بنفسك، وجرّب الاختبار الأعمى.",
                        "These are measurements for review, not a certificate. No measure can certify a text as \"100% human\", nor what a detector will say. Read the text yourself, and try the blind comparison."))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
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
            if !choices.refused.isEmpty {
                SecondaryActionButton(title: exporting ? l10n.t("جارٍ الإنشاء…", "Making…")
                                                       : l10n.t("أنشئ ملف Word بقراراتي (\(choices.refused.count) مرفوضة)",
                                                                "Make the Word file with my choices (\(choices.refused.count) refused)"),
                                      systemImage: "doc.badge.gearshape") { export() }
                    .disabled(exporting)
                if let exportError { InlineMessage(text: exportError, isError: true) }
            }
            SecondaryActionButton(title: l10n.t("اختبار أعمى: أيّ النسختين أقرب إلى كتابة إنسان؟", "Blind test: which version reads more like a person?"),
                                  systemImage: "eye.slash") { blind = true }
            if let share = choices.blind?.share, let test = choices.blind {
                Text(l10n.t("في الاختبار الأعمى فضّلت النسخة المحررة في \(test.preferredEdited) من \(test.answered.count) (بين \(Int((share.low * 100).rounded()))% و\(Int((share.high * 100).rounded()))% بثقة 95%).",
                            "In the blind test you preferred the edited version in \(test.preferredEdited) of \(test.answered.count) (between \(Int((share.low * 100).rounded()))% and \(Int((share.high * 100).rounded()))% at 95% confidence)."))
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SecondaryActionButton(title: copied ? l10n.t("نُسخ النص", "Text copied") : l10n.t("انسخ النص كاملًا", "Copy the whole text"),
                                  systemImage: "doc.on.doc") {
                UIPasteboard.general.string = (final ?? result).plainText
                copied = true
                UIAccessibility.post(notification: .announcement, argument: l10n.t("نُسخ النص.", "Text copied."))
            }
        }
    }

    private func stretches(_ windows: [RestyleResult.WindowScore]) -> some View {
        DisclosureGroup {
            LazyVStack(alignment: .leading, spacing: BasirSpacing.xs) {
                ForEach(Array(windows.enumerated()), id: \.offset) { index, window in
                    Text(l10n.t("المقطع \(index + 1): \(Self.verdict(window.flaggedBefore)) ← \(Self.verdict(window.flaggedAfter)) (\(Self.number(window.before)) ← \(Self.number(window.after)))",
                                "Stretch \(index + 1): \(Self.verdictEn(window.flaggedBefore)) → \(Self.verdictEn(window.flaggedAfter)) (\(Self.number(window.before)) → \(Self.number(window.after)))"))
                        .font(.footnote)
                        .accessibilityLabel(l10n.t("المقطع \(index + 1)، قبل: \(Self.verdict(window.flaggedBefore))، بعد: \(Self.verdict(window.flaggedAfter))",
                                                   "Stretch \(index + 1), before: \(Self.verdictEn(window.flaggedBefore)), after: \(Self.verdictEn(window.flaggedAfter))"))
                }
            }
            .padding(.top, BasirSpacing.s)
        } label: {
            Text(l10n.t("قياس كل مقطع", "Each stretch measured")).font(.headline)
        }
        .glassSurface()
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
                            if let edits = block.edits, !edits.isEmpty {
                                Text(l10n.t("التعديلات", "Edits")).font(.caption.weight(.semibold)).foregroundStyle(BasirPalette.secondaryText)
                                ForEach(edits, id: \.self) { edit in
                                    Text("\(Self.category(edit.category, l10n: l10n)): «\(edit.before)» \(l10n.isArabic ? "←" : "→") «\(edit.after)»"
                                         + (edit.reason.isEmpty ? "" : " — \(edit.reason)"))
                                        .font(.footnote)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Toggle(l10n.t("أقبل هذا التعديل", "I accept this edit"), isOn: Binding(
                                get: { !choices.refused.contains(block.id) },
                                set: { accepted in
                                    if accepted { choices.refused.remove(block.id) } else { choices.refused.insert(block.id) }
                                    RestyleStore.setChoices(choices, for: entry.id)
                                }))
                        }
                        .padding(.top, BasirSpacing.s)
                    } label: {
                        Text((choices.refused.contains(block.id) ? l10n.t("مرفوض: ", "Refused: ") : "") + block.text).lineLimit(2)
                    }
                    .padding(BasirSpacing.m)
                    .background(BasirPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    private func export() {
        guard let final, let data = try? final.encoded(),
              let object = try? JSONSerialization.jsonObject(with: data),
              let body = try? JSONSerialization.data(withJSONObject: [
                  "result": object, "refused": choices.refused.count,
                  "accepted": (result?.blocks.filter(\.changed).count ?? 0) - choices.refused.count,
              ] as [String: Any])
        else { return }
        exporting = true
        exportError = nil
        Task {
            defer { exporting = false }
            do {
                let word = try await ProxyClient(configuration: settings.configuration).restyleCall("document", body: body)
                guard let folder = try? FileAccess.outputDirectory() else { return }
                let base = FileAccess.sanitizeFilename(entry.title)
                var target = folder.appendingPathComponent(base + l10n.t(" - بقراراتي", " - my choices") + ".docx")
                var counter = 2
                while FileManager.default.fileExists(atPath: target.path) {
                    target = folder.appendingPathComponent(base + l10n.t(" - بقراراتي", " - my choices") + " \(counter).docx")
                    counter += 1
                }
                try word.write(to: target, options: [.atomic, .completeFileProtectionUnlessOpen])
                wordName = target.lastPathComponent
                RestyleStore.setWordFile(target.lastPathComponent, for: entry.id)
                UIAccessibility.post(notification: .announcement,
                                     argument: l10n.t("أُنشئ ملف Word بقراراتك في «ملفاتي».", "The Word file with your choices is in My Files."))
            } catch {
                exportError = DocumentAssistant.message(for: error, l10n: l10n)
            }
        }
    }

    static func category(_ key: String, l10n: L10n) -> String {
        // Dictionary keys arrive camel-cased by the snake-case decoder; both forms are understood.
        let snake = key.reduce(into: "") { out, ch in
            if ch.isUppercase { out += "_" + ch.lowercased() } else { out.append(ch) }
        }
        let names: [String: (String, String)] = [
            "awkward_word": ("لفظ متكلف", "awkward word"), "sentence_structure": ("بنية الجملة", "sentence structure"),
            "over_explaining": ("شرح زائد", "over-explaining"), "cliche": ("عبارة مستهلكة", "cliché"),
            "purple_prose": ("زخرفة", "purple prose"), "vague": ("لفظ عام", "vague word"), "tense": ("الزمن", "tense"),
            "translated_construction": ("تركيب مترجم", "translated construction"), "punctuation": ("الترقيم", "punctuation"),
            "summary_ending": ("خاتمة تلخيصية", "summary ending"), "author_restored": ("من مسودتك", "from your draft"),
            "other": ("أخرى", "other"),
        ]
        guard let name = names[snake] else { return key }
        return l10n.t(name.0, name.1)
    }

    static func verdict(_ flagged: Bool) -> String { flagged ? "يُقاس آليًا" : "ضمن البشري" }
    static func verdictEn(_ flagged: Bool) -> String { flagged ? "measures as machine" : "within human" }
    static func number(_ value: Double, digits: Int = 2) -> String { String(format: "%.\(digits)f", value) }
}

/// The blind comparison: the original and the edited paragraph, in a random
/// order, unlabelled; the reader picks the one that reads more like a person.
struct BlindTestView: View {
    @EnvironmentObject private var l10n: L10n
    @Environment(\.dismiss) private var dismiss
    let result: RestyleResult
    @Binding var test: BlindTest?
    @State private var index = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BasirSpacing.l) {
                    if let test, index < test.trials.count {
                        trial(test.trials[index], number: index + 1, of: test.trials.count)
                    } else if let test, let share = test.share {
                        Text(l10n.t("فضّلت النسخة المحررة في \(test.preferredEdited) من \(test.answered.count).",
                                    "You preferred the edited version in \(test.preferredEdited) of \(test.answered.count)."))
                            .font(.headline)
                        Text(l10n.t("بثقة 95%: بين \(Int((share.low * 100).rounded()))% و\(Int((share.high * 100).rounded()))%. كلما زادت الأسئلة ضاق المدى. والأصدق أن يجيب قارئ آخر يعرف هذا النوع من الكتابة.",
                                    "At 95% confidence: between \(Int((share.low * 100).rounded()))% and \(Int((share.high * 100).rounded()))%. More questions narrow the range; the most honest answer comes from another reader who knows this kind of writing."))
                            .fixedSize(horizontal: false, vertical: true)
                        PrimaryActionButton(title: l10n.t("تم", "Done"), systemImage: "checkmark") { dismiss() }
                    } else {
                        Text(l10n.t("لا توجد فقرات محررة كافية للاختبار.", "There are not enough edited paragraphs to test."))
                    }
                }
                .appScreenContent()
            }
            .navigationTitle(l10n.t("اختبار أعمى", "Blind test"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(l10n.t("إغلاق", "Close")) { dismiss() } }
            }
            .onAppear {
                if test == nil || test?.answered.count == test?.trials.count {
                    var generator = SystemRandomNumberGenerator()
                    test = BlindTest.make(from: result, using: &generator)
                    index = 0
                } else {
                    index = test?.answered.count ?? 0
                }
            }
        }
    }

    private func trial(_ trial: BlindTest.Trial, number: Int, of total: Int) -> some View {
        let block = result.blocks.first { $0.id == trial.id }
        let edited = block?.text ?? ""
        let original = block?.original ?? ""
        let first = trial.editedFirst ? edited : original
        let second = trial.editedFirst ? original : edited
        return VStack(alignment: .leading, spacing: BasirSpacing.m) {
            Text(l10n.t("السؤال \(number) من \(total): أيّ النصين أقرب إلى كتابة إنسان يجيد هذا النوع؟",
                        "Question \(number) of \(total): which reads more like a person who writes this kind of text well?"))
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            option(l10n.t("النص الأول", "First text"), first) { answer(editedChosen: trial.editedFirst) }
            option(l10n.t("النص الثاني", "Second text"), second) { answer(editedChosen: !trial.editedFirst) }
        }
    }

    private func option(_ label: String, _ text: String, choose: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            Text(label).font(.subheadline.weight(.semibold))
            Text(text).fixedSize(horizontal: false, vertical: true)
            SecondaryActionButton(title: l10n.t("هذا أقرب", "This one"), systemImage: "hand.point.up.left") { choose() }
                .accessibilityLabel(l10n.t("\(label) أقرب", "\(label) is closer"))
        }
        .glassSurface()
    }

    private func answer(editedChosen: Bool) {
        guard var current = test, index < current.trials.count else { return }
        current.trials[index].choseEdited = editedChosen
        test = current
        index += 1
    }
}
