import SwiftUI
import AVFoundation
import ImageIO
import UIKit

/// Reads a Basir Word result inside the app, built for VoiceOver first:
/// headings are headings, every table row is read with its column names,
/// rotors jump between tables, images, pages and bookmarks, and the place
/// the person stopped is kept for next time. It can also read aloud.
struct DocumentReaderView: View {
    /// The Word file, or nil for text read on the phone (instant read).
    let url: URL?
    private let preloaded: [ReaderBlock]?
    private let givenTitle: String

    init(url: URL) {
        self.url = url
        preloaded = nil
        givenTitle = url.deletingPathExtension().lastPathComponent
    }

    init(title: String, blocks: [ReaderBlock]) {
        url = nil
        preloaded = blocks
        givenTitle = title
    }

    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speaker = ReaderSpeaker()
    @StateObject private var translator = BilingualTranslator()
    @StateObject private var audiobook = AudiobookExporter()
    @AppStorage("reader.maskSensitive") private var maskSensitive = false
    @State private var rawBlocks: [ReaderBlock] = []
    @State private var blocks: [ReaderBlock] = []
    @State private var bilingual = false
    @State private var showAudiobook = false
    @State private var loading = true
    @State private var bookmarks: [Int] = []
    /// Blocks on screen. A reference, so scrolling does not redraw the reader.
    @State private var visibility = VisibleBlocks()
    @State private var position = 0
    /// Page mode: one page per screen with Previous and Next.
    @AppStorage("reader.paged") private var paged = true
    @State private var readerPages: [ReaderPage] = []
    @State private var currentPage = 0
    /// Images decoded once, off the main thread, at screen size.
    @State private var decodedImages: [Int: UIImage] = [:]
    @State private var readerIndex = ReaderIndex()
    @AccessibilityFocusState private var pageHeaderFocused: Bool
    @State private var resumeFrom: Int?
    @State private var showContents = false
    @State private var pendingJump: Int?
    @State private var assistMode: DocumentAssistView.Mode?
    @State private var explainedTable: ReaderBlock?
    @AccessibilityFocusState private var focusedID: Int?
    @Namespace private var rotorSpace

    private var memory: ReaderMemory { ReaderMemory(fileName: url?.lastPathComponent ?? "instant") }
    private var remembers: Bool { url != nil }
    private var title: String { givenTitle }
    // Worked out once per load, not on every redraw.
    private var tables: [ReaderBlock] { readerIndex.tables }
    private var images: [ReaderBlock] { readerIndex.images }
    private var pages: [ReaderBlock] { readerIndex.pages }
    private var headings: [ReaderBlock] { readerIndex.headings }
    private var marked: [ReaderBlock] { bookmarks.compactMap { id in blocks.indices.contains(id) ? blocks[id] : nil } }

    private var isPaging: Bool { paged && readerPages.count > 1 }

    /// The blocks drawn now: the current page, or the whole document.
    private var shownBlocks: ArraySlice<ReaderBlock> {
        guard isPaging, readerPages.indices.contains(currentPage) else { return blocks[...] }
        let range = readerPages[currentPage].range.clamped(to: blocks.indices)
        // The page header replaces the document's own "Page N" line.
        return blocks[range]
    }

