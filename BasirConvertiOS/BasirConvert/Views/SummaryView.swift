import SwiftUI
import UIKit

/// What is being summarized: one document (its text and reader blocks) or
/// several files together, and where the summary is kept.
struct SummarySource {
    var title: String
    var text: String = ""
    var files: [SummaryRequestBody.File] = []
    var home: SummaryHome
    /// The reader blocks, so a point can lead to its page (ت12).
    var blocks: [ReaderBlock] = []
    /// The Word file in My Files, so a page can be opened when the summary
    /// was not opened from the reader.
    var outputURL: URL?

    /// Everything the follow-up questions may draw on (ت13).
    var questionText: String {
        guard !files.isEmpty else { return text }
        return files.enumerated().map { "\($0.offset + 1). \($0.element.name)\n\($0.element.text)" }
            .joined(separator: "\n\n")
    }
}

/// The summary screen: one line, a paragraph, every key point, the document
/// type's own headings, a section-by-section summary, an easy-read version,
/// and study cards and questions on request. Built for VoiceOver first: real
/// headings, one element per point with its page, its verification and its
/// actions (go to the page, explain, simplify, ask) as VoiceOver actions.
struct SummaryView: View {
    enum Level: String, CaseIterable, Identifiable {
        case oneLine, short, detailed, easy
        var id: String { rawValue }

        @MainActor
        func title(_ l10n: L10n) -> String {
            switch self {
            case .oneLine: return l10n.t("سطر واحد", "One line")
            case .short: return l10n.t("فقرة", "Paragraph")
            case .detailed: return l10n.t("مفصّل", "Detailed")
            case .easy: return l10n.t("مبسّط", "Easy read")
            }
        }
    }

    enum FollowUpKind: String { case explain, simplify, ask }

    struct FollowUp: Identifiable {
        let point: DocumentSummary.Point
        let kind: FollowUpKind
        var id: String { point.id + kind.rawValue }
    }

    let source: SummarySource
    /// Moves the reader to a block (set when opened from the reader).
    var onJump: ((Int) -> Void)?

    @MainActor
    init(source: SummarySource, onJump: ((Int) -> Void)? = nil) {
        self.source = source
        self.onJump = onJump
        // The work lives in the app, not in this screen: closing the screen
        // never stops a summary, and opening it again shows where it is.
        _runner = ObservedObject(wrappedValue: SummaryCenter.shared.runner(for: source.home))
    }

    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runner: SummaryRunner
    @StateObject private var speaker = ReaderSpeaker()
    @StateObject private var audiobook = AudiobookExporter()
    @AppStorage("summary.level") private var levelRaw = Level.short.rawValue
    @State private var language = ""
    @State private var template = SummaryTemplate.automatic
    @State private var includeStudy = false
    @State private var showOptions = false
    @State private var showAudiobook = false
    @State private var shareURL: URL?
    @State private var exporting = false
    @State private var exportError: String?
    @State private var answers: [String: String] = [:]
    @State private var pendingQuestion: FollowUp?
    @State private var questionText = ""
    @State private var workingFollowUp: String?
    @State private var revealedCards: Set<String> = []
    @State private var chosenAnswers: [String: Int] = [:]
    @State private var expandedSections: Set<String> = []
    @State private var readerPage: ReaderTarget?

