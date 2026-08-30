import Foundation

struct VisualSpec: Equatable, Sendable {
    let kind: String
    let yMin: Int
    let xMin: Int
    let yMax: Int
    let xMax: Int
    let altText: String
}

final class MarkdownDocumentParser {
    typealias VisualResolver = (VisualSpec) throws -> PreparedImage?

    private static let maximumVisualsPerPage = 12
    private let document: DocxBuilder
    private let defaultArabic: Bool
    private var emittedVisualDescriptions: Set<String> = []
    private(set) var renderedPageCount = 0
    private(set) var tableCount = 0
    private(set) var imageCount = 0
    private(set) var lastPageVisualMarkerCount = 0
    private var mostRecentHeading = ""

    init(document: DocxBuilder, defaultArabic: Bool) {
        self.document = document
        self.defaultArabic = defaultArabic
    }

    func appendPage(
        _ markdown: String,
        sourcePageNumber: Int,
        visualResolver: VisualResolver? = nil
    ) {
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if renderedPageCount > 0 { document.pageBreak() }
        lastPageVisualMarkerCount = 0
        parse(markdown, sourcePageNumber: sourcePageNumber, visualResolver: visualResolver)
        renderedPageCount += 1
    }

    /// Used for translated DOCX chunks. It preserves semantic blocks without
    /// inventing a physical page boundary between transport-sized chunks.
    func appendChunk(_ markdown: String) {
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        parse(markdown, sourcePageNumber: 0, visualResolver: nil)
    }