    private var pageTitle: String {
        guard readerPages.indices.contains(currentPage) else { return "" }
        let page = readerPages[currentPage]
        let count = readerPages.count
        if let printed = page.printedNumber, printed != page.index + 1 {
            return l10n.t("الصفحة \(printed) (\(page.index + 1) من \(count))", "Page \(printed) (\(page.index + 1) of \(count))")
        }
        return l10n.t("الصفحة \(page.index + 1) من \(count)", "Page \(page.index + 1) of \(count)")
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: BasirSpacing.m) {
                        if loading {
                            ProgressView(l10n.t("جارٍ فتح الملف", "Opening the file"))
                                .frame(maxWidth: .infinity, minHeight: 200)
                        } else if blocks.isEmpty {
                            InfoCard(title: l10n.t("لا يوجد نص لعرضه", "Nothing to read"),
                                     text: l10n.t("لم يجد بصير نصًا في هذا الملف. جرّب المعاينة.",
                                                  "Basir found no text in this file. Try Preview."),
                                     systemImage: "doc.text.magnifyingglass")
                        } else {
                            if let resume = resumeFrom { resumeCard(resume, proxy: proxy) }
                            if isPaging { pageHeader(proxy: proxy) }
                            ForEach(shownBlocks) { block in
                                if !(isPaging && block.pageNumber != nil) {
                                    row(block, proxy: proxy)
                                        .id(block.id)
                                        .accessibilityRotorEntry(id: block.id, in: rotorSpace)
                                        .accessibilityFocused($focusedID, equals: block.id)
                                        .onAppear { visibility.ids.insert(block.id); trackTop() }
                                        .onDisappear { visibility.ids.remove(block.id); trackTop() }
                                }
                            }
                            if isPaging { pageFooter(proxy: proxy) }
                        }
                    }
                    .appScreenContent(bottomPadding: 120)
                }
                .accessibilityRotor(Text(l10n.t("الجداول", "Tables"))) {
                    ForEach(tables) { block in
                        AccessibilityRotorEntry(Text(tableLabel(block)), id: block.id, in: rotorSpace) {
                            reveal(block.id, proxy: proxy)
                        }
                    }
                }
                .accessibilityRotor(Text(l10n.t("الصور", "Images"))) {
                    ForEach(images) { block in
                        AccessibilityRotorEntry(Text(imageLabel(block)), id: block.id, in: rotorSpace) {
                            reveal(block.id, proxy: proxy)
                        }
                    }
                }
                .accessibilityRotor(Text(l10n.t("الصفحات", "Pages"))) {
                    ForEach(pages) { block in
                        AccessibilityRotorEntry(Text(pageLabel(block)), id: block.id, in: rotorSpace) {
                            reveal(block.id, proxy: proxy)
                        }
                    }
                }
                .accessibilityRotor(Text(l10n.t("العلامات", "Bookmarks"))) {
                    ForEach(marked) { block in
                        AccessibilityRotorEntry(Text(excerpt(block)), id: block.id, in: rotorSpace) {
                            reveal(block.id, proxy: proxy)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) { controls(proxy: proxy) }
                .onChange(of: speaker.speakingID) { id in
                    guard let id else { return }
                    position = id
                    follow(id, proxy: proxy)
                }
                .onChange(of: focusedID) { id in
                    if let id { position = id }
                }
                .onChange(of: pendingJump) { id in
                    guard let id else { return }
                    pendingJump = nil
                    jump(to: id, proxy: proxy)
                }
            }
            .background(BasirPalette.background.ignoresSafeArea())
            .foregroundStyle(BasirPalette.primaryText)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(l10n.t("تم", "Done")) { close() }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button { assistMode = .brief } label: {
                            Label(l10n.t("ماذا يطلب مني؟", "What does it ask of me?"), systemImage: "checklist")
                        }
                        Button { assistMode = .dates } label: {
                            Label(l10n.t("أضف المواعيد إلى التقويم", "Add dates to Calendar"), systemImage: "calendar.badge.plus")
                        }
                        Button { assistMode = .ask } label: {
                            Label(l10n.t("اسأل عن المستند", "Ask about the document"), systemImage: "questionmark.bubble")
                        }
                        Divider()
                        Button { toggleBilingual() } label: {
                            Label(bilingual ? l10n.t("أوقف القراءة ثنائية اللغة", "Turn off bilingual reading")
                                            : l10n.t("قراءة ثنائية اللغة", "Bilingual reading"),
                                  systemImage: "character.bubble")
                        }
                        Button { togglePaging() } label: {
                            Label(paged ? l10n.t("اعرض المستند كاملًا متصلًا", "Show the whole document as one scroll")
                                        : l10n.t("اقرأ صفحة صفحة", "Read page by page"),
                                  systemImage: paged ? "doc.plaintext" : "book.pages")
                        }
                        Button { showAudiobook = true } label: {
                            Label(l10n.t("احفظ كملف صوتي", "Save as audiobook"), systemImage: "waveform")
                        }
                        Button { maskSensitive.toggle(); applyMask(); announceMask() } label: {
                            Label(maskSensitive ? l10n.t("أظهر الأرقام الحساسة", "Show sensitive numbers")
                                                : l10n.t("أخفِ الأرقام الحساسة", "Hide sensitive numbers"),
                                  systemImage: maskSensitive ? "eye" : "eye.slash")
                        }
                    } label: {
                        Label(l10n.t("بصير", "Basir"), systemImage: "sparkles")
                    }
                    .disabled(blocks.isEmpty)
                }
            }
            .sheet(isPresented: $showContents) { contentsSheet }
            .sheet(item: Binding(get: { assistMode.map(AssistSheet.init) }, set: { assistMode = $0?.mode })) { sheet in
                DocumentAssistView(title: title, blocks: blocks, initialMode: sheet.mode) { id in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { pendingJump = id }
                }
            }
            .sheet(item: $explainedTable) { block in
                TableExplanationView(rows: block.rows, context: context(around: block))
            }
            .sheet(isPresented: $showAudiobook) {
                AudiobookExportView(exporter: audiobook, title: title, passages: audiobookPassages)
            }
        }
        .escapeToDismiss { close() }
        .task { await load() }
        .onDisappear {
            speaker.stop()
            audiobook.cancel()
            if remembers, !blocks.isEmpty { memory.position = position }
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ block: ReaderBlock, proxy: ScrollViewProxy) -> some View {
        if bilingual, Self.translatable(block) {
            VStack(alignment: .leading, spacing: BasirSpacing.xs) {
                decoratedRow(block)
                translationView(block)
            }
            .onAppear { translator.need(block.id, text: block.text) }
        } else {
            decoratedRow(block)
        }
    }

    private static func translatable(_ block: ReaderBlock) -> Bool {
        guard block.pageNumber == nil else { return false }
        switch block.kind {
        case .heading, .paragraph, .listItem, .link: return !block.text.isEmpty
        default: return false
        }
    }

    @ViewBuilder
    private func translationView(_ block: ReaderBlock) -> some View {
        if let translated = translator.translations[block.id] {
            Text(translated)
                .font(.callout)
                .foregroundStyle(BasirPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, BasirSpacing.s)
                .overlay(alignment: .leading) {
                    Rectangle().fill(BasirPalette.accent.opacity(0.5)).frame(width: 2)
                }
                .environment(\.layoutDirection, translator.target == "ar" ? .rightToLeft : .leftToRight)
                .accessibilityLabel(l10n.t("الترجمة: ", "Translation: ") + translated)
        } else if translator.failed {
            EmptyView()
        } else {
            ProgressView()
                .accessibilityLabel(l10n.t("جارٍ الترجمة", "Translating"))
        }
    }

    @ViewBuilder
    private func decoratedRow(_ block: ReaderBlock) -> some View {
        let isMarked = bookmarks.contains(block.id)
        let isSpeaking = speaker.speakingID == block.id
        blockContent(block)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(isSpeaking ? 8 : 0)
            .background(isSpeaking ? BasirPalette.accent.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if isMarked {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(BasirPalette.accent)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityValue(isMarked ? l10n.t("عليه علامة", "Bookmarked") : "")
            .accessibilityAction(named: isMarked ? l10n.t("إزالة العلامة", "Remove bookmark")
                                                 : l10n.t("ضع علامة هنا", "Bookmark here")) {
                toggleBookmark(block.id)
            }
            .accessibilityAction(named: l10n.t("اقرأ بصوت عالٍ من هنا", "Read aloud from here")) {
                play(from: block.id)
            }
            .modifier(TableActionModifier(isTable: block.kind == .table, title: l10n.t("اشرح الجدول", "Explain this table")) {
                explainedTable = block
            })
            .contextMenu {
                Button { toggleBookmark(block.id) } label: {
                    Label(isMarked ? l10n.t("إزالة العلامة", "Remove bookmark") : l10n.t("ضع علامة هنا", "Bookmark here"),
                          systemImage: isMarked ? "bookmark.slash" : "bookmark")
                }
                Button { play(from: block.id) } label: {
                    Label(l10n.t("اقرأ بصوت عالٍ من هنا", "Read aloud from here"), systemImage: "play.fill")
                }
            }
    }

    @ViewBuilder
    private func blockContent(_ block: ReaderBlock) -> some View {
        switch block.kind {
        case .heading(let level):
            if let page = block.pageNumber {
                HStack(spacing: BasirSpacing.s) {
                    Rectangle().fill(BasirPalette.stroke).frame(height: 1)
                    Text(l10n.t("الصفحة \(page)", "Page \(page)"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(BasirPalette.secondaryText)
                        .fixedSize()
                    Rectangle().fill(BasirPalette.stroke).frame(height: 1)
                }
                .padding(.top, BasirSpacing.s)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(pageLabel(block))
                .accessibilityAddTraits(.isHeader)
            } else {
                Text(block.text)
                    .font(level <= 1 ? .title2.weight(.bold) : level == 2 ? .title3.weight(.bold) : .headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, level <= 2 ? BasirSpacing.s : 0)
                    .accessibilityAddTraits(.isHeader)
            }
        case .paragraph:
            if let page = block.pageNumber {
                Text(l10n.t("الصفحة \(page)", "Page \(page)"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BasirPalette.secondaryText)
                    .accessibilityLabel(pageLabel(block))
                    .accessibilityAddTraits(.isHeader)
            } else {
                Text(block.text)
                    .font(.body)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        case .listItem(let ordered, let level):
            HStack(alignment: .firstTextBaseline, spacing: BasirSpacing.s) {
                Text(ordered ? "–" : "•").accessibilityHidden(true)
                Text(block.text).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(level) * 16)
            .accessibilityElement(children: .combine)
        case .table:
            VStack(alignment: .leading, spacing: BasirSpacing.s) {
                ReaderTableView(rows: block.rows, summary: tableLabel(block))
                Button { explainedTable = block } label: {
                    Label(l10n.t("اشرح الجدول", "Explain this table"), systemImage: "tablecells.badge.ellipsis")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .tint(BasirPalette.accent)
            }
        case .image:
            VStack(alignment: .leading, spacing: BasirSpacing.xs) {
                if let image = decodedImages[block.id] {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                if !block.text.isEmpty {
                    Text(block.text)
                        .font(.footnote)
                        .foregroundStyle(BasirPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(imageLabel(block))
            .accessibilityAddTraits(.isImage)
        case .math:
            Text(block.text)
                .font(.body.monospaced())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(l10n.t("معادلة: ", "Equation: ") + block.text)
        case .link:
            Text(block.text)
                .underline()
                .foregroundStyle(BasirPalette.accent)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func resumeCard(_ id: Int, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            Text(l10n.t("توقفت سابقًا عند: \(excerpt(blocks[id]))", "You stopped at: \(excerpt(blocks[id]))"))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            AdaptiveStack {
                CardActionButton(title: l10n.t("تابع من حيث توقفت", "Continue where you stopped"),
                                 systemImage: "arrow.uturn.forward", prominent: true) {
                    resumeFrom = nil
                    jump(to: id, proxy: proxy)
                }
                CardActionButton(title: l10n.t("من البداية", "From the start"), systemImage: "arrow.up.to.line") {
                    resumeFrom = nil
                    if remembers { memory.position = 0 }
                    focusedID = blocks.first?.id
                }
            }
        }
        .glassSurface()
    }

    // MARK: Controls

    private func controls(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: BasirSpacing.xs) {
            if isPaging { pager(proxy: proxy) }
            mainControls
        }
        .padding(.horizontal, BasirSpacing.l)
        .padding(.vertical, BasirSpacing.s)
        .background(.ultraThinMaterial)
        .disabled(blocks.isEmpty)
    }

    /// Previous, where you are, Next. The middle is adjustable with VoiceOver:
    /// swipe up or down on it to turn the page.
    private func pager(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: BasirSpacing.s) {
            CardActionButton(title: l10n.t("السابقة", "Previous"), systemImage: "chevron.backward") { turnPage(-1, proxy: proxy) }
                .disabled(currentPage == 0)
                .opacity(currentPage == 0 ? 0.45 : 1)
                .accessibilityLabel(l10n.t("الصفحة السابقة", "Previous page"))
            Text(pageTitle)
                .font(.footnote.weight(.semibold).monospacedDigit())
                .multilineTextAlignment(.center)
                .frame(minWidth: 70)
                .accessibilityLabel(pageTitle)
                .accessibilityHint(l10n.t("اسحب لأعلى أو لأسفل لتقليب الصفحات", "Swipe up or down to turn pages"))
                .accessibilityAdjustableAction { direction in
                    turnPage(direction == .increment ? 1 : -1, proxy: proxy)
                }
            CardActionButton(title: l10n.t("التالية", "Next"), systemImage: "chevron.forward") { turnPage(1, proxy: proxy) }
                .disabled(currentPage >= readerPages.count - 1)
                .opacity(currentPage >= readerPages.count - 1 ? 0.45 : 1)
                .accessibilityLabel(l10n.t("الصفحة التالية", "Next page"))
        }
    }

    private func pageHeader(proxy: ScrollViewProxy) -> some View {
        Text(pageTitle)
            .font(.headline)
            .foregroundStyle(BasirPalette.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($pageHeaderFocused)
            .id("page-header")
    }

    @ViewBuilder
    private func pageFooter(proxy: ScrollViewProxy) -> some View {
        if currentPage < readerPages.count - 1 {
            CardActionButton(title: l10n.t("الصفحة التالية", "Next page"), systemImage: "chevron.forward", prominent: true) {
                turnPage(1, proxy: proxy)
            }
            .padding(.top, BasirSpacing.m)
        } else {
            Text(l10n.t("نهاية المستند", "End of the document"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(BasirPalette.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.top, BasirSpacing.m)
        }
    }

    private var mainControls: some View {
        AdaptiveStack {
            controlButton(l10n.t("المحتوى", "Contents"), systemImage: "list.bullet") { showContents = true }
            controlButton(l10n.t("اسأل", "Ask"), systemImage: "questionmark.bubble") { assistMode = .ask }
            controlButton(speaker.isSpeaking && !speaker.isPaused ? l10n.t("إيقاف مؤقت", "Pause")
                                                                  : l10n.t("استماع", "Listen"),
                          systemImage: speaker.isSpeaking && !speaker.isPaused ? "pause.fill" : "play.fill",
                          prominent: true) { togglePlayback() }
            controlButton(bookmarks.contains(position) ? l10n.t("إزالة العلامة", "Unmark")
                                                       : l10n.t("علامة", "Bookmark"),
                          systemImage: bookmarks.contains(position) ? "bookmark.slash" : "bookmark") {
                toggleBookmark(position)
            }
        }
    }

    private func controlButton(_ title: String, systemImage: String, prominent: Bool = false,
                               action: @escaping () -> Void) -> some View {
        CardActionButton(title: title, systemImage: systemImage, prominent: prominent, action: action)
    }

    private var contentsSheet: some View {
        NavigationStack {
            List {
                if !marked.isEmpty {
                    Section(l10n.t("العلامات", "Bookmarks")) {
                        ForEach(marked) { block in contentsButton(excerpt(block), id: block.id) }
                    }
                }
                if !headings.isEmpty {
                    Section(l10n.t("العناوين", "Headings")) {
                        ForEach(headings) { block in
                            let level: Int = { if case .heading(let value) = block.kind { return value } else { return 1 } }()
                            contentsButton(block.text, id: block.id)
                                .padding(.leading, CGFloat(max(0, level - 1)) * 14)
                        }
                    }
                }
                if !tables.isEmpty {
                    Section(l10n.t("الجداول", "Tables")) {
                        ForEach(tables) { block in contentsButton(tableLabel(block), id: block.id) }
                    }
                }
                if !pages.isEmpty {
                    Section(l10n.t("الصفحات", "Pages")) {
                        ForEach(pages) { block in contentsButton(pageLabel(block), id: block.id) }
                    }
                }
            }
            .navigationTitle(l10n.t("المحتوى", "Contents"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t("إغلاق", "Close")) { showContents = false }
                }
            }
        }
        .escapeToDismiss { showContents = false }
        .presentationDetents([.medium, .large])
    }

    private func contentsButton(_ title: String, id: Int) -> some View {
        Button {
            showContents = false
            // Jump after the sheet has gone, so focus lands in the reader.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { pendingJump = id }
        } label: {
            Text(title).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Text just before a table (its caption or heading), to explain it.
    private func context(around block: ReaderBlock) -> String {
        let start = max(0, block.id - 3)
        return blocks[start..<block.id].map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    // MARK: Labels

    private func tableLabel(_ block: ReaderBlock) -> String {
        let columns = block.rows.first?.count ?? 0
        let headers = (block.rows.first ?? []).filter { !$0.isEmpty }.prefix(3).joined(separator: "، ")
        return l10n.t("جدول من \(block.rows.count) صفوف و\(columns) أعمدة", "Table, \(block.rows.count) rows, \(columns) columns")
            + (headers.isEmpty ? "" : ": " + headers)
    }

    private func imageLabel(_ block: ReaderBlock) -> String {
        block.text.isEmpty ? l10n.t("صورة بلا وصف", "Image without a description") : l10n.t("صورة: ", "Image: ") + block.text
    }

    private func pageLabel(_ block: ReaderBlock) -> String {
        let page = block.pageNumber ?? 0
        return l10n.t("الصفحة \(page)", "Page \(page)")
    }

    private func excerpt(_ block: ReaderBlock) -> String {
        switch block.kind {
        case .table: return tableLabel(block)
        case .image: return imageLabel(block)
        default:
            if block.pageNumber != nil { return pageLabel(block) }
            return block.text.count > 80 ? String(block.text.prefix(80)) + "…" : block.text
        }
    }

    // MARK: Actions

    private func load() async {
        let parsed: [ReaderBlock]
        if let preloaded {
            parsed = preloaded
        } else if let url {
            parsed = await Task.detached(priority: .userInitiated) { () -> [ReaderBlock] in
                guard let document = try? DocxExtractor.parse(url: url) else { return [] }
                return ReaderContent.blocks(from: document)
            }.value
        } else {
            parsed = []
        }
        rawBlocks = parsed
        applyMask()
        readerPages = ReaderPaging.pages(for: parsed)
        if remembers {
            bookmarks = memory.bookmarks.filter { $0 < parsed.count }
            let saved = memory.position
            if saved > 0, saved < parsed.count { resumeFrom = saved }
        }
        loading = false
        let pictures = parsed.compactMap { block in block.imageData.map { (block.id, $0) } }
        if !pictures.isEmpty {
            decodedImages = await Task.detached(priority: .utility) { () -> [Int: UIImage] in
                var result: [Int: UIImage] = [:]
                for (id, data) in pictures { result[id] = ReaderImageDecoder.thumbnail(data) }
                return result
            }.value
        }
        let summary = l10n.t("\(title). \(headings.count) عنوانًا، \(tables.count) جدولًا، \(pages.count) صفحة.",
                             "\(title). \(headings.count) headings, \(tables.count) tables, \(pages.count) pages.")
        UIAccessibility.post(notification: .screenChanged, argument: summary)
    }

    private func trackTop() {
        // The first block on screen is where the person is, unless VoiceOver
        // focus or speech say otherwise.
        guard focusedID == nil, !speaker.isSpeaking, let top = visibility.ids.min(), top != position else { return }
        position = top
    }

    /// Opens the page holding a block (in page mode) and scrolls to it.
    private func reveal(_ id: Int, proxy: ScrollViewProxy) {
        if isPaging {
            let target = ReaderPaging.pageIndex(of: id, in: readerPages)
            if target != currentPage { currentPage = target }
        }
        DispatchQueue.main.async { proxy.scrollTo(id, anchor: .top) }
    }

    private func jump(to id: Int, proxy: ScrollViewProxy) {
        position = id
        reveal(id, proxy: proxy)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focusedID = id }
    }

    /// While reading aloud: turn the page when the voice reaches the next
    /// one, and scroll only if the passage is off screen, without animation,
    /// so the screen stays still.
    private func follow(_ id: Int, proxy: ScrollViewProxy) {
        if isPaging, readerPages.indices.contains(currentPage), !readerPages[currentPage].range.contains(id) {
            currentPage = ReaderPaging.pageIndex(of: id, in: readerPages)
            DispatchQueue.main.async { proxy.scrollTo("page-header", anchor: .top) }
            return
        }
        if !visibility.ids.contains(id) { proxy.scrollTo(id, anchor: .top) }
    }

    private func turnPage(_ delta: Int, proxy: ScrollViewProxy) {
        let target = currentPage + delta
        guard readerPages.indices.contains(target) else {
            UIAccessibility.post(notification: .announcement, argument: delta > 0
                ? l10n.t("هذه آخر صفحة", "This is the last page") : l10n.t("هذه أول صفحة", "This is the first page"))
            return
        }
        currentPage = target
        let first = readerPages[target].range.lowerBound
        position = first
        // Listening continues from the new page.
        if speaker.isSpeaking { play(from: first) }
        DispatchQueue.main.async { proxy.scrollTo("page-header", anchor: .top) }
        pageHeaderFocused = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { pageHeaderFocused = true }
    }

    private func togglePaging() {
        paged.toggle()
        if paged, !readerPages.isEmpty { currentPage = ReaderPaging.pageIndex(of: position, in: readerPages) }
        UIAccessibility.post(notification: .announcement, argument: paged
            ? l10n.t("القراءة صفحة صفحة. استخدم التالية والسابقة أسفل الشاشة.", "Page by page. Use Next and Previous at the bottom.")
            : l10n.t("المستند كاملًا في شاشة واحدة.", "The whole document on one screen."))
    }

    private func applyMask() {
        defer { readerIndex = ReaderIndex(blocks) }
        guard maskSensitive else {
            blocks = rawBlocks
            return
        }
        let arabic = l10n.isArabic
        blocks = rawBlocks.map { block in
            ReaderBlock(id: block.id, kind: block.kind, text: SensitiveMask.mask(block.text, isArabic: arabic),
                        rows: block.rows.map { $0.map { SensitiveMask.mask($0, isArabic: arabic) } },
                        imageData: block.imageData, pageNumber: block.pageNumber)
        }
    }

    private func announceMask() {
        UIAccessibility.post(notification: .announcement, argument: maskSensitive
            ? l10n.t("أُخفيت الأرقام الطويلة مثل الهوية والحساب والبطاقة، ويبقى آخر أربعة أرقام.",
                     "Long numbers such as IDs, accounts and cards are hidden; the last four digits stay.")
            : l10n.t("تظهر الأرقام كاملة.", "Numbers are shown in full."))
    }

    private func toggleBilingual() {
        bilingual.toggle()
        if bilingual {
            // Arabic documents are shown with English, everything else with Arabic.
            let sample = blocks.prefix(40).map(\.text).joined(separator: " ")
            let target = ReaderContent.speechLanguage(for: sample) == "ar-SA" ? "en" : "ar"
            translator.reset(target: target, configuration: settings.configuration)
            for block in blocks where Self.translatable(block) && visibility.ids.contains(block.id) {
                translator.need(block.id, text: block.text)
            }
        }
        UIAccessibility.post(notification: .announcement, argument: bilingual
            ? l10n.t("القراءة ثنائية اللغة مفعّلة. تظهر الترجمة بعد كل فقرة.", "Bilingual reading on. Each paragraph is followed by its translation.")
            : l10n.t("أُوقفت القراءة ثنائية اللغة.", "Bilingual reading off."))
    }

    private var audiobookPassages: [String] {
        blocks.map { ReaderContent.spokenText(for: $0, l10n: l10n) }
    }

    private func toggleBookmark(_ id: Int) {
        guard remembers, blocks.indices.contains(id) else { return }
        let added = memory.toggleBookmark(id)
        bookmarks = memory.bookmarks
        UIAccessibility.post(notification: .announcement,
                             argument: added ? l10n.t("أُضيفت علامة", "Bookmark added") : l10n.t("أُزيلت العلامة", "Bookmark removed"))
    }

    private func togglePlayback() {
        if speaker.isSpeaking {
            if speaker.isPaused { speaker.resume() } else { speaker.pause() }
        } else {
            play(from: position)
        }
    }

    private func play(from id: Int) {
        let items = blocks.filter { $0.id >= id }.map { block -> (id: Int, text: String) in
            var text = ReaderContent.spokenText(for: block, l10n: l10n)
            if bilingual, let translated = translator.translations[block.id] { text += "\n" + translated }
            return (id: block.id, text: text)
        }
        speaker.play(items)
    }

    private func close() {
        speaker.stop()
        if remembers, !blocks.isEmpty { memory.position = position }
        dismiss()
    }
}

/// Saves the document as an m4a made on the phone, then shares it.
private struct AudiobookExportView: View {
    @ObservedObject var exporter: AudiobookExporter
    let title: String
    let passages: [String]

    @EnvironmentObject private var l10n: L10n
    @Environment(\.dismiss) private var dismiss
    @State private var share = false
    @State private var lastAnnounced = 0

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: BasirSpacing.l) {
                Text(l10n.t("يحوّل بصير المستند إلى ملف صوتي على هاتفك بنفس الأصوات العربية والإنجليزية، دون إرسال شيء. يمكنك الاستماع إليه في أي تطبيق.",
                            "Basir turns the document into an audio file on your phone with the same Arabic and English voices, without sending anything. Listen in any app."))
                    .fixedSize(horizontal: false, vertical: true)
                if exporter.running {
                    ProgressView(value: exporter.fraction) {
                        Text(l10n.t("جارٍ التسجيل: \(exporter.done) من \(exporter.total)",
                                    "Recording: \(exporter.done) of \(exporter.total)"))
                    }
                    SecondaryActionButton(title: l10n.t("إيقاف", "Stop"), systemImage: "stop.fill") { exporter.cancel() }
                } else if let url = exporter.resultURL {
                    InlineMessage(text: l10n.t("الملف الصوتي جاهز.", "The audio file is ready."), isError: false)
                    PrimaryActionButton(title: l10n.t("مشاركة أو حفظ", "Share or save"), systemImage: "square.and.arrow.up") {
                        share = true
                    }
                    .sheet(isPresented: $share) { ActivityShareView(urls: [url]) }
                } else {
                    if exporter.failed {
                        InlineMessage(text: l10n.t("تعذر إنشاء الملف الصوتي.", "The audio file could not be made."), isError: true)
                    }
                    PrimaryActionButton(title: l10n.t("ابدأ", "Start"), systemImage: "waveform") {
                        exporter.start(passages: passages, title: title)
                    }
                }
                Spacer()
            }
            .appScreenContent()
            .background(BasirPalette.background.ignoresSafeArea())
            .foregroundStyle(BasirPalette.primaryText)
            .navigationTitle(l10n.t("كتاب صوتي", "Audiobook"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(l10n.t("تم", "Done")) { dismiss() } }
            }
        }
        .escapeToDismiss { dismiss() }
        .presentationDetents([.medium, .large])
        .onChange(of: exporter.done) { done in
            // A short progress note every quarter, not on every passage.
            guard exporter.total > 0 else { return }
            let quarter = Int(Double(done) / Double(exporter.total) * 4)
            if quarter > lastAnnounced, quarter < 4 {
                lastAnnounced = quarter
                UIAccessibility.post(notification: .announcement, argument: l10n.t("\(quarter * 25) بالمئة", "\(quarter * 25) percent"))
            }
        }
        .onChange(of: exporter.resultURL) { url in
            if url != nil {
                UIAccessibility.post(notification: .announcement, argument: l10n.t("الملف الصوتي جاهز", "The audio file is ready"))
            }
        }
    }
}

private struct AssistSheet: Identifiable {
    let mode: DocumentAssistView.Mode
    var id: DocumentAssistView.Mode { mode }
}

private struct TableActionModifier: ViewModifier {
    let isTable: Bool
    let title: String
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isTable { content.accessibilityAction(named: title, action) } else { content }
    }
}

/// A table that VoiceOver reads row by row, each cell named by its column.
private struct ReaderTableView: View {
    let rows: [[String]]
    let summary: String

    var body: some View {
        let headers = rows.first ?? []
        VStack(alignment: .leading, spacing: 0) {
            Text(summary)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(BasirPalette.secondaryText)
                .padding(.bottom, BasirSpacing.xs)
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(cell)
                                    .font(index == 0 ? .subheadline.weight(.bold) : .subheadline)
                                    .frame(width: 140, alignment: .leading)
                                    .padding(8)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .background(index == 0 ? BasirPalette.accent.opacity(0.10)
                                               : (index.isMultiple(of: 2) ? BasirPalette.subtleFill : Color.clear))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(index == 0
                            ? headers.filter { !$0.isEmpty }.joined(separator: "، ")
                            : ReaderContent.rowSentence(row, headers: headers))
                        .accessibilityAddTraits(index == 0 ? .isHeader : [])
                    }
                }
            }
        }
        .padding(BasirSpacing.s)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(BasirPalette.stroke, lineWidth: 1)
        }
    }
}

/// Blocks currently on screen. A plain reference: changing it never redraws.
final class VisibleBlocks {
    var ids = Set<Int>()
}

/// Tables, images, page markers and headings, found once per load.
struct ReaderIndex {
    var tables: [ReaderBlock] = []
    var images: [ReaderBlock] = []
    var pages: [ReaderBlock] = []
    var headings: [ReaderBlock] = []

    init() {}

    init(_ blocks: [ReaderBlock]) {
        for block in blocks {
            if block.kind == .table { tables.append(block) }
            if block.kind == .image { images.append(block) }
            if block.pageNumber != nil { pages.append(block) } else if block.isHeading { headings.append(block) }
        }
    }
}

/// Decodes a document image at screen size instead of full resolution.
enum ReaderImageDecoder {
    static func thumbnail(_ data: Data, maxPixels: Int = 1_400) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return UIImage(data: data) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return UIImage(data: data) }
        return UIImage(cgImage: image)
    }
}

/// Reads blocks aloud one after another, in Arabic or English per passage.
/// Long passages are spoken a sentence at a time. A watchdog restarts the
/// speech engine if it goes quiet without saying it finished, which iOS
/// sometimes does after an interruption or on long texts.
@MainActor
final class ReaderSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var speakingID: Int?
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false

    private var synthesizer = AVSpeechSynthesizer()
    private var queue: [(id: Int, text: String)] = []
    private var current: (id: Int, text: String)?
    private var currentUtterance: AVSpeechUtterance?
    private var lastProgress = Date()
    private var restarts = 0
    private var watchdog: Task<Void, Never>?
    private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init()
        synthesizer.delegate = self
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            Task { @MainActor in self?.handleInterruption(type) }
        }
    }

    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    func play(_ items: [(id: Int, text: String)]) {
        stop()
        queue = items.flatMap { item in SpeechChunker.chunks(item.text).map { (id: item.id, text: $0) } }
        guard !queue.isEmpty else { return }
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? audio.setActive(true)
        isSpeaking = true
        startWatchdog()
        speakNext()
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
    }

    func resume() {
        isPaused = false
        lastProgress = Date()
        if !synthesizer.continueSpeaking() { restartCurrent() }
    }

    func stop() {
        watchdog?.cancel()
        watchdog = nil
        queue = []
        current = nil
        currentUtterance = nil
        if synthesizer.isSpeaking || synthesizer.isPaused { synthesizer.stopSpeaking(at: .immediate) }
        if isSpeaking {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        isSpeaking = false
        isPaused = false
        speakingID = nil
    }

    private func speakNext() {
        guard isSpeaking, !queue.isEmpty else {
            stop()
            return
        }
        let item = queue.removeFirst()
        current = item
        restarts = 0
        if speakingID != item.id { speakingID = item.id }
        speak(item)
    }

    private func speak(_ item: (id: Int, text: String)) {
        let utterance = AVSpeechUtterance(string: item.text)
        utterance.voice = AVSpeechSynthesisVoice(language: ReaderContent.speechLanguage(for: item.text))
        utterance.postUtteranceDelay = 0.1
        currentUtterance = utterance
        lastProgress = Date()
        synthesizer.speak(utterance)
    }

    /// A fresh engine for the passage that got stuck. Twice stuck: skip it.
    private func restartCurrent() {
        guard let item = current else { speakNext(); return }
        restarts += 1
        currentUtterance = nil
        synthesizer.delegate = nil
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        if restarts > 2 { speakNext() } else { speak(item) }
    }

    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                guard self.isSpeaking, !self.isPaused, self.currentUtterance != nil else { continue }
                let quiet = Date().timeIntervalSince(self.lastProgress)
                if !self.synthesizer.isSpeaking, quiet > 2.5 {
                    // Finished, but the "did finish" call never came.
                    self.speakNext()
                } else if quiet > 10 {
                    // Speaking, but no word for ten seconds: stuck.
                    self.restartCurrent()
                }
            }
        }
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType?) {
        guard isSpeaking else { return }
        switch type {
        case .began:
            isPaused = true
        case .ended:
            try? AVAudioSession.sharedInstance().setActive(true)
            isPaused = false
            restartCurrent()
        default:
            break
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard utterance === self.currentUtterance else { return }
            self.lastProgress = Date()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard utterance === self.currentUtterance else { return }
            self.lastProgress = Date()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard utterance === self.currentUtterance else { return }
            self.currentUtterance = nil
            self.speakNext()
        }
    }
}
