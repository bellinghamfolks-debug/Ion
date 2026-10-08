import Foundation

/// One readable unit of a Basir Word result, flattened for the in-app reader:
/// plain values only, so it can be built off the main thread and kept.
struct ReaderBlock: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case heading(Int)
        case paragraph
        case listItem(ordered: Bool, level: Int)
        case table
        case image
        case math
        case link
    }

    let id: Int
    let kind: Kind
    let text: String
    var rows: [[String]] = []
    var imageData: Data?
    /// Set when the block is the "Page N" marker Basir writes for each source page.
    var pageNumber: Int?

    var isHeading: Bool { if case .heading = kind { return true } else { return false } }
}

enum ReaderContent {
    static func blocks(from document: ExtractedDocument) -> [ReaderBlock] {
        var result: [ReaderBlock] = []
        for block in document.blocks {
            let id = result.count
            switch block {
            case .heading(let level, let text):
                result.append(ReaderBlock(id: id, kind: .heading(level), text: text, pageNumber: pageNumber(in: text)))
            case .paragraph(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                result.append(ReaderBlock(id: id, kind: .paragraph, text: trimmed, pageNumber: pageNumber(in: trimmed)))
            case .list(let text, let ordered, let level):
                result.append(ReaderBlock(id: id, kind: .listItem(ordered: ordered, level: level), text: text))
            case .table(let rows):
                let cleaned = rows.filter { $0.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
                guard !cleaned.isEmpty else { continue }
                result.append(ReaderBlock(id: id, kind: .table, text: "", rows: cleaned))
            case .image(let image, let altText, let title):
                let description = [title, altText]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: ". ")
                result.append(ReaderBlock(id: id, kind: .image, text: description, imageData: image.data))
            case .hyperlink(let text, _):
                result.append(ReaderBlock(id: id, kind: .link, text: text))
            case .math(let expression):
                result.append(ReaderBlock(id: id, kind: .math, text: expression))
            }
        }
        return result
    }

    /// "الصفحة 12", "صفحة ١٢", "Page 12" or "Source page 12" alone on a line.
    static func pageNumber(in text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 24 else { return nil }
        let prefixes = ["الصفحة", "صفحة", "Source page", "Page"]
        guard let prefix = prefixes.first(where: { trimmed.lowercased().hasPrefix($0.lowercased()) }) else { return nil }
        let rest = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        let western = String(rest.map { character -> Character in
            if let value = character.wholeNumberValue, !character.isASCII { return Character(String(value)) }
            return character
        })
        return Int(western)
    }

    /// What a table row says when read on its own: every cell named by its
    /// column, so the person never has to remember the header row.
    static func rowSentence(_ row: [String], headers: [String]) -> String {
        row.enumerated().compactMap { index, cell in
            let value = cell.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            let header = index < headers.count ? headers[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            return header.isEmpty || header == value ? value : "\(header): \(value)"
        }.joined(separator: "، ")
    }

    /// Text to read aloud for a block, in reading order.
    @MainActor
    static func spokenText(for block: ReaderBlock, l10n: L10n) -> String {
        switch block.kind {
        case .table:
            let headers = block.rows.first ?? []
            let columns = headers.count
            var parts = [l10n.t("جدول من \(block.rows.count) صفوف و\(columns) أعمدة.",
                                "Table with \(block.rows.count) rows and \(columns) columns.")]
            parts.append(headers.filter { !$0.isEmpty }.joined(separator: "، "))
            for (index, row) in block.rows.dropFirst().enumerated() {
                parts.append(l10n.t("الصف \(index + 1): ", "Row \(index + 1): ") + rowSentence(row, headers: headers))
            }
            return parts.joined(separator: "\n")
        case .image:
            return block.text.isEmpty ? l10n.t("صورة.", "Image.") : l10n.t("صورة: ", "Image: ") + block.text
        case .math:
            return l10n.t("معادلة: ", "Equation: ") + block.text
        default:
            return block.text
        }
    }

    /// The language to speak a passage in: Arabic when Arabic letters
    /// dominate, English otherwise.
    static func speechLanguage(for text: String) -> String {
        var arabic = 0, latin = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0600...0x06FF, 0x0750...0x077F, 0xFB50...0xFDFF, 0xFE70...0xFEFF: arabic += 1
            case 0x41...0x5A, 0x61...0x7A: latin += 1
            default: break
            }
        }
        return arabic >= latin && arabic > 0 ? "ar-SA" : "en-US"
    }
}

/// Where the person stopped and what they marked, per result file.
struct ReaderMemory {
    private let defaults: UserDefaults
    private let key: String

    init(fileName: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.key = "reader." + fileName
    }

    var position: Int {
        get { defaults.integer(forKey: key + ".position") }
        nonmutating set { defaults.set(newValue, forKey: key + ".position") }
    }

    var bookmarks: [Int] {
        get { (defaults.array(forKey: key + ".bookmarks") as? [Int]) ?? [] }
        nonmutating set { defaults.set(Array(Set(newValue)).sorted(), forKey: key + ".bookmarks") }
    }

    func toggleBookmark(_ id: Int) -> Bool {
        var marks = bookmarks
        if let index = marks.firstIndex(of: id) {
            marks.remove(at: index)
            bookmarks = marks
            return false
        }
        marks.append(id)
        bookmarks = marks
        return true
    }

    func forget() {
        defaults.removeObject(forKey: key + ".position")
        defaults.removeObject(forKey: key + ".bookmarks")
    }
}

/// Hides long numbers (ID, card, account, IBAN, phone) in what the reader
/// shows and says, keeping the last four digits so the person can still
/// tell which one it is.
enum SensitiveMask {
    private static let pattern = try! NSRegularExpression(
        pattern: "(?<![0-9٠-٩])[0-9٠-٩](?:[ \\-]?[0-9٠-٩]){8,}(?![0-9٠-٩])"
    )

    static func mask(_ text: String, isArabic: Bool) -> String {
        let range = NSRange(text.startIndex..., in: text)
        let matches = pattern.matches(in: text, range: range)
        guard !matches.isEmpty else { return text }
        var result = text
        for match in matches.reversed() {
            guard let swiftRange = Range(match.range, in: result) else { continue }
            let digits = result[swiftRange].filter { $0.isNumber }
            let last = String(digits.suffix(4))
            let replacement = isArabic ? "(رقم مخفي ينتهي بـ \(last))" : "(hidden number ending \(last))"
            result.replaceSubrange(swiftRange, with: replacement)
        }
        return result
    }
}
