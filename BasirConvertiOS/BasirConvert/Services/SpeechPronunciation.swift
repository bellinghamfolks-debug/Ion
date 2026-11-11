import Foundation

/// Speech-only substitutions. Original documents, quotes and translations
/// are never rewritten by a pronunciation preference.
enum SpeechPronunciation {
    static func apply(_ text: String, rules: String = UserDefaults.standard.string(forKey: "basir_pronunciation_rules") ?? "") -> String {
        var result = text
        for line in rules.components(separatedBy: .newlines).prefix(60) {
            let pair = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2, !pair[0].isEmpty, !pair[1].isEmpty, pair[0].count <= 100, pair[1].count <= 200 else { continue }
            let escaped = NSRegularExpression.escapedPattern(for: pair[0])
            guard let expression = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])" + escaped + "(?![\\p{L}\\p{N}])", options: .caseInsensitive) else { continue }
            result = expression.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: NSRegularExpression.escapedTemplate(for: pair[1]))
        }
        return result
    }
}
