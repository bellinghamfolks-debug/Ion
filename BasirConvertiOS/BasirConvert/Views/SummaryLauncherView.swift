import SwiftUI
import PDFKit

/// Opens the summary screen for files that are not open in the reader yet:
/// one or several results in My Files (ت9), or a file shared from another
/// app or chosen by Siri (ت18). The text is taken on the phone (the Word
/// result, a PDF's own text, or on-device text recognition) and only the
/// text is sent for the summary.
struct SummaryLauncherView: View {
    enum Input {
        case outputs([URL])
        case files([URL])
    }

    let input: Input

    init(input: Input) {
        self.input = input
    }

    @EnvironmentObject private var l10n: L10n
    @Environment(\.dismiss) private var dismiss
    @State private var source: SummarySource?
    @State private var failure: String?
    @State private var note: String?

    var body: some View {
        if let source {
            SummaryView(source: source)
        } else {
            NavigationStack {
                VStack(alignment: .leading, spacing: BasirSpacing.l) {
                    if let failure {
                        InlineMessage(text: failure, isError: true)
                    } else {
                        ProgressView(l10n.t("جارٍ تجهيز المستند للتلخيص", "Preparing the document for the summary"))
                            .frame(maxWidth: .infinity)
                    }
                    if let note { Text(note).font(.footnote).foregroundStyle(BasirPalette.secondaryText) }
                    Spacer()
                }
                .appScreenContent()
                .background(BasirPalette.background.ignoresSafeArea())
                .navigationTitle(l10n.t("ملخص", "Summary"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(l10n.t("إغلاق", "Close")) { dismiss() } }
                }
            }
            .escapeToDismiss { dismiss() }
            .task { await load() }
        }
    }

    private func load() async {
        let arabic = l10n.isArabic
        switch input {
        case .outputs(let urls):
            let documents = await Task.detached(priority: .userInitiated) { () -> [(URL, [ReaderBlock])] in
                urls.map { url in
                    let blocks = (try? DocxExtractor.parse(url: url)).map { ReaderContent.blocks(from: $0) } ?? []
                    return (url, blocks)
                }
            }.value
            build(documents.map { document -> (name: String, blocks: [ReaderBlock], output: URL?) in
                (name: document.0.deletingPathExtension().lastPathComponent, blocks: document.1, output: document.0)
            })
        case .files(let urls):
            var documents: [(name: String, blocks: [ReaderBlock], output: URL?)] = []
            for url in urls {
                let blocks = await SummaryText.blocks(of: url, isArabic: arabic)
                documents.append((name: url.deletingPathExtension().lastPathComponent, blocks: blocks.blocks, output: nil))
                if blocks.truncated {
                    note = l10n.t("قرأ بصير على جهازك أول \(InstantReader.maximumPages) صفحة من الملف المصوَّر. لتلخيص الملف كاملًا، حوّله إلى Word أولًا أو اختر «إضافة ملخص في بداية الملف» عند التحويل.",
                                  "Basir read the first \(InstantReader.maximumPages) pages of the scanned file on your device. To summarize all of it, convert it to Word first, or choose “Add a summary at the start of the file” when converting.")
                }
            }
            build(documents)
        }
    }

    private func build(_ documents: [(name: String, blocks: [ReaderBlock], output: URL?)]) {
        let readable = documents.filter { !$0.blocks.isEmpty }
        guard !readable.isEmpty else {
            failure = l10n.t("لم يجد بصير نصًا يمكن تلخيصه في هذا الملف.", "Basir found no text to summarize in this file.")
            UIAccessibility.post(notification: .announcement, argument: failure ?? "")
            return
        }
        if readable.count == 1, let only = readable.first {
            let text = DocumentAssistant.text(of: only.blocks)
            source = SummarySource(title: only.name, text: text,
                                   home: only.output.map { SummaryHome.output($0) } ?? .key(SummaryStore.fingerprint(text)),
                                   blocks: only.blocks, outputURL: only.output)
        } else {
            let files = readable.map { SummaryRequestBody.File(name: $0.name, text: DocumentAssistant.text(of: $0.blocks)) }
            let key = SummaryStore.fingerprint(files.map { $0.name + "\n" + $0.text }.joined(separator: "\n\u{1E}\n"))
            source = SummarySource(title: l10n.t("\(files.count) ملفات", "\(files.count) files"), files: files,
                                   home: .key(key))
        }
    }
}

/// The readable text of any file Basir accepts, taken on the phone.
enum SummaryText {
    static func blocks(of url: URL, isArabic: Bool) async -> (blocks: [ReaderBlock], truncated: Bool) {
        let ext = url.pathExtension.lowercased()
        if ext == "docx", let document = try? DocxExtractor.parse(url: url) {
            return (ReaderContent.blocks(from: document), false)
        }
        if ext == "pdf", let pdf = PDFDocument(url: url) {
            // A digital PDF: its own text, every page, with page markers.
            var blocks: [ReaderBlock] = []
            var characters = 0
            for index in 0..<pdf.pageCount {
                let text = pdf.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                characters += text.count
                let marker = isArabic ? "الصفحة \(index + 1)" : "Page \(index + 1)"
                blocks.append(ReaderBlock(id: blocks.count, kind: .heading(2), text: marker, pageNumber: index + 1))
                for paragraph in text.components(separatedBy: "\n\n") where !paragraph.isEmpty {
                    blocks.append(ReaderBlock(id: blocks.count, kind: .paragraph, text: paragraph))
                }
            }
            if characters >= max(200, pdf.pageCount * 80) { return (blocks, false) }
        }
        // A scan or a picture: on-device text recognition.
        guard let outcome = try? await InstantReader.read([url], isArabic: isArabic) else { return ([], false) }
        return (outcome.blocks, outcome.pagesSkipped > 0)
    }
}
