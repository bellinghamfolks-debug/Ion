import Foundation

// Kept free of app types so the measuring tools in tools/currency compile it as is.

/// Saudi riyal banknotes the currency reader names.
enum RiyalNote: Int, CaseIterable, Codable, Sendable {
    case one = 1, five = 5, ten = 10, twenty = 20, fifty = 50, hundred = 100, twoHundred = 200, fiveHundred = 500

    /// The model's class label for this note.
    var label: String { String(rawValue) }

    init?(label: String) {
        guard let value = Int(label.trimmingCharacters(in: .whitespaces)) else { return nil }
        self.init(rawValue: value)
    }

    /// A distinct number of taps for each note, smallest to largest, so the
    /// value can be felt without listening.
    var hapticTaps: Int { (RiyalNote.allCases.firstIndex(of: self) ?? 0) + 1 }
}

/// A total as it is read aloud, with the noun agreeing with the number:
/// "8 ريالات", "70 ريالًا", "100 ريال".
enum RiyalAmount {
    static func arabic(_ amount: Int) -> String {
        let lastTwo = amount % 100
        let noun = (3...10).contains(lastTwo) ? "ريالات" : (11...99).contains(lastTwo) ? "ريالًا" : "ريال"
        return "\(amount) \(noun)"
    }

    static func english(_ amount: Int) -> String { amount == 1 ? "1 riyal" : "\(amount) riyals" }
}

/// The values printed on a note, found in recognised text. Serial numbers
/// are long runs of digits, so only a short number that is exactly a
/// denomination counts, in Western or Arabic-Indic digits, or in words.
enum PrintedValue {
    private static let words: [(String, RiyalNote)] = [
        ("خمسمائة", .fiveHundred), ("خمسمئة", .fiveHundred), ("خمس مائة", .fiveHundred),
        ("مائتا", .twoHundred), ("مئتا", .twoHundred), ("مائتان", .twoHundred), ("مئتان", .twoHundred),
        ("مائة", .hundred), ("مئة", .hundred),
        ("خمسون", .fifty), ("عشرون", .twenty), ("عشرة", .ten), ("خمسة", .five), ("ريال واحد", .one),
        ("five hundred", .fiveHundred), ("two hundred", .twoHundred), ("one hundred", .hundred),
        ("fifty", .fifty), ("twenty", .twenty), ("ten", .ten), ("five", .five), ("one riyal", .one),
    ]

    static func notes(in lines: [String]) -> Set<RiyalNote> {
        var found = Set<RiyalNote>()
        for line in lines {
            let latin = toLatinDigits(line)
            let tokens = latin.split(whereSeparator: { !$0.isNumber })
            for token in tokens where token.count <= 3 {
                if let value = Int(token), let note = RiyalNote(rawValue: value), value != 1 { found.insert(note) }
            }
            let lowered = line.lowercased()
            // Longest phrases first, so "خمسمائة" is not also read as "مائة".
            var remaining = lowered
            for (phrase, note) in words where remaining.contains(phrase) {
                found.insert(note)
                remaining = remaining.replacingOccurrences(of: phrase, with: " ")
            }
        }
        return found
    }

    static func toLatinDigits(_ text: String) -> String {
        String(text.map { character -> Character in
            guard let scalar = character.unicodeScalars.first else { return character }
            switch scalar.value {
            case 0x0660...0x0669: return Character(String(scalar.value - 0x0660))
            case 0x06F0...0x06F9: return Character(String(scalar.value - 0x06F0))
            default: return character
            }
        })
    }
}