    private var level: Level { Level(rawValue: levelRaw) ?? .short }
    private var isSeveralFiles: Bool { source.files.count > 1 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BasirSpacing.l) {
                    if let summary = runner.summary {
                        result(summary)
                    } else {
                        startCard
                    }
                }
                .appScreenContent()
            }
            .background(BasirPalette.background.ignoresSafeArea())
            .foregroundStyle(BasirPalette.primaryText)
            .navigationTitle(l10n.t("ملخص: \(source.title)", "Summary: \(source.title)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(l10n.t("تم", "Done")) { close() }.fontWeight(.semibold)
                }
                if let summary = runner.summary {
                    ToolbarItem(placement: .navigationBarLeading) { actionsMenu(summary) }
                }
            }
            .sheet(isPresented: $showOptions) { optionsSheet }
            .sheet(isPresented: $showAudiobook) {
                if let summary = runner.summary {
                    AudiobookExportView(exporter: audiobook, title: SummaryExport.fileName(source.title, l10n: l10n),
                                        passages: SummaryExport.spokenPassages(summary, title: source.title, l10n: l10n))
                }
            }
            .sheet(item: Binding(get: { shareURL.map(ShareTarget.init) }, set: { shareURL = $0?.url })) { item in
                ActivityShareView(urls: [item.url])
            }
            .sheet(item: $pendingQuestion) { followUp in questionSheet(followUp) }
            .fullScreenCover(item: $readerPage) { target in
                DocumentReaderView(url: target.url, startAtPage: target.page)
            }
        }
        .escapeToDismiss { close() }
        .onAppear(perform: start)
        .onDisappear { speaker.stop(); audiobook.cancel() }
    }

    // MARK: Start

    private var request: SummaryRequestBody {
        SummaryRequestBody(
            text: source.files.isEmpty ? source.text : "",
            files: source.files,
            title: source.title,
            language: language.isEmpty ? (l10n.isArabic ? "ar" : "en") : language,
            template: isSeveralFiles && template == .automatic ? SummaryTemplate.multi.rawValue : template.rawValue,
            includeStudy: includeStudy,
            choice: settings.preferredModel.serverModelID
        )
    }

    private func start() {
        if language.isEmpty { language = runner.summary?.language ?? (l10n.isArabic ? "ar" : "en") }
        // Still working from an earlier visit: show its progress, do not restart.
        if case .working = runner.phase { return }
        guard runner.summary == nil else { return }
        if let saved = SummaryRunner.saved(request, home: source.home) {
            runner.showSaved(saved)
        } else if case .output(let url) = source.home, let latest = SummaryStore.latest(forOutput: url) {
            // A summary made earlier (for example while converting) opens at once.
            runner.showSaved(latest)
            language = latest.language
        } else {
            summarize()
        }
    }

    private func summarize() {
        speaker.stop()
        runner.run(request, home: source.home, configuration: settings.configuration, l10n: l10n)
    }

    @ViewBuilder
    private var startCard: some View {
        switch runner.phase {
        case .working(let detail, let done, let total):
            VStack(alignment: .leading, spacing: BasirSpacing.m) {
                if total > 1 {
                    ProgressView(value: Double(done), total: Double(total)) { Text(detail) }
                } else {
                    ProgressView { Text(detail) }
                }
                Text(l10n.t("يقرأ بصير المستند ويعدّ الملخص، ثم يراجع نقاطه بالرجوع إلى النص الأصلي. يمكنك مغادرة هذه الشاشة أثناء العمل. عند تلخيص مستند طويل، ينبهك بصير عند اكتماله إذا كانت الإشعارات مفعّلة.",
                            "Basir reads the document, prepares a summary, and checks its points against the source text. You can leave this screen while it works. For long summaries, Basir notifies you when it finishes if notifications are enabled."))
                    .font(.footnote)
                    .foregroundStyle(BasirPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                SecondaryActionButton(title: l10n.t("إيقاف", "Stop"), systemImage: "stop.fill") { runner.cancel() }
            }
            .glassSurface()
        case .failed(let message):
            InlineMessage(text: message, isError: true)
            PrimaryActionButton(title: l10n.t("إعادة المحاولة", "Try again"), systemImage: "arrow.clockwise") { summarize() }
            SecondaryActionButton(title: l10n.t("خيارات الملخص", "Summary options"), systemImage: "slider.horizontal.3") {
                showOptions = true
            }
        default:
            VStack(alignment: .leading, spacing: BasirSpacing.m) {
                Text(l10n.t("احصل على ملخص لأهم النقاط مع مراجع إلى صفحات المستند. يراجع بصير النقاط بالرجوع إلى النص الأصلي.",
                            "Get a summary of the key points with references to the document’s pages. Basir checks the points against the source text."))
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryActionButton(title: l10n.t("لخّص الآن", "Summarize now"), systemImage: "text.badge.star") { summarize() }
                SecondaryActionButton(title: l10n.t("خيارات الملخص", "Summary options"), systemImage: "slider.horizontal.3") {
                    showOptions = true
                }
            }
            .glassSurface()
        }
    }

    // MARK: Result

    @ViewBuilder
    private func result(_ summary: DocumentSummary) -> some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            Text(summary.documentType.isEmpty ? source.title : summary.documentType)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(templateTitle(summary))
                .font(.subheadline)
                .foregroundStyle(BasirPalette.secondaryText)
            if summary.verification.pointsTotal > 0 {
                Label(SummaryExport.verificationSentence(summary.verification, l10n: l10n), systemImage: "checkmark.seal")
                    .font(.footnote)
                    .foregroundStyle(BasirPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !summary.notice.isEmpty {
                InlineMessage(text: summary.notice, isError: false)
            }
            if summary.language != (l10n.isArabic ? "ar" : "en") || isSeveralFiles {
                Text(isSeveralFiles
                     ? l10n.t("ملخص مشترك لـ \(source.files.count) ملفات.", "One summary of \(source.files.count) files.")
                     : l10n.t("لغة الملخص: \(languageName(summary.language))", "Summary language: \(languageName(summary.language))"))
                    .font(.footnote)
                    .foregroundStyle(BasirPalette.secondaryText)
            }
        }
        .glassSurface()

        Picker(l10n.t("طول الملخص", "Summary length"), selection: $levelRaw) {
            ForEach(Level.allCases) { item in Text(item.title(l10n)).tag(item.rawValue) }
        }
        .pickerStyle(.segmented)
        .accessibilityHint(l10n.t("يعرض نسخة أخرى من الملخص دون إعادة تلخيص المستند.", "Shows another version of the summary without summarizing the document again."))

        levelContent(summary)

        ForEach(summary.groups.filter { !$0.points.isEmpty }) { group in
            SectionHeading(title: group.heading)
            ForEach(group.points) { point in pointRow(point, in: summary) }
        }

        if !summary.sections.isEmpty {
            SectionHeading(title: l10n.t("أقسام الملخص", "Section by section"))
            ForEach(summary.sections) { section in sectionRow(section, in: summary) }
        }

        if !summary.cards.isEmpty { cards(summary) }
        if !summary.quiz.isEmpty { quiz(summary) }

        if !summary.keyPoints.isEmpty || !summary.groups.isEmpty {
            Text(l10n.t("تظهر مراجع الصفحات مع نقاط الملخص. إذا ظهرت عبارة «غير مؤكد في النص»، فراجع المستند الأصلي؛ لم يجد بصير نصًا يؤكد هذه النقطة.",
                        "Every point names its page. “Not confirmed in the text” means Basir found no passage that supports it word for word; check the original before relying on it."))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let exportError { InlineMessage(text: exportError, isError: true) }
    }

    @ViewBuilder
    private func levelContent(_ summary: DocumentSummary) -> some View {
        switch level {
        case .oneLine:
            overviewCard(summary.oneLine)
        case .short:
            overviewCard(summary.short)
        case .easy:
            overviewCard(summary.easyRead)
        case .detailed:
            SectionHeading(title: l10n.t("أهم النقاط", "Key points"))
            if summary.keyPoints.isEmpty {
                overviewCard(summary.short)
            } else {
                ForEach(summary.keyPoints) { point in pointRow(point, in: summary) }
            }
        }
    }

    private func overviewCard(_ overview: DocumentSummary.Overview) -> some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            Text(overview.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if !overview.flaggedNumbers.isEmpty {
                flagLabel(overview.flaggedNumbers)
            }
        }
        .glassSurface()
        .accessibilityElement(children: .combine)
    }

    private func pointRow(_ point: DocumentSummary.Point, in summary: DocumentSummary) -> some View {
        let place = SummaryExport.whereLabel(point.locations, in: summary, l10n: l10n)
        return VStack(alignment: .leading, spacing: 6) {
            Text(point.text)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if !point.owner.isEmpty || !point.deadline.isEmpty {
                Text([point.owner.isEmpty ? "" : l10n.t("المسؤول: \(point.owner)", "Owner: \(point.owner)"),
                      point.deadline.isEmpty ? "" : l10n.t("الموعد: \(point.deadline)", "Deadline: \(point.deadline)")]
                    .filter { !$0.isEmpty }.joined(separator: l10n.t("، ", ", ")))
                    .font(.footnote.weight(.semibold))
            }
            HStack(spacing: BasirSpacing.s) {
                if let place {
                    Label(place, systemImage: "doc.text").font(.footnote).foregroundStyle(BasirPalette.secondaryText)
                }
                if !point.verified {
                    Label(l10n.t("غير مؤكد في النص", "Not confirmed in the text"), systemImage: "questionmark.circle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(BasirPalette.warning)
                }
            }
            if !point.flaggedNumbers.isEmpty { flagLabel(point.flaggedNumbers) }
            if workingFollowUp?.hasPrefix(point.id) == true {
                ProgressView(l10n.t("جارٍ الإجابة…", "Answering…"))
            }
            ForEach([FollowUpKind.explain, .simplify, .ask], id: \.rawValue) { kind in
                if let answer = answers[point.id + kind.rawValue] {
                    Text(answer)
                        .font(.callout)
                        .padding(BasirSpacing.s)
                        .background(BasirPalette.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(followUpTitle(kind) + ": " + answer)
                }
            }
            AdaptiveStack {
                if canOpen(point) {
                    CardActionButton(title: l10n.t("اذهب إلى الصفحة", "Go to the page"), systemImage: "arrow.right.doc.on.clipboard") {
                        open(point, in: summary)
                    }
                }
                Menu {
                    Button { followUp(point, .explain) } label: { Label(followUpTitle(.explain), systemImage: "text.magnifyingglass") }
                    Button { followUp(point, .simplify) } label: { Label(followUpTitle(.simplify), systemImage: "text.word.spacing") }
                    Button { questionText = ""; pendingQuestion = FollowUp(point: point, kind: .ask) } label: {
                        Label(followUpTitle(.ask), systemImage: "questionmark.bubble")
                    }
                } label: {
                    Label(l10n.t("المزيد عن هذه النقطة", "More on this point"), systemImage: "ellipsis.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
            }
        }
        .padding(BasirSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BasirPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(SummaryExport.describe(point, in: summary, l10n: l10n))
        .accessibilityAction(named: Text(l10n.t("اذهب إلى الصفحة", "Go to the page"))) { open(point, in: summary) }
        .accessibilityAction(named: Text(followUpTitle(.explain))) { followUp(point, .explain) }
        .accessibilityAction(named: Text(followUpTitle(.simplify))) { followUp(point, .simplify) }
        .accessibilityAction(named: Text(followUpTitle(.ask))) {
            questionText = ""
            pendingQuestion = FollowUp(point: point, kind: .ask)
        }
    }

    private func sectionRow(_ section: DocumentSummary.Section, in summary: DocumentSummary) -> some View {
        let expanded = expandedSections.contains(section.id)
        return VStack(alignment: .leading, spacing: BasirSpacing.s) {
            Text(section.title + SummaryExport.pages(of: section, in: summary, l10n: l10n))
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(section.summary)
                .fixedSize(horizontal: false, vertical: true)
            if !section.flaggedNumbers.isEmpty { flagLabel(section.flaggedNumbers) }
            AdaptiveStack {
                if section.firstPage > 0, summary.usesPages(file: section.file), canOpenPages {
                    CardActionButton(title: l10n.t("اذهب إلى الصفحة", "Go to the page"), systemImage: "arrow.right.doc.on.clipboard") {
                        openPage(section.firstPage, file: section.file)
                    }
                }
                if !section.points.isEmpty {
                    CardActionButton(title: expanded ? l10n.t("إخفاء التفاصيل", "Hide details")
                                                     : l10n.t("التفاصيل (\(section.points.count))", "Details (\(section.points.count))"),
                                     systemImage: expanded ? "chevron.up" : "chevron.down") {
                        if expanded { expandedSections.remove(section.id) } else { expandedSections.insert(section.id) }
                    }
                }
            }
            if expanded {
                ForEach(section.points) { point in pointRow(point, in: summary) }
            }
        }
        .glassSurface()
    }

    private func cards(_ summary: DocumentSummary) -> some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            SectionHeading(title: l10n.t("بطاقات المراجعة", "Study cards"))
            ForEach(summary.cards) { card in
                let revealed = revealedCards.contains(card.id)
                Button {
                    if revealed { revealedCards.remove(card.id) } else { revealedCards.insert(card.id) }
                    UIAccessibility.post(notification: .announcement, argument: revealed ? card.front : card.back)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(card.front).font(.headline).fixedSize(horizontal: false, vertical: true)
                        if revealed {
                            Text(card.back).fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(l10n.t("اضغط لإظهار الإجابة", "Tap to show the answer"))
                                .font(.footnote).foregroundStyle(BasirPalette.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(BasirSpacing.m)
                    .background(BasirPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint(revealed ? l10n.t("اضغط مرتين لإخفاء الإجابة", "Double-tap to hide the answer")
                                            : l10n.t("اضغط مرتين لإظهار الإجابة", "Double-tap to show the answer"))
            }
        }
    }

    private func quiz(_ summary: DocumentSummary) -> some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            SectionHeading(title: l10n.t("اختبر فهمك", "Test yourself"))
            ForEach(Array(summary.quiz.enumerated()), id: \.element.id) { number, question in
                VStack(alignment: .leading, spacing: BasirSpacing.s) {
                    Text("\(number + 1). \(question.question)")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(question.choices.enumerated()), id: \.offset) { index, choice in
                        let chosen = chosenAnswers[question.id]
                        Button {
                            chosenAnswers[question.id] = index
                            let right = index == question.answerIndex
                            UIAccessibility.post(notification: .announcement, argument: right
                                ? l10n.t("إجابة صحيحة. \(question.explanation)", "Correct. \(question.explanation)")
                                : l10n.t("إجابة غير صحيحة. الإجابة الصحيحة: \(question.choices[question.answerIndex])",
                                         "Not quite. The answer is: \(question.choices[question.answerIndex])"))
                        } label: {
                            HStack {
                                Text(choice).fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                if chosen == index {
                                    Image(systemName: index == question.answerIndex ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(index == question.answerIndex ? BasirPalette.success : BasirPalette.danger)
                                        .accessibilityHidden(true)
                                }
                            }
                            .padding(BasirSpacing.s)
                            .frame(minHeight: 44)
                            .background(BasirPalette.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(chosen == index ? .isSelected : [])
                    }
                    if let chosen = chosenAnswers[question.id] {
                        Text(chosen == question.answerIndex
                             ? l10n.t("إجابة صحيحة. \(question.explanation)", "Correct. \(question.explanation)")
                             : l10n.t("الإجابة الصحيحة: \(question.choices[question.answerIndex]). \(question.explanation)",
                                      "The answer: \(question.choices[question.answerIndex]). \(question.explanation)"))
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .glassSurface()
            }
        }
    }

    private func flagLabel(_ numbers: [String]) -> some View {
        Label(l10n.t("رقم لم يُعثر عليه في النص: \(numbers.joined(separator: "، "))",
                     "Number not found in the text: \(numbers.joined(separator: ", "))"),
              systemImage: "number.circle")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(BasirPalette.warning)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Menus and sheets

    private func actionsMenu(_ summary: DocumentSummary) -> some View {
        Menu {
            Button {
                if speaker.isSpeaking { speaker.stop() } else {
                    let passages = SummaryExport.spokenPassages(summary, title: source.title, l10n: l10n)
                    speaker.play(passages.enumerated().map { (id: $0.offset, text: $0.element) })
                }
            } label: {
                Label(speaker.isSpeaking ? l10n.t("إيقاف الاستماع", "Stop listening") : l10n.t("استمع إلى الملخص", "Listen to the summary"),
                      systemImage: speaker.isSpeaking ? "stop.fill" : "play.fill")
            }
            Button { showAudiobook = true } label: {
                Label(l10n.t("ملف صوتي للملخص", "Summary as an audio file"), systemImage: "waveform")
            }
            Divider()
            Button { exportWord(summary) } label: { Label(l10n.t("تصدير ملف Word", "Export as Word"), systemImage: "doc.richtext") }
            Button { export { try SummaryExport.pdf(summary, title: source.title, l10n: l10n) } } label: {
                Label(l10n.t("تصدير PDF", "Export as PDF"), systemImage: "doc.text")
            }
            Button { export { try SummaryExport.textFile(summary, title: source.title, l10n: l10n) } } label: {
                Label(l10n.t("مشاركة كنص", "Share as text"), systemImage: "square.and.arrow.up")
            }
            Divider()
            Button { showOptions = true } label: {
                Label(l10n.t("لغة الملخص ونوعه وبطاقات المراجعة", "Language, type and study cards"), systemImage: "slider.horizontal.3")
            }
        } label: {
            Label(l10n.t("خيارات الملخص", "Summary options"), systemImage: "ellipsis.circle")
        }
        .disabled(exporting)
    }

    private var optionsSheet: some View {
        NavigationStack {
            Form {
                Section(l10n.t("لغة الملخص", "Summary language")) {
                    Picker(l10n.t("لغة الملخص", "Summary language"), selection: $language) {
                        Text("العربية").tag("ar")
                        Text("English").tag("en")
                    }
                    .pickerStyle(.segmented)
                    Text(l10n.t("اختر لغة الملخص، حتى لو كانت مختلفة عن لغة المستند.", "The summary is written in this language whatever the document’s language."))
                        .font(.footnote).foregroundStyle(BasirPalette.secondaryText)
                }
                if !isSeveralFiles {
                    Section(l10n.t("نوع المستند", "Document type")) {
                        Picker(l10n.t("نوع المستند", "Document type"), selection: $template) {
                            ForEach(SummaryTemplate.singleDocumentChoices) { item in Text(item.title(l10n)).tag(item) }
                        }
                        Text(l10n.t("يساعد نوع المستند بصير على اختيار عناوين الملخص. في العقود مثلًا، يجمع الالتزامات والغرامات تحت عناوين مستقلة.",
                                    "Basir arranges the summary under headings that suit the document type, such as obligations and penalties in a contract."))
                            .font(.footnote).foregroundStyle(BasirPalette.secondaryText)
                    }
                }
                Section {
                    Toggle(l10n.t("بطاقات مراجعة واختبار قصير", "Study cards and a short quiz"), isOn: $includeStudy)
                }
                Section {
                    Button(l10n.t("إعادة التلخيص بهذه الخيارات", "Summarize again with these options")) {
                        showOptions = false
                        summarize()
                    }
                    .fontWeight(.semibold)
                }
            }
            .navigationTitle(l10n.t("خيارات الملخص", "Summary options"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(l10n.t("تم", "Done")) { showOptions = false } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func questionSheet(_ followUp: FollowUp) -> some View {
        NavigationStack {
            Form {
                Section(l10n.t("النقطة", "The point")) { Text(followUp.point.text) }
                Section(l10n.t("سؤالك", "Your question")) {
                    TextField(l10n.t("اكتب سؤالك عن هذه النقطة", "Ask about this point"), text: $questionText, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section {
                    Button(l10n.t("اسأل", "Ask")) {
                        let question = questionText.trimmingCharacters(in: .whitespacesAndNewlines)
                        pendingQuestion = nil
                        guard !question.isEmpty else { return }
                        self.followUp(followUp.point, .ask, question: question)
                    }
                    .disabled(questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle(followUpTitle(.ask))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(l10n.t("إلغاء", "Cancel")) { pendingQuestion = nil } }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Actions

    private func followUpTitle(_ kind: FollowUpKind) -> String {
        switch kind {
        case .explain: return l10n.t("اشرح أكثر", "Explain more")
        case .simplify: return l10n.t("بسّطها", "Simplify")
        case .ask: return l10n.t("اسأل عنها", "Ask about it")
        }
    }

    /// Follow-ups answer from the document itself, through Ask the document (ت13).
    private func followUp(_ point: DocumentSummary.Point, _ kind: FollowUpKind, question: String = "") {
        let key = point.id + kind.rawValue
        guard workingFollowUp == nil else { return }
        let asked: String
        switch kind {
        case .explain:
            asked = l10n.t("اشرح هذه النقطة من المستند بتفصيل أكبر وبكلمات واضحة: «\(point.text)»",
                           "Explain this point from the document in more detail and in clear words: “\(point.text)”")
        case .simplify:
            asked = l10n.t("أعد صياغة هذه النقطة بكلمات بسيطة جدًا وجمل قصيرة: «\(point.text)»",
                           "Restate this point in very simple words and short sentences: “\(point.text)”")
        case .ask:
            asked = l10n.t("بخصوص هذه النقطة من المستند: «\(point.text)». \(question)",
                           "About this point in the document: “\(point.text)”. \(question)")
        }
        workingFollowUp = key
        let body = AssistRequestBody(task: .ask, language: runner.summary?.language ?? (l10n.isArabic ? "ar" : "en"),
                                     text: String(source.questionText.prefix(DocumentAssistant.maximumCharacters)),
                                     question: asked, title: source.title)
        Task {
            defer { workingFollowUp = nil }
            do {
                let answer = try await DocumentAssistant.send(body, as: AskAnswer.self, configuration: settings.configuration)
                answers[key] = answer.answer
                UIAccessibility.post(notification: .announcement, argument: answer.answer)
            } catch {
                let message = DocumentAssistant.message(for: error, l10n: l10n)
                answers[key] = message
                UIAccessibility.post(notification: .announcement, argument: message)
            }
        }
    }

    private var canOpenPages: Bool { onJump != nil || source.outputURL != nil }

    private func canOpen(_ point: DocumentSummary.Point) -> Bool {
        canOpenPages && (!point.locations.isEmpty || !point.quote.isEmpty)
    }

    /// Goes to the point in the reader: its exact passage when found, else its page (ت12).
    private func open(_ point: DocumentSummary.Point, in summary: DocumentSummary) {
        if let onJump, !source.blocks.isEmpty {
            if !point.quote.isEmpty, let id = DocumentAssistant.blockID(containing: point.quote, in: source.blocks) {
                close(then: id, jump: onJump)
                return
            }
            if let page = point.locations.first?.page,
               let id = source.blocks.first(where: { $0.pageNumber == page })?.id {
                close(then: id, jump: onJump)
                return
            }
        }
        if let location = point.locations.first {
            openPage(location.page, file: location.file)
        }
    }

    private func openPage(_ page: Int, file: Int) {
        if let onJump, let id = source.blocks.first(where: { $0.pageNumber == page })?.id {
            close(then: id, jump: onJump)
        } else if let url = source.outputURL {
            readerPage = ReaderTarget(url: url, page: page)
        }
    }

    private func close(then id: Int, jump: @escaping (Int) -> Void) {
        speaker.stop()
        dismiss()
        jump(id)
    }

    private func exportWord(_ summary: DocumentSummary) {
        export {
            let data = try summary.encoded()
            let document = try await ProxyClient(configuration: settings.configuration)
                .summaryDocument(summary: data, title: SummaryExport.fileName(source.title, l10n: l10n))
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(SummaryExport.fileName(source.title, l10n: l10n)).appendingPathExtension("docx")
            try document.write(to: url, options: .atomic)
            return url
        }
    }

    private func export(_ make: @escaping @MainActor () async throws -> URL) {
        exporting = true
        exportError = nil
        Task {
            defer { exporting = false }
            do {
                shareURL = try await make()
            } catch {
                exportError = DocumentAssistant.message(for: error, l10n: l10n)
            }
        }
    }

    private func templateTitle(_ summary: DocumentSummary) -> String {
        let kind = SummaryTemplate(rawValue: summary.template) ?? .general
        return l10n.t("نوع الملخص: \(kind.title(l10n))", "Summary type: \(kind.title(l10n))")
    }

    private func languageName(_ code: String) -> String {
        code == "ar" ? l10n.t("العربية", "Arabic") : l10n.t("الإنجليزية", "English")
    }

    private func close() {
        speaker.stop()
        dismiss()
    }
}

private struct ShareTarget: Identifiable {
    let url: URL
    var id: String { url.path }
}

struct ReaderTarget: Identifiable {
    let url: URL
    let page: Int
    var id: String { "\(url.path)#\(page)" }
}
