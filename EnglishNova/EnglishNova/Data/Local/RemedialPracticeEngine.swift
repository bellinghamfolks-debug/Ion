import Foundation

/// Lesson mistakes carry an id that points back to the original exercise:
/// `lesson|<lessonID>|<exerciseID>|<unique>`. That lets remedial practice
/// replay the real item (with its choices, audio and tokens) instead of a
/// flattened text copy.
enum LessonMistakeFactory {
    static let prefix = "lesson|"

    static func make(lessonID: String, source: String, exercise: Exercise, response: String, now: Date = .now) -> LearningMistake {
        let prompt = [exercise.displayPrompt, exercise.promptEn ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return LearningMistake(
            id: "\(prefix)\(lessonID)|\(exercise.id)|\(UUID().uuidString)",
            category: LE("الدروس", "Lessons"),
            source: source,
            prompt: prompt,
            learnerAnswer: exercise.readable(response),
            correction: exercise.displayAnswer,
            explanationAr: exercise.display(exercise.explanationAr),
            createdAt: now,
            reviewCount: 0,
            resolved: false
        )
    }

    /// `(lessonID, exerciseID)` for a lesson mistake, or nil for other sources.
    static func reference(from mistakeID: String) -> (lessonID: String, exerciseID: String)? {
        guard mistakeID.hasPrefix(prefix) else { return nil }
        let parts = mistakeID.dropFirst(prefix.count).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }
}

/// One remedial item: the exercise to practise and the mistake it came from.
struct RemedialItem: Identifiable, Hashable {
    let mistakeID: String
    let exercise: Exercise
    var id: String { mistakeID }
}

/// Builds a short practice set from unresolved mistakes, newest and most
/// repeated first. Lesson mistakes replay the original exercise; mistakes
/// from other features (writing, conversation, pronunciation, exams) become
/// a typed "write the correct form" item.
enum RemedialPracticeEngine {
    static let defaultLimit = 8

    static func items(mistakes: [LearningMistake], catalog: CourseCatalog?, limit: Int = defaultLimit) -> [RemedialItem] {
        let lessons: [String: Lesson] = Dictionary(
            (catalog?.levels ?? []).flatMap { $0.units.flatMap(\.lessons) }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let open = mistakes
            .filter { !$0.resolved }
            .sorted {
                if $0.reviewCount != $1.reviewCount { return $0.reviewCount > $1.reviewCount }
                return $0.createdAt > $1.createdAt
            }

        var result: [RemedialItem] = []
        var seenExercises = Set<String>()
        for mistake in open {
            guard result.count < limit else { break }
            if let ref = LessonMistakeFactory.reference(from: mistake.id), let lesson = lessons[ref.lessonID] {
                let pool = ExerciseSynthesizer.sequence(for: lesson)
                if let exercise = pool.first(where: { $0.id == ref.exerciseID }), exercise.type.isGraded {
                    guard seenExercises.insert(exercise.id).inserted else { continue }
                    result.append(RemedialItem(mistakeID: mistake.id, exercise: exercise))
                    continue
                }
            }
            if let typed = typedItem(for: mistake) {
                result.append(RemedialItem(mistakeID: mistake.id, exercise: typed))
            }
        }
        return result
    }

    private static func typedItem(for mistake: LearningMistake) -> Exercise? {
        let correction = mistake.correction.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only Latin-script corrections can be checked by typing in English.
        guard !correction.isEmpty,
              correction.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil,
              correction.count <= 160 else { return nil }
        let prompt = mistake.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return Exercise(
            id: "syn-remedial-\(mistake.id)",
            type: .fillBlank,
            promptAr: LE("اكتب الصيغة الصحيحة", "Write the correct form"),
            promptEn: prompt.isEmpty ? nil : prompt,
            answer: correction,
            choices: nil,
            tokens: nil,
            explanationAr: mistake.explanationAr,
            accessibilityHint: LE("اكتب الإجابة بالإنجليزية، ثم اضغط تحقق.", "Type the answer in English, then tap Check."),
            speechText: nil, // speaking the answer would give it away
            acceptableAnswers: nil
        )
    }
}
