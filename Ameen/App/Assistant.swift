import Foundation

enum Assistant {
    static let categories = ["طعام ومقاهٍ", "مواصلات", "تسوق", "فواتير", "صحة", "سكن", "ترفيه", "أخرى"]
    private static let examples = [
        ["قهوة", "مطعم", "عشاء", "غداء", "بقالة", "فطور", "سوبرماركت", "قهوه", "كافيه"],
        ["بنزين", "أوبر", "تاكسي", "مترو", "مواقف"], ["ملابس", "أمازون", "نون", "تسوق"],
        ["فاتورة", "كهرباء", "انترنت", "جوال"], ["صيدلية", "دواء", "عيادة", "طبيب"],
        ["إيجار", "أثاث", "صيانة"], ["سينما", "لعبة", "تذكرة"]
    ]
    static func normalize(_ s: String) -> String {
        Money.digits(s).lowercased().replacingOccurrences(of: #"[\u064B-\u0652ـ]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[إأآ]"#, with: "ا", options: .regularExpression)
            .replacingOccurrences(of: "ة", with: "ه")
    }
    private static func tokens(_ s: String) -> Set<String> {
        let skip: Set<String> = ["ريال", "دفعت", "صرفت", "اشتريت", "على", "من", "في", "اليوم", "امس", "مبلغ", "عند"]
        return Set(normalize(s).components(separatedBy: CharacterSet.letters.inverted).filter { $0.count > 1 && !skip.contains($0) })
    }
    // A nearest-neighbour classifier over confirmed entries supplements the seed vocabulary.
    static func category(for text: String, history: [Entry]) -> String {
        let s = normalize(text), words = tokens(text)
        var scores: [String: Double] = [:]
        for (i, seeds) in examples.enumerated() where seeds.contains(where: { s.contains(normalize($0)) }) {
            scores[categories[i]] = 0.55
        }
        for entry in history.suffix(500) where entry.kind == .expense {
            let other = tokens(entry.title), common = words.intersection(other).count
            guard common > 0 else { continue }
            let similarity = Double(common) / Double(words.union(other).count)
            scores[entry.category] = max(scores[entry.category] ?? 0, similarity)
        }
        let best = scores.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.first
        return (best?.value ?? 0) >= 0.45 ? best!.key : "أخرى"
    }
    struct Draft {
        var kind: EntryKind
        var title: String
        var amount: String
        var category: String
        var date: Date
    }
    static func draft(_ text: String, history: [Entry], now: Date = Date()) throws -> Draft {
        let s = normalize(text)
        let regex = try NSRegularExpression(pattern: #"[+-]?[0-9][0-9,.]*"#)
        let matches = regex.matches(in: s, range: NSRange(s.startIndex..., in: s))
        guard matches.count == 1, let range = Range(matches[0].range, in: s), let cents = Money.parse(String(s[range])) else {
            throw ParseError.amount
        }
        let kind: EntryKind
        if ["استلفت", "اقترضت", "علي دين", "عليّ دين", "دين علي", "علي ل"].contains(where: s.contains) { kind = .owing }
        else if ["اقرضت", "سلفت", "لي عند", "لي دين", "دين لي"].contains(where: s.contains) { kind = .owed }
        else if ["راتب", "استلمت", "دخل", "مكافاه", "ايراد"].contains(where: s.contains) { kind = .income }
        else { kind = .expense }
        let date = s.contains("امس") ? Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now : now
        return Draft(kind: kind, title: text.trimmingCharacters(in: .whitespacesAndNewlines), amount: Money.input(cents), category: category(for: text, history: history), date: date)
    }
    enum ParseError: LocalizedError {
        case amount
        var errorDescription: String? { "اكتب مبلغًا واحدًا بالأرقام، مثل «دفعت ٣٥٫٥٠ ريال للقهوة»." }
    }
}
