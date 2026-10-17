import Foundation

extension RiyalNote {
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
/// note is named only when two independent readers agree: the classifier,
/// confident over several frames in a row, and the number printed on the
/// note, read as text. Measured on camera-like frames, either alone named
/// wrong values (the classifier on blank surfaces, the text on price tags);
/// together they named none.
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
    /// How long a note must be out of view before it may be named again.
    /// Longer while adding up, so turning a note over does not count it twice.
    var reshowGap: TimeInterval = 1

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
            if let spoken = lastSpoken, observation.time - lastNoteSeen > reshowGap, spoken.time < lastNoteSeen + 0.001 {
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
        let confident = recent.allSatisfy { $0.confidence >= minimumConfidence }
        return confident && printed == [note] ? .note(note) : .uncertain
    }
}