    private func parse(
        _ markdown: String,
        sourcePageNumber: Int,
        visualResolver: VisualResolver?
    ) {
        let stripped = Self.stripOuterFence(markdown.trimmingCharacters(in: .whitespacesAndNewlines))
        let lines = stripped.components(separatedBy: .newlines)
        var table: [[String]] = []
        var tableCaption = ""
        var paragraph: [String] = []
        var pageImages = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let text = Self.normalizeModelText(paragraph.joined(separator: "\n"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty, !Self.isGeneratedPageLabel(text) { document.paragraph(text) }
            paragraph.removeAll(keepingCapacity: true)
        }

        func flushTable() {
            guard !table.isEmpty else { return }
            let width = table.map(\.count).max() ?? 0
            for index in table.indices {
                while table[index].count < width { table[index].append("") }
            }
            let populated = table.flatMap { $0 }.filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.count
            if table.count >= 2, populated >= 3 {
                var caption = tableCaption.trimmingCharacters(in: .whitespacesAndNewlines)
                if caption.isEmpty {
                    caption = defaultArabic
                        ? "جدول في صفحة المصدر \(sourcePageNumber)"
                        : "Table on source page \(sourcePageNumber)"
                }
                let rows = max(0, table.count - 1)
                let description = defaultArabic
                    ? "\(caption)؛ \(width) أعمدة و\(rows) صفوف بيانات."
                    : "\(caption); \(width) columns and \(rows) data rows."
                document.table(table, headerRow: true,
                               headerColumn: Self.looksLikeSchedule(table),
                               caption: caption, description: description)
                tableCount += 1
            }
            table.removeAll(keepingCapacity: true)
            tableCaption = ""
        }

        for raw in lines {
            var line = Self.normalizeModelText(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            let unbulleted = line.replacingOccurrences(
                of: #"^[-*+]\s+"#, with: "", options: .regularExpression
            )
            let visualLine = Self.stripInlineMarkdown(unbulleted)
            let visual = Self.parseVisualMarker(visualLine)
            if visual != nil || Self.isPotentialVisualMarker(visualLine) {
                flushTable()
                flushParagraph()
                guard let visual else { continue }
                lastPageVisualMarkerCount += 1
                if pageImages < Self.maximumVisualsPerPage, let visualResolver {
                    do {
                        if let prepared = try visualResolver(visual) {
                            let logo = visual.kind.localizedCaseInsensitiveContains("logo")
                                || visual.kind.contains("شعار")
                            document.image(
                                prepared,
                                altText: visual.altText,
                                title: defaultArabic
                                    ? "صورة من صفحة \(sourcePageNumber)"
                                    : "Image from page \(sourcePageNumber)",
                                maximumWidthInches: logo ? 2.4 : 6.4
                            )
                            imageCount += 1
                            pageImages += 1
                        }
                    } catch {
                        // The text description remains available when one crop fails.
                    }
                }
                appendVisualDescription(visual.altText)
                continue
            }

            if Self.isHorizontalRule(line) {
                flushTable()
                flushParagraph()
                continue
            }

            if Self.isTableRow(line) {
                flushParagraph()
                if Self.isTableSeparator(line) {
                    if table.count > 1 {
                        let nextHeader = table.removeLast()
                        flushTable()
                        tableCaption = Self.captionFromPossibleTitleRow(nextHeader)
                        if tableCaption.isEmpty { tableCaption = mostRecentHeading }
                        table.append(nextHeader)
                    }
                    continue
                }
                if table.isEmpty { tableCaption = mostRecentHeading }
                table.append(Self.splitTableRow(line))
                continue
            }

            if line.isEmpty, !table.isEmpty { continue }
            flushTable()

            if line.hasPrefix("#") {
                var level = 0
                for character in line.prefix(6) where character == "#" { level += 1 }
                let start = line.index(line.startIndex, offsetBy: min(level, line.count))
                let heading = Self.stripInlineMarkdown(String(line[start...]))
                if heading.isEmpty || Self.isGeneratedPageLabel(heading) { continue }
                flushParagraph()
                mostRecentHeading = heading
                document.heading(max(1, min(6, level)), heading)
                continue
            }

            if line.isEmpty {
                flushParagraph()
                continue
            }
            if Self.isGeneratedPageLabel(line) { continue }
            if Self.isVisualDescription(line) {
                flushParagraph()
                appendVisualDescription(Self.stripVisualLabel(line))
                continue
            }

            if let list = Self.listItem(from: line) {
                flushParagraph()
                document.listItem(list.text, ordered: list.ordered, level: list.level)
                continue
            }
            if let link = Self.standaloneLink(from: line) {
                flushParagraph()
                document.hyperlink(link.url, text: link.text)
                continue
            }
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty { paragraph.append(line) }
        }
        flushTable()
        flushParagraph()
    }

    private static func listItem(from line: String) -> (text: String, ordered: Bool, level: Int)? {
        let pattern = #"^(\s*)(?:(\d+)[.)]|([-*+]))\s+(.+)$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: line,
                range: NSRange(line.startIndex..<line.endIndex, in: line)
              ),
              let textRange = Range(match.range(at: 4), in: line) else { return nil }
        let indent: Int
        if let range = Range(match.range(at: 1), in: line) { indent = line[range].count / 2 }
        else { indent = 0 }
        let ordered = match.range(at: 2).location != NSNotFound
        return (stripInlineMarkdown(String(line[textRange])), ordered, min(8, indent))
    }

    private static func standaloneLink(from line: String) -> (text: String, url: String)? {
        let pattern = #"^\[([^\]]+)\]\((https?://[^\s)]+|mailto:[^\s)]+)\)$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: line,
                range: NSRange(line.startIndex..<line.endIndex, in: line)
              ),
              let textRange = Range(match.range(at: 1), in: line),
              let urlRange = Range(match.range(at: 2), in: line) else { return nil }
        return (String(line[textRange]), String(line[urlRange]))
    }

