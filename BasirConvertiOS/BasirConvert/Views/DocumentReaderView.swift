import SwiftUI
import AVFoundation
import UIKit

/// Reads a Basir Word result inside the app, built for VoiceOver first:
/// headings are headings, every table row is read with its column names,
/// rotors jump between tables, images, pages and bookmarks, and the place
/// the person stopped is kept for next time. It can also read aloud.
struct DocumentReaderView: View {
    let url: URL
    @EnvironmentObject private var l10n: L10n
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speaker = ReaderSpeaker()
    @State private var blocks: [ReaderBlock] = []
    @State private var loading = true
    @State private var bookmarks: [Int] = []
    @State private var visible: Set<Int> = []
    @State private var position = 0
    @State private var resumeFrom: Int?
    @State private var showContents = false
    @State private var pendingJump: Int?
    @AccessibilityFocusState private var focusedID: Int?
    @Namespace private var rotorSpace

    private var memory: ReaderMemory { ReaderMemory(fileName: url.lastPathComponent) }
    private var title: String { url.deletingPathExtension().lastPathComponent }
    private var tables: [ReaderBlock] { blocks.filter { $0.kind == .table } }
    private var images: [ReaderBlock] { blocks.filter { $0.kind == .image } }
    private var pages: [ReaderBlock] { blocks.filter { $0.pageNumber != nil } }
    private var headings: [ReaderBlock] { blocks.filter { $0.isHeading && $0.pageNumber == nil } }
    private var marked: [ReaderBlock] { bookmarks.compactMap { id in blocks.first { $0.id == id } } }

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
                            ForEach(blocks) { block in
                                row(block, proxy: proxy)
                                    .id(block.id)
                                    .accessibilityRotorEntry(id: block.id, in: rotorSpace)
                                    .accessibilityFocused($focusedID, equals: block.id)
                                    .onAppear { visible.insert(block.id); trackTop() }
                                    .onDisappear { visible.remove(block.id); trackTop() }
                            }
                        }
                    }
                    .appScreenContent(bottomPadding: 120)
                }
                .accessibilityRotor(Text(l10n.t("الجداول", "Tables"))) {
                    ForEach(tables) { block in
                        AccessibilityRotorEntry(Text(tableLabel(block)), id: block.id, in: rotorSpace) {
                            proxy.scrollTo(block.id, anchor: .top)
                        }
                    }
                }
                .accessibilityRotor(Text(l10n.t("الصور", "Images"))) {
                    ForEach(images) { block in
                        AccessibilityRotorEntry(Text(imageLabel(block)), id: block.id, in: rotorSpace) {
                            proxy.scrollTo(block.id, anchor: .top)
                        }
                    }
                }
                .accessibilityRotor(Text(l10n.t("الصفحات", "Pages"))) {
                    ForEach(pages) { block in
                        AccessibilityRotorEntry(Text(pageLabel(block)), id: block.id, in: rotorSpace) {
                            proxy.scrollTo(block.id, anchor: .top)
                        }
                    }
                }
                .accessibilityRotor(Text(l10n.t("العلامات", "Bookmarks"))) {
                    ForEach(marked) { block in
                        AccessibilityRotorEntry(Text(excerpt(block)), id: block.id, in: rotorSpace) {
                            proxy.scrollTo(block.id, anchor: .top)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) { controls }
                .onChange(of: speaker.speakingID) { id in
                    guard let id else { return }
                    position = id
                    withAnimation { proxy.scrollTo(id, anchor: .top) }
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
            }
            .sheet(isPresented: $showContents) { contentsSheet }
        }
        .escapeToDismiss { close() }
        .task { await load() }
        .onDisappear {
            speaker.stop()
            if !blocks.isEmpty { memory.position = position }
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ block: ReaderBlock, proxy: ScrollViewProxy) -> some View {
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
            ReaderTableView(rows: block.rows, summary: tableLabel(block))
        case .image:
            VStack(alignment: .leading, spacing: BasirSpacing.xs) {
                if let data = block.imageData, let image = UIImage(data: data) {
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
                    memory.position = 0
                    focusedID = blocks.first?.id
                }
            }
        }
        .glassSurface()
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: BasirSpacing.s) {
            controlButton(l10n.t("المحتوى", "Contents"), systemImage: "list.bullet") { showContents = true }
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
        .padding(.horizontal, BasirSpacing.l)
        .padding(.vertical, BasirSpacing.s)
        .background(.ultraThinMaterial)
        .disabled(blocks.isEmpty)
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
        let url = self.url
        let parsed = await Task.detached(priority: .userInitiated) { () -> [ReaderBlock] in
            guard let document = try? DocxExtractor.parse(url: url) else { return [] }
            return ReaderContent.blocks(from: document)
        }.value
        blocks = parsed
        bookmarks = memory.bookmarks.filter { $0 < parsed.count }
        let saved = memory.position
        if saved > 0, saved < parsed.count { resumeFrom = saved }
        loading = false
        let summary = l10n.t("\(title). \(headings.count) عنوانًا، \(tables.count) جدولًا، \(pages.count) صفحة.",
                             "\(title). \(headings.count) headings, \(tables.count) tables, \(pages.count) pages.")
        UIAccessibility.post(notification: .screenChanged, argument: summary)
    }

    private func trackTop() {
        // The first block on screen is where the person is, unless VoiceOver
        // focus or speech say otherwise.
        guard focusedID == nil, !speaker.isSpeaking, let top = visible.min() else { return }
        position = top
    }

    private func jump(to id: Int, proxy: ScrollViewProxy) {
        position = id
        proxy.scrollTo(id, anchor: .top)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focusedID = id }
    }

    private func toggleBookmark(_ id: Int) {
        guard blocks.indices.contains(id) else { return }
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
        let items = blocks.filter { $0.id >= id }.map { (id: $0.id, text: ReaderContent.spokenText(for: $0, l10n: l10n)) }
        speaker.play(items)
    }

    private func close() {
        speaker.stop()
        if !blocks.isEmpty { memory.position = position }
        dismiss()
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

/// Reads blocks aloud one after another, in Arabic or English per passage.
@MainActor
final class ReaderSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var speakingID: Int?
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false

    private let synthesizer = AVSpeechSynthesizer()
    private var queue: [(id: Int, text: String)] = []
    private var current: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func play(_ items: [(id: Int, text: String)]) {
        stop()
        queue = items.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !queue.isEmpty else { return }
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? audio.setActive(true)
        isSpeaking = true
        speakNext()
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
    }

    func resume() {
        synthesizer.continueSpeaking()
        isPaused = false
    }

    func stop() {
        queue = []
        current = nil
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
        speakingID = item.id
        let utterance = AVSpeechUtterance(string: item.text)
        utterance.voice = AVSpeechSynthesisVoice(language: ReaderContent.speechLanguage(for: item.text))
        utterance.postUtteranceDelay = 0.15
        current = utterance
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard utterance === self.current else { return }
            self.speakNext()
        }
    }
}
