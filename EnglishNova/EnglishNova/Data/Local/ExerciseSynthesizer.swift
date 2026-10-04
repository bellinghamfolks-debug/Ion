import Foundation

/// Builds extra practice items from a lesson's own vocabulary so every lesson
/// gets matching, listening, dictation and quick true/false checks without
/// changing the bundled curriculum file (whose checksum is part of the
/// release fingerprint).
///
/// Output is deterministic for a given lesson: the same learner sees the same
/// items on every attempt, and tests can assert exact results.
enum ExerciseSynthesizer {
    static let maximumPerLesson = 4

    static func exercises(for lesson: Lesson) -> [Exercise] {
        var seenEnglish = Set<String>()
        var seenArabic = Set<String>()
        let words = lesson.vocabulary.filter { word in
            guard isUsable(word) else { return false }
            let english = word.english.lowercased()
            guard !seenEnglish.contains(english), !seenArabic.contains(word.arabic) else { return false }
            seenEnglish.insert(english)
            seenArabic.insert(word.arabic)
            return true
        }
        guard words.count >= 2 else { return [] }
        var generator = SeededGenerator(seed: stableSeed(lesson.id))
        var output: [Exercise] = []

        if words.count >= 3 {
            output.append(matchPairs(lesson: lesson, words: Array(words.prefix(4)), generator: &generator))
        }

        let tfWord = words[Int(generator.next() % UInt64(words.count))]
        output.append(trueFalse(lesson: lesson, word: tfWord, words: words, generator: &generator))

        let listenWord = words[Int(generator.next() % UInt64(words.count))]
        output.append(listenType(lesson: lesson, word: listenWord))

        if let sentence = dictationSentence(for: lesson, words: words) {
            output.append(dictation(lesson: lesson, sentence: sentence))
        }

        return Array(output.prefix(maximumPerLesson))
    }

    /// Lesson exercises with the synthesized ones woven into the second half,
    /// after the learner has met the words in flashcards and recognition items.
    static func sequence(for lesson: Lesson) -> [Exercise] {
        let base = lesson.exercises
        let extra = exercises(for: lesson)
        guard !extra.isEmpty else { return base }

        // Keep a closing explanation (lesson summary) at the very end.
        var head = base
        var tail: [Exercise] = []
        if let last = head.last, last.type == .explanation, head.count > 1 {
            tail = [head.removeLast()]
        }

        let start = max(1, head.count / 2)
        let span = max(1, head.count - start)
        var result = head
        for (offset, item) in extra.enumerated().reversed() {
            let position = start + (span * (offset + 1)) / (extra.count + 1)
            // Inserting from the last position backwards keeps earlier indices valid.
            result.insert(item, at: min(result.count, position))
        }
        return result + tail
    }

    // MARK: - Builders

    private static func matchPairs(lesson: Lesson, words: [VocabularyWord], generator: inout SeededGenerator) -> Exercise {
        let english = words.map { $0.english }
        let arabic = words.map { $0.arabic }.shuffled(using: &generator)
        let answer = Exercise.encodePairs(words.map { ($0.english, $0.arabic) })
        return Exercise(
            id: "syn-\(lesson.id)-match",
            type: .matchPairs,
            promptAr: LE("صِل كل كلمة بمعناها", "Match each word to its meaning"),
            promptEn: nil,
            answer: answer,
            choices: arabic,
            tokens: english,
            explanationAr: words.map { "\($0.english) = \($0.arabic)" }.joined(separator: "\n"),
            accessibilityHint: LE("اختر معنى كل كلمة من القائمة بجانبها، ثم اضغط تحقق.", "Pick a meaning for each word from its menu, then tap Check."),
            speechText: nil,
            acceptableAnswers: nil
        )
    }

    private static func trueFalse(lesson: Lesson, word: VocabularyWord, words: [VocabularyWord], generator: inout SeededGenerator) -> Exercise {
        let others = words.filter { $0.id != word.id && $0.arabic != word.arabic }
        let useTruth = others.isEmpty || generator.next() % 2 == 0
        let meaning = useTruth ? word.arabic : others[Int(generator.next() % UInt64(others.count))].arabic
        let correct = "\(word.english) = \(word.arabic)"
        return Exercise(
            id: "syn-\(lesson.id)-tf",
            type: .trueFalse,
            promptAr: LfE("هل تعني كلمة «%@»: %@؟", "Does “%@” mean “%@”?", word.english, meaning),
            promptEn: nil,
            answer: useTruth ? "true" : "false",
            choices: ["true", "false"],
            tokens: nil,
            explanationAr: correct,
            accessibilityHint: LE("اختر صح أو خطأ، ثم اضغط تحقق.", "Choose true or false, then tap Check."),
            speechText: word.english,
            acceptableAnswers: nil
        )
    }

    private static func listenType(lesson: Lesson, word: VocabularyWord) -> Exercise {
        Exercise(
            id: "syn-\(lesson.id)-listen",
            type: .listenType,
            promptAr: LE("استمع، ثم اكتب الكلمة التي سمعتها", "Listen, then type the word you hear"),
            promptEn: nil,
            answer: word.english,
            choices: nil,
            tokens: nil,
            explanationAr: "\(word.english) = \(word.arabic)",
            accessibilityHint: LE("شغّل الصوت، ثم اكتب الكلمة بالإنجليزية.", "Play the audio, then type the word in English."),
            speechText: word.english,
            acceptableAnswers: nil
        )
    }

    private static func dictation(lesson: Lesson, sentence: String) -> Exercise {
        Exercise(
            id: "syn-\(lesson.id)-dictation",
            type: .dictation,
            promptAr: LE("إملاء: استمع إلى الجملة واكتبها كاملة", "Dictation: listen and type the whole sentence"),
            promptEn: nil,
            answer: sentence,
            choices: nil,
            tokens: nil,
            explanationAr: sentence,
            accessibilityHint: LE("شغّل الجملة مرة أو أكثر، ثم اكتبها بالإنجليزية.", "Play the sentence as often as you need, then type it in English."),
            speechText: sentence,
            acceptableAnswers: nil
        )
    }

    // MARK: - Helpers

    private static func isUsable(_ word: VocabularyWord) -> Bool {
        let english = word.english.trimmingCharacters(in: .whitespacesAndNewlines)
        let arabic = word.arabic.trimmingCharacters(in: .whitespacesAndNewlines)
        // `|` and `=` are the matchPairs encoding separators.
        return !english.isEmpty && !arabic.isEmpty
            && !english.contains("|") && !english.contains("=")
            && !arabic.contains("|") && !arabic.contains("=")
    }

    /// A real sentence from the lesson: prefer the arrange-words answer, then
    /// a vocabulary example that is not one of the generic "key word" fillers.
    static func dictationSentence(for lesson: Lesson, words: [VocabularyWord]) -> String? {
        let candidates = lesson.exercises.filter { $0.type == .arrangeWords }.map(\.answer)
            + words.map(\.example)
            + lesson.exercises.filter { $0.type == .translation }.map(\.answer)
        return candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { sentence in
                let count = sentence.split(separator: " ").count
                let lower = sentence.lowercased()
                return (3...12).contains(count)
                    && !lower.contains("key word")
                    && !lower.contains("today’s")
                    && !lower.contains("today's")
                    && sentence.range(of: #"[؀-ۿ]"#, options: .regularExpression) == nil
            }
    }

    /// FNV-1a; `String.hashValue` is randomized per launch and unusable here.
    static func stableSeed(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

/// SplitMix64 — tiny, deterministic and good enough for shuffling choices.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
