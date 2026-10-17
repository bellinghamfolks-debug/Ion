import Foundation

/// Saudi riyal banknotes the currency reader names.
enum RiyalNote: Int, CaseIterable, Codable, Sendable {
    case one = 1, five = 5, ten = 10, twenty = 20, fifty = 50, hundred = 100, twoHundred = 200, fiveHundred = 500

    /// The model's class label for this note.
    var label: String { String(rawValue) }

    init?(label: String) {
        guard let value = Int(label.trimmingCharacters(in: .whitespaces)) else { return nil }
        self.init(rawValue: value)
    }

    /// How the note is said: the way people say it, with correct Arabic number agreement.
    @MainActor
    func spoken(_ l10n: L10n) -> String {
        switch self {
        case .one: return l10n.t("ريال واحد", "One riyal")
        case .five: return l10n.t("خمسة ريالات", "Five riyals")
        case .ten: return l10n.t("عشرة ريالات", "Ten riyals")
        case .twenty: return l10n.t("عشرون ريالًا", "Twenty riyals")
        case .fifty: return l10n.t("خمسون ريالًا", "Fifty riyals")
        case .hundred: return l10n.t("مئة ريال", "One hundred riyals")
        case .twoHundred: return l10n.t("مئتا ريال", "Two hundred riyals")
        case .fiveHundred: return l10n.t("خمسمئة ريال", "Five hundred riyals")
        }
    }

    /// A distinct number of taps for each note, smallest to largest, so the
    /// value can be felt without listening.
    var hapticTaps: Int { (RiyalNote.allCases.firstIndex(of: self) ?? 0) + 1 }
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

/// One camera frame's evidence.
struct CurrencyObservation: Equatable, Sendable {
    /// The model's best class and its confidence; nil when it saw no note.
    var note: RiyalNote?
    var confidence: Double
    /// Values read in the frame's printed text.
    var printed: Set<RiyalNote> = []
    var time: TimeInterval
}

/// Decides when to speak, from a stream of frames.
///
/// A wrong value is worse than none for someone who cannot check it, so a
/// note is named only when several frames in a row agree with high
/// confidence, and never when the printed number on the note says otherwise.
struct CurrencyVoter {
    enum Verdict: Equatable {
        case note(RiyalNote)
        case uncertain
        case nothing
    }

    var requiredFrames = 3
    var minimumConfidence = 0.85
    /// The same note is not repeated while it stays in view.
    var repeatAfter: TimeInterval = 4

    private(set) var history: [CurrencyObservation] = []
    private var lastSpoken: (note: RiyalNote, time: TimeInterval)?
    private var lastNoteSeen: TimeInterval = 0

    mutating func add(_ observation: CurrencyObservation) -> Verdict? {
        history.append(observation)
        if history.count > 8 { history.removeFirst(history.count - 8) }
        if observation.note != nil && observation.confidence >= 0.5 { lastNoteSeen = observation.time }
        let verdict = decide()
        guard case .note(let note) = verdict else {
            // A note taken away and shown again may be named again.
            if let spoken = lastSpoken, observation.time - lastNoteSeen > 1.0, spoken.time < lastNoteSeen + 0.001 {
                lastSpoken = nil
            }
            return verdict == .uncertain ? .uncertain : nil
        }
        if let spoken = lastSpoken, spoken.note == note, observation.time - spoken.time < repeatAfter {
            return nil
        }
        lastSpoken = (note, observation.time)
        return .note(note)
    }

    func decide() -> Verdict {
        let recent = history.suffix(requiredFrames)
        guard recent.count == requiredFrames else { return .nothing }
        let notes = Set(recent.compactMap(\.note))
        guard notes.count == 1, let note = notes.first, recent.allSatisfy({ $0.note == note }) else {
            return recent.contains(where: { $0.note != nil }) ? .uncertain : .nothing
        }
        let printed = recent.reduce(into: Set<RiyalNote>()) { $0.formUnion($1.printed) }
        if !printed.isEmpty && !printed.contains(note) { return .uncertain }
        let confident = recent.allSatisfy { $0.confidence >= minimumConfidence }
        // The printed value confirming the model can stand in for a little confidence.
        let confirmed = printed == [note] && recent.allSatisfy { $0.confidence >= minimumConfidence - 0.15 }
        return confident || confirmed ? .note(note) : .uncertain
    }
}
