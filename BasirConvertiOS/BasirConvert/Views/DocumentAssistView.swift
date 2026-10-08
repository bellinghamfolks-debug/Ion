import SwiftUI
import UIKit

/// "Ask Basir" inside the reader: free questions, "what does it ask of me?",
/// dates to the calendar. Every answer is announced, and quoted passages
/// can be opened in the document.
struct DocumentAssistView: View {
    enum Mode: Hashable {
        case ask, brief, dates
    }

    let title: String
    let blocks: [ReaderBlock]
    let initialMode: Mode
    let onJump: (Int) -> Void

    init(title: String, blocks: [ReaderBlock], initialMode: Mode = .ask, onJump: @escaping (Int) -> Void) {
        self.title = title
        self.blocks = blocks
        self.initialMode = initialMode
        self.onJump = onJump
        _mode = State(initialValue: initialMode)
    }

    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode
    @State private var question = ""
    @State private var exchanges: [(question: String, answer: AskAnswer)] = []
    @State private var brief: DocumentBrief?
    @State private var events: [DocumentEvent]?
    @State private var chosenEvents: Set<String> = []
    @State private var working = false
    @State private var errorText: String?
    @State private var calendarMessage: String?
    @FocusState private var questionFocused: Bool

    private var documentText: String { DocumentAssistant.text(of: blocks) }
    private var language: String { l10n.isArabic ? "ar" : "en" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BasirSpacing.l) {
                    Picker(l10n.t("النوع", "Kind"), selection: $mode) {
                        Text(l10n.t("اسأل", "Ask")).tag(Mode.ask)
                        Text(l10n.t("ماذا يطلب مني؟", "What it asks")).tag(Mode.brief)
                        Text(l10n.t("المواعيد", "Dates")).tag(Mode.dates)
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .ask: askSection
                    case .brief: briefSection
                    case .dates: datesSection
                    }
                    if working {
                        ProgressView(l10n.t("بصير يقرأ المستند…", "Basir is reading the document…"))
                            .frame(maxWidth: .infinity)
                    }
                    if let errorText { InlineMessage(text: errorText, isError: true) }
                    Text(l10n.t("تأتي الإجابات من نص هذا المستند فقط، ويُرسل النص إلى خادم بصير لهذا الطلب ولا يُحفظ.",
                                "Answers come only from this document's text, which is sent to the Basir server for this request and not kept."))
                        .font(.footnote)
                        .foregroundStyle(BasirPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .appScreenContent()
            }
            .background(BasirPalette.background.ignoresSafeArea())
            .foregroundStyle(BasirPalette.primaryText)
            .navigationTitle(l10n.t("اسأل بصير", "Ask Basir"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(l10n.t("تم", "Done")) { dismiss() }
                }
            }
        }
        .escapeToDismiss { dismiss() }
        .onAppear {
            if initialMode == .ask { questionFocused = true }
        }
        .onChange(of: mode) { newMode in
            errorText = nil
            if newMode == .brief, brief == nil { loadBrief() }
            if newMode == .dates, events == nil { loadDates() }
        }
        .task {
            if initialMode == .brief { loadBrief() }
            if initialMode == .dates { loadDates() }
        }
    }

    // MARK: Ask

    private var askSection: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            TextField(l10n.t("اكتب سؤالك أو استخدم الإملاء", "Type your question or dictate it"),
                      text: $question, axis: .vertical)
                .lineLimit(1...4)
                .focused($questionFocused)
                .submitLabel(.send)
                .onSubmit(ask)
                .padding(12)
                .background(BasirPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(BasirPalette.stroke) }
            PrimaryActionButton(title: l10n.t("اسأل", "Ask"), systemImage: "questionmark.bubble.fill", action: ask)
                .disabled(working || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if exchanges.isEmpty {
                VStack(alignment: .leading, spacing: BasirSpacing.s) {
                    Text(l10n.t("أمثلة", "Examples")).font(.subheadline.weight(.semibold))
                    ForEach(examples, id: \.self) { example in
                        Button { question = example; ask() } label: {
                            Label(example, systemImage: "text.bubble")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .disabled(working)
                    }
                }
            }
            ForEach(Array(exchanges.enumerated().reversed()), id: \.offset) { _, exchange in
                answerCard(question: exchange.question, answer: exchange.answer)
            }
        }
    }

    private var examples: [String] {
        [l10n.t("ما المبلغ المطلوب؟", "What amount is due?"),
         l10n.t("ما آخر موعد؟", "What is the deadline?"),
         l10n.t("لخّص المستند في ثلاث جمل", "Summarize in three sentences")]
    }

    private func answerCard(question: String, answer: AskAnswer) -> some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            Text(question)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BasirPalette.secondaryText)
                .accessibilityLabel(l10n.t("سؤالك: ", "Your question: ") + question)
            Text(answer.answer)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            ForEach(answer.quotes, id: \.self) { quote in
                quoteButton(quote)
            }
        }
        .glassSurface()
    }

    private func quoteButton(_ quote: String) -> some View {
        let target = DocumentAssistant.blockID(containing: quote, in: blocks)
        return Button {
            if let target { dismiss(); onJump(target) }
        } label: {
            HStack(alignment: .top, spacing: BasirSpacing.s) {
                Image(systemName: "text.quote").accessibilityHidden(true)
                Text("«\(quote)»").fixedSize(horizontal: false, vertical: true)
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(target == nil)
        .accessibilityLabel(l10n.t("من المستند: ", "From the document: ") + quote)
        .accessibilityHint(target == nil ? "" : l10n.t("يفتح هذا الموضع في المستند", "Opens this place in the document"))
    }

    private func ask() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !working else { return }
        run {
            let answer = try await DocumentAssistant.send(
                AssistRequestBody(task: .ask, language: language, text: documentText, question: text, title: title),
                as: AskAnswer.self, configuration: settings.configuration)
            exchanges.append((text, answer))
            question = ""
            announce(answer.answer)
        }
    }

    // MARK: Brief

    @ViewBuilder
    private var briefSection: some View {
        if let brief {
            VStack(alignment: .leading, spacing: BasirSpacing.m) {
                Text(brief.documentType)
                    .font(.title3.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text(brief.summary).fixedSize(horizontal: false, vertical: true)
                briefList(l10n.t("المطلوب منك", "What you need to do"), items: brief.requests.map { request in
                    [request.action,
                     request.deadline.isEmpty ? "" : l10n.t("الموعد: ", "By: ") + request.deadline,
                     request.details].filter { !$0.isEmpty }.joined(separator: l10n.isArabic ? "، " : ", ")
                })
                briefList(l10n.t("المبالغ", "Amounts"), items: brief.amounts.map { "\($0.label): \($0.value)" })
                briefList(l10n.t("الأوراق المطلوبة", "Documents needed"), items: brief.documentsNeeded)
                briefList(l10n.t("للتواصل", "Contacts"), items: brief.contacts)
                briefList(l10n.t("تنبيهات", "Warnings"), items: brief.warnings)
                if brief.requests.contains(where: { !$0.deadline.isEmpty }) {
                    SecondaryActionButton(title: l10n.t("أضف المواعيد إلى التقويم", "Add the dates to Calendar"),
                                          systemImage: "calendar.badge.plus") { mode = .dates }
                }
            }
            .glassSurface()
        }
    }

    @ViewBuilder
    private func briefList(_ heading: String, items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: BasirSpacing.xs) {
                Text(heading).font(.headline).accessibilityAddTraits(.isHeader)
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: BasirSpacing.s) {
                        Text("•").accessibilityHidden(true)
                        Text(item).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func loadBrief() {
        run {
            let result = try await DocumentAssistant.send(
                AssistRequestBody(task: .brief, language: language, text: documentText, title: title),
                as: DocumentBrief.self, configuration: settings.configuration)
            brief = result
            let count = result.requests.count
            announce(l10n.t("\(result.documentType). \(result.summary) المطلوب منك \(count) أمور.",
                            "\(result.documentType). \(result.summary) \(count) things to do."))
        }
    }

    // MARK: Dates

    @ViewBuilder
    private var datesSection: some View {
        if let events {
            VStack(alignment: .leading, spacing: BasirSpacing.m) {
                if events.isEmpty {
                    InfoCard(title: l10n.t("لا مواعيد في هذا المستند", "No dates in this document"),
                             text: l10n.t("لم يجد بصير مواعيد أو آخر مواعيد للتقويم.", "Basir found no appointments or deadlines."),
                             systemImage: "calendar")
                } else {
                    ForEach(events) { event in eventRow(event) }
                    PrimaryActionButton(title: l10n.t("أضف \(chosenEvents.count) إلى التقويم", "Add \(chosenEvents.count) to Calendar"),
                                        systemImage: "calendar.badge.plus") { addToCalendar(events) }
                        .disabled(chosenEvents.isEmpty || working)
                }
                if let calendarMessage { InlineMessage(text: calendarMessage, isError: false) }
            }
        }
    }

    private func eventRow(_ event: DocumentEvent) -> some View {
        let chosen = chosenEvents.contains(event.id)
        return Button {
            if chosen { chosenEvents.remove(event.id) } else { chosenEvents.insert(event.id) }
        } label: {
            HStack(alignment: .top, spacing: BasirSpacing.m) {
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(chosen ? BasirPalette.accent : BasirPalette.tertiaryText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(when(event)).font(.subheadline)
                    if !event.location.isEmpty {
                        Text(event.location).font(.footnote).foregroundStyle(BasirPalette.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .glassSurface(padding: BasirSpacing.m)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(chosen ? l10n.t("محدد للإضافة. اضغط مرتين لإلغاء التحديد.", "Selected. Double-tap to deselect.")
                                  : l10n.t("اضغط مرتين لتحديده.", "Double-tap to select."))
    }

    private func when(_ event: DocumentEvent) -> String {
        guard let start = event.start else { return event.date }
        let day = start.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(l10n.locale))
        if event.isAllDay { return day }
        return day + l10n.t("، الساعة ", ", ") + start.formatted(.dateTime.hour().minute().locale(l10n.locale))
    }

    private func loadDates() {
        run {
            let result = try await DocumentAssistant.send(
                AssistRequestBody(task: .dates, language: language, text: documentText, title: title,
                                  today: DocumentAssistant.today()),
                as: DocumentEvents.self, configuration: settings.configuration)
            let usable = result.events.filter { $0.start != nil }
            events = usable
            chosenEvents = Set(usable.map(\.id))
            announce(usable.isEmpty ? l10n.t("لا مواعيد في هذا المستند", "No dates in this document")
                                    : l10n.t("وجد بصير \(usable.count) مواعيد، كلها محددة للإضافة.",
                                             "Basir found \(usable.count) dates, all selected."))
        }
    }

    private func addToCalendar(_ events: [DocumentEvent]) {
        let chosen = events.filter { chosenEvents.contains($0.id) }
        working = true
        Task {
            let outcome = await CalendarWriter.add(chosen, sourceTitle: title)
            working = false
            switch outcome {
            case .added(let count):
                calendarMessage = l10n.t("أُضيف \(count) إلى التقويم مع تذكير.", "\(count) added to Calendar with a reminder.")
                OperationFeedback.selectionChanged()
            case .denied:
                calendarMessage = l10n.t("لم يُسمح لبصير بالإضافة إلى التقويم. يمكنك السماح من الإعدادات > بصير > التقويمات.",
                                         "Basir is not allowed to add to Calendar. Allow it in Settings > Basir > Calendars.")
            case .failed:
                calendarMessage = l10n.t("تعذرت الإضافة إلى التقويم.", "Could not add to Calendar.")
            }
            announce(calendarMessage ?? "")
        }
    }

    // MARK: Shared

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        working = true
        errorText = nil
        Task { @MainActor in
            defer { working = false }
            do {
                try await work()
            } catch {
                errorText = DocumentAssistant.message(for: error, l10n: l10n)
                announce(errorText ?? "")
            }
        }
    }

    private func announce(_ text: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            UIAccessibility.post(notification: .announcement, argument: text)
        }
    }
}

/// "Explain this table": what it shows, what the columns mean, what stands out.
struct TableExplanationView: View {
    let rows: [[String]]
    let context: String

    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var explanation: TableExplanation?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BasirSpacing.m) {
                    if let explanation {
                        Text(explanation.overview).fixedSize(horizontal: false, vertical: true)
                        section(l10n.t("الأعمدة", "Columns"), explanation.columns.map { "\($0.name): \($0.meaning)" })
                        section(l10n.t("أبرز ما فيه", "What stands out"), explanation.highlights)
                        section(l10n.t("المجاميع", "Totals"), explanation.totals)
                    } else if let errorText {
                        InlineMessage(text: errorText, isError: true)
                    } else {
                        ProgressView(l10n.t("بصير يقرأ الجدول…", "Basir is reading the table…"))
                            .frame(maxWidth: .infinity, minHeight: 160)
                    }
                }
                .appScreenContent()
            }
            .background(BasirPalette.background.ignoresSafeArea())
            .foregroundStyle(BasirPalette.primaryText)
            .navigationTitle(l10n.t("شرح الجدول", "Table explained"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(l10n.t("تم", "Done")) { dismiss() } }
            }
        }
        .escapeToDismiss { dismiss() }
        .presentationDetents([.medium, .large])
        .task { await load() }
    }

    @ViewBuilder
    private func section(_ heading: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            Text(heading).font(.headline).accessibilityAddTraits(.isHeader)
            ForEach(items, id: \.self) { item in
                Text("• " + item).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func load() async {
        do {
            let result = try await DocumentAssistant.send(
                AssistRequestBody(task: .table, language: l10n.isArabic ? "ar" : "en", text: context, table: rows),
                as: TableExplanation.self, configuration: settings.configuration)
            explanation = result
            UIAccessibility.post(notification: .announcement, argument: result.overview)
        } catch {
            errorText = DocumentAssistant.message(for: error, l10n: l10n)
            UIAccessibility.post(notification: .announcement, argument: errorText ?? "")
        }
    }
}
