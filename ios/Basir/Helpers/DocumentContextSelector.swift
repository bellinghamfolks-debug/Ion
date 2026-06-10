import Foundation

/// Selects relevant excerpts from a long converted document for grounded Q&A.
/// The previous implementation silently sent only the first 12,000 characters,
/// so questions about later pages could never be answered. This selector scans
/// the whole locally held document, ranks bounded chunks against the question,
/// and returns a compact context that fits safely in one model request.
enum DocumentContextSelector {
    struct Selection: Sendable {
        let context: String
        let totalChunks: Int
        let selectedChunks: Int

        var isEmpty: Bool { context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var usesWholeDocument: Bool { totalChunks == selectedChunks }
    }

    private struct Chunk: Sendable {
        let index: Int
        let text: String
        let tokens: [String]
    }

    private static let stopWords: Set<String> = [
        "في", "من", "الى", "إلى", "على", "عن", "ما", "ماذا", "هل", "هو", "هي",
        "هذا", "هذه", "ذلك", "التي", "الذي", "و", "او", "أو", "ثم", "مع", "تم",
        "the", "a", "an", "of", "to", "in", "on", "for", "and", "or", "is", "are",
        "what", "when", "where", "who", "how", "does", "did", "this", "that"
    ]

    static func select(
        document: String,
        question: String,
        maxCharacters: Int = 30_000,
        targetChunkCharacters: Int = 2_400
    ) -> Selection {
        let cleanedDocument = document.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedDocument.isEmpty, maxCharacters >= 1_000 else {
            return Selection(context: "", totalChunks: 0, selectedChunks: 0)
        }

        let chunks = makeChunks(
            from: cleanedDocument,
            targetCharacters: max(800, min(targetChunkCharacters, 5_000))
        )
        guard !chunks.isEmpty else {
            return Selection(context: "", totalChunks: 0, selectedChunks: 0)
        }

        let queryTokens = Set(tokens(in: question))
        let normalizedQuestion = normalize(question)
        let ranked = chunks.map { chunk -> (index: Int, score: Int) in
            var score = 0
            let frequency = Dictionary(grouping: chunk.tokens, by: { $0 }).mapValues(\.count)
            for token in queryTokens {
                let hits = min(frequency[token] ?? 0, 3)
                guard hits > 0 else { continue }
                score += isCriticalToken(token) ? 12 * hits : 4 * hits
            }
            if normalizedQuestion.count >= 4,
               normalizedQuestion.count <= 160,
               normalize(chunk.text).contains(normalizedQuestion) {
                score += 20
            }
            return (chunk.index, score)
        }
        .sorted {
            if $0.score == $1.score { return $0.index < $1.index }
            return $0.score > $1.score
        }

        var priority: [Int] = []
        var seen = Set<Int>()
        func enqueue(_ index: Int) {
            guard chunks.indices.contains(index), seen.insert(index).inserted else { return }
            priority.append(index)
        }

        let positive = ranked.filter { $0.score > 0 }
        if positive.isEmpty {
            enqueue(0)
            enqueue(chunks.count / 2)
            enqueue(chunks.count - 1)
        } else {
            for item in positive.prefix(12) {
                // Include immediate context around each high-scoring chunk.
                enqueue(item.index)
                enqueue(item.index - 1)
                enqueue(item.index + 1)
            }
        }

        var selected: [Int] = []
        var usedCharacters = 0
        for index in priority {
            let textCount = chunks[index].text.count
            let estimated = textCount + 90
            if !selected.isEmpty && usedCharacters + estimated > maxCharacters { continue }
            selected.append(index)
            usedCharacters += estimated
            if usedCharacters >= maxCharacters { break }
        }
        if selected.isEmpty { selected = [priority.first ?? 0] }
        selected.sort()

        var sections: [String] = []
        var emittedCharacters = 0
        for index in selected {
            let header = "[Relevant excerpt \(sections.count + 1); source section \(index + 1) of \(chunks.count)]\n"
            let remaining = maxCharacters - emittedCharacters - header.count
            guard remaining > 0 else { break }
            let body = String(chunks[index].text.prefix(remaining))
            sections.append(header + body)
            emittedCharacters += header.count + body.count + 2
        }

        return Selection(
            context: sections.joined(separator: "\n\n"),
            totalChunks: chunks.count,
            selectedChunks: sections.count
        )
    }

    private static func makeChunks(from text: String, targetCharacters: Int) -> [Chunk] {
        let paragraphs = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var rawChunks: [String] = []
        var current = ""

        func flush() {
            let value = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { rawChunks.append(value) }
            current = ""
        }

        for paragraph in paragraphs {
            if paragraph.count > targetCharacters * 2 {
                flush()
                var cursor = paragraph.startIndex
                while cursor < paragraph.endIndex {
                    let end = paragraph.index(cursor, offsetBy: targetCharacters,
                                              limitedBy: paragraph.endIndex) ?? paragraph.endIndex
                    rawChunks.append(String(paragraph[cursor..<end]))
                    cursor = end
                }
                continue
            }

            let extra = current.isEmpty ? paragraph.count : paragraph.count + 1
            if !current.isEmpty && current.count + extra > targetCharacters { flush() }
            if !current.isEmpty { current += "\n" }
            current += paragraph
        }
        flush()

        return rawChunks.enumerated().map { index, value in
            Chunk(index: index, text: value, tokens: tokens(in: value))
        }
    }

    private static func tokens(in value: String) -> [String] {
        let normalized = normalize(value)
        guard let regex = try? NSRegularExpression(
            pattern: #"[\p{L}\p{N}][\p{L}\p{N}._/\-]{1,}"#
        ) else { return [] }
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        return regex.matches(in: normalized, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: normalized) else { return nil }
            let token = String(normalized[swiftRange])
            return stopWords.contains(token) ? nil : token
        }
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ar"))
            .replacingOccurrences(of: "أ", with: "ا")
            .replacingOccurrences(of: "إ", with: "ا")
            .replacingOccurrences(of: "آ", with: "ا")
            .replacingOccurrences(of: "ى", with: "ي")
            .lowercased()
    }

    private static func isCriticalToken(_ token: String) -> Bool {
        token.unicodeScalars.contains(where: CharacterSet.decimalDigits.contains)
            || token.contains("@")
            || token.contains("/")
            || token.contains("-")
    }
}
