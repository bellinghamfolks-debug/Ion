import Foundation

/// One screen of the reader in page mode: a run of blocks.
struct ReaderPage: Equatable, Sendable {
    /// 0-based position in the page list.
    let index: Int
    /// The page number printed in the document, when it has one.
    let printedNumber: Int?
    /// Block ids (equal to their indices) on this page.
    let range: Range<Int>
}

enum ReaderPaging {
    /// Characters per page when the document has no page markers.
    static let charactersPerPage = 2_400
    static let blocksPerPage = 30

    /// Pages follow the document's own "Page N" markers when it has them;
    /// otherwise the text is cut into screens of similar length, starting a
    /// new screen at a heading where possible.
    static func pages(for blocks: [ReaderBlock]) -> [ReaderPage] {
        guard !blocks.isEmpty else { return [] }
        let markers = blocks.filter { $0.pageNumber != nil }.map(\.id)
        var starts: [Int]
        if !markers.isEmpty {
            starts = markers
            // Text before the first marker joins the first page.
            starts[0] = 0
        } else {
            starts = [0]
            var characters = 0
            var count = 0
            for block in blocks {
                let size = weight(of: block)
                let full = characters + size > charactersPerPage || count >= blocksPerPage
                let goodBreak = block.isHeading && characters > charactersPerPage / 2
                if count > 0, full || goodBreak {
                    starts.append(block.id)
                    characters = 0
                    count = 0
                }
                characters += size
                count += 1
            }
        }
        var pages: [ReaderPage] = []
        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1] : blocks.count
            guard end > start else { continue }
            let printed = markers.isEmpty ? nil : blocks[index == 0 ? markers[0] : start].pageNumber
            pages.append(ReaderPage(index: pages.count, printedNumber: printed, range: start..<end))
        }
        return pages
    }

    /// The page holding a block.
    static func pageIndex(of blockID: Int, in pages: [ReaderPage]) -> Int {
        pages.firstIndex { $0.range.contains(blockID) } ?? 0
    }

    private static func weight(of block: ReaderBlock) -> Int {
        switch block.kind {
        case .table: return max(400, block.rows.reduce(0) { $0 + $1.joined().count })
        case .image: return 300
        default: return max(40, block.text.count)
        }
    }
}

/// Long passages are cut into sentences before they are spoken. The speech
/// engine stalls on very long strings, and short pieces make pause, resume
/// and "where am I" precise.
enum SpeechChunker {
    static let maximumLength = 320

    static func chunks(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maximumLength else { return trimmed.isEmpty ? [] : [trimmed] }
        var pieces: [String] = []
        var current = ""
        func flush() {
            let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { pieces.append(piece) }
            current = ""
        }
        let enders: Set<Character> = [".", "!", "?", "؟", "؛", ";", "\n", "。"]
        for character in trimmed {
            current.append(character)
            if enders.contains(character), current.count >= 40 {
                flush()
            } else if current.count >= maximumLength {
                // No sentence end in sight: cut at the last space.
                if let space = current.lastIndex(where: { $0 == " " || $0 == "،" || $0 == "," }),
                   current.distance(from: current.startIndex, to: space) > maximumLength / 2 {
                    let head = String(current[...space])
                    let tail = String(current[current.index(after: space)...])
                    current = head
                    flush()
                    current = tail
                } else {
                    flush()
                }
            }
        }
        flush()
        return pieces
    }
}
