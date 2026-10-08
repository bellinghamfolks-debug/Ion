import Foundation

/// An exact, on-device comparison of two versions of a document, paragraph
/// by paragraph. Nothing is guessed: what it lists is what changed.
enum TextComparison {
    struct Change: Identifiable, Equatable, Sendable {
        enum Kind: Equatable, Sendable { case added, removed, changed }
        let id: Int
        let kind: Kind
        let before: String
        let after: String
    }

    static func paragraphs(of blocks: [ReaderBlock]) -> [String] {
        blocks.compactMap { block -> String? in
            guard block.pageNumber == nil else { return nil }
            let text = block.kind == .table
                ? block.rows.map { $0.joined(separator: " | ") }.joined(separator: "\n")
                : block.text
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    static func compare(old: [String], new: [String]) -> [Change] {
        let oldKeys = old.map(DocumentAssistant.normalized)
        let newKeys = new.map(DocumentAssistant.normalized)
        let difference = newKeys.difference(from: oldKeys)
        var removed: [Int: String] = [:]
        var inserted: [Int: String] = [:]
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed[offset] = old[offset]
            case .insert(let offset, _, _): inserted[offset] = new[offset]
            }
        }
        // Walk both documents in order, pairing a removal with the insertion
        // that takes its place as one "changed" paragraph.
        var changes: [Change] = []
        var oldIndex = 0, newIndex = 0
        while oldIndex < old.count || newIndex < new.count {
            let gone = removed[oldIndex]
            let came = inserted[newIndex]
            if let gone, let came {
                changes.append(Change(id: changes.count, kind: .changed, before: gone, after: came))
                oldIndex += 1; newIndex += 1
            } else if let gone {
                changes.append(Change(id: changes.count, kind: .removed, before: gone, after: ""))
                oldIndex += 1
            } else if let came {
                changes.append(Change(id: changes.count, kind: .added, before: "", after: came))
                newIndex += 1
            } else {
                oldIndex += 1; newIndex += 1
            }
        }
        return changes
    }
}
