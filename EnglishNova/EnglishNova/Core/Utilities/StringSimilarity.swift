import Foundation

enum StringSimilarity {
    static func normalized(_ value: String) -> String {
        value.lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func score(_ lhs: String, _ rhs: String) -> Double {
        let a = Array(normalized(lhs))
        let b = Array(normalized(rhs))
        guard !a.isEmpty || !b.isEmpty else { return 1 }
        let distance = levenshtein(a, b)
        return max(0, 1 - Double(distance) / Double(max(a.count, b.count)))
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        for (i, ca) in a.enumerated() {
            var current = [i + 1]
            for (j, cb) in b.enumerated() {
                current.append(min(current[j] + 1, previous[j + 1] + 1, previous[j] + (ca == cb ? 0 : 1)))
            }
            previous = current
        }
        return previous[b.count]
    }
}