    private func appendVisualDescription(_ raw: String) {
        let description = Self.stripInlineMarkdown(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return }
        let normalized = description.lowercased()
            .replacingOccurrences(of: #"[\p{P}\p{S}\s]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let logo = normalized.contains("شعار") || normalized.contains("logo")
        let kingSaud = normalized.contains("جامعة الملك سعود")
            || normalized.contains("king saud university")
        let key = logo && kingSaud ? "logo:king-saud-university" : normalized
        guard emittedVisualDescriptions.insert(key).inserted else { return }
        document.paragraph((defaultArabic ? "وصف بصري: " : "Visual description: ") + description)
    }

    static func parseVisualMarker(_ line: String) -> VisualSpec? {
        guard isPotentialVisualMarker(line), line.hasSuffix("]]"), line.count > 4 else { return nil }
        let body = String(line.dropFirst(2).dropLast(2))
        let fields = body.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 4,
              fields[0].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "BASIR_VISUAL" else {
            return nil
        }
        let box = fields[2].split(separator: ",", omittingEmptySubsequences: false)
        guard box.count == 4,
              let rawYMin = Int(box[0].trimmingCharacters(in: .whitespaces)),
              let rawXMin = Int(box[1].trimmingCharacters(in: .whitespaces)),
              let rawYMax = Int(box[2].trimmingCharacters(in: .whitespaces)),
              let rawXMax = Int(box[3].trimmingCharacters(in: .whitespaces)) else { return nil }
        let yMin = max(0, min(1_000, rawYMin))
        let xMin = max(0, min(1_000, rawXMin))
        let yMax = max(0, min(1_000, rawYMax))
        let xMax = max(0, min(1_000, rawXMax))
        let alt = stripInlineMarkdown(fields[3].replacingOccurrences(of: "|", with: " "))
        guard yMax - yMin >= 5, xMax - xMin >= 5, !alt.isEmpty else { return nil }
        return VisualSpec(kind: fields[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                          yMin: yMin, xMin: xMin, yMax: yMax, xMax: xMax, altText: alt)
    }

    static func containsVisualDescription(_ markdown: String) -> Bool {
        let lower = markdown.lowercased()
        return lower.contains("[وصف الصورة]") || lower.contains("وصف الصورة:")
            || lower.contains("[image description]") || lower.contains("image description:")
            || lower.contains("[[basir_visual|")
    }

    static func normalizeModelText(_ value: String) -> String {
        value.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)
    }

    static func stripInlineMarkdown(_ value: String) -> String {
        var output = normalizeModelText(value)
            .replacingOccurrences(of: "\\|", with: "|")
        let patterns = [
            (#"\*\*([^*]+?)\*\*"#, "$1"),
            (#"__([^_]+?)__"#, "$1"),
            (#"(?<![*\w])\*([^*\n]+?)\*(?![*\w])"#, "$1"),
            (#"(?<![_\w])_([^_\n]+?)_(?![_\w])"#, "$1"),
            (#"`([^`]+?)`"#, "$1")
        ]
        for (pattern, replacement) in patterns {
            output = output.replacingOccurrences(of: pattern, with: replacement,
                                                 options: .regularExpression)
        }
        return output.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripOuterFence(_ value: String) -> String {
        var output = value
        if output.hasPrefix("```") {
            if let newline = output.firstIndex(of: "\n") {
                output = String(output[output.index(after: newline)...])
            }
        }
        if output.hasSuffix("```") { output = String(output.dropLast(3)) }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isPotentialVisualMarker(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            .hasPrefix("[[BASIR_VISUAL|")
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        guard line.count >= 3, !line.hasPrefix("|"), let first = line.first,
              first == "-" || first == "*" || first == "_" else { return false }
        var count = 0
        for character in line {
            if character == first { count += 1 }
            else if character != " " && character != "\t" { return false }
        }
        return count >= 3
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.count >= 3 && line.hasPrefix("|") && line.hasSuffix("|")
            && line.dropFirst().contains("|")
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        line.contains("-") && line.allSatisfy { "|-: ".contains($0) }
    }

    private static func splitTableRow(_ line: String) -> [String] {
        let inner = String(line.dropFirst().dropLast())
        var cells: [String] = []
        var cell = ""
        var escaped = false
        for character in inner {
            if escaped {
                cell.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                cells.append(stripInlineMarkdown(cell))
                cell = ""
            } else {
                cell.append(character)
            }
        }
        if escaped { cell.append("\\") }
        cells.append(stripInlineMarkdown(cell))
        return cells
    }

    private static func captionFromPossibleTitleRow(_ row: [String]) -> String {
        let populated = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return populated.count == 1 ? populated[0] : ""
    }

    private static func isGeneratedPageLabel(_ text: String) -> Bool {
        let patterns = [#"(?iu)^الصفحة\s*[0-9٠-٩]+$"#,
                        #"(?iu)^page\s*[0-9]+$"#,
                        #"(?iu)^source page\s*[0-9]+$"#]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private static func isVisualDescription(_ line: String) -> Bool {
        let lower = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("[وصف الصورة]") || lower.hasPrefix("وصف الصورة:")
            || lower.hasPrefix("[image description]") || lower.hasPrefix("image description:")
    }

    private static func stripVisualLabel(_ line: String) -> String {
        line.replacingOccurrences(
            of: #"(?iu)^\s*(?:\[وصف الصورة\]|وصف الصورة:|\[image description\]|image description:)\s*"#,
            with: "", options: .regularExpression
        )
    }

    private static func looksLikeSchedule(_ rows: [[String]]) -> Bool {
        guard let first = rows.first else { return false }
        let header = first.joined(separator: " ").lowercased()
        return (header.contains("وقت") || header.contains("الزمن") || header.contains("time"))
            && (header.contains("يوم") || header.contains("day")
                || header.contains("تاريخ") || header.contains("date"))
    }
}

