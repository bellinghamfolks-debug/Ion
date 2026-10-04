import Foundation
import Combine

@MainActor
final class LessonPlayerViewModel: ObservableObject {
    enum Phase { case lesson, result }

    /// One step in the player. Retry steps replay an item the learner missed;
    /// they teach, but never change the score (evidence is first-attempt only).
    struct Step: Identifiable, Hashable {
        let exercise: Exercise
        let isRetry: Bool
        var id: String { (isRetry ? "retry-" : "") + exercise.id }
    }

    let lesson: Lesson
    @Published private(set) var steps: [Step]
    @Published var currentIndex = 0
    @Published var selectedAnswer = ""
    @Published var arrangedTokens: [String] = []
    @Published var correctCount = 0
    @Published var answered = false
    @Published var lastWasCorrect = false
    @Published var phase: Phase = .lesson
    @Published var startedAt = Date()
    @Published private(set) var evidence: [LessonExerciseEvidence] = []
    /// Graded items answered wrongly on the first attempt.
    @Published private(set) var missed: [Exercise] = []
    /// Missed items the learner got right in the retry round.
    @Published private(set) var recoveredIDs: Set<String> = []
    @Published private(set) var retryRoundStarted = false

    /// Called once per first-attempt mistake so it can feed remedial practice.
    var onMistake: ((Exercise, String) -> Void)?

    init(lesson: Lesson, includeSynthesized: Bool = true) {
        self.lesson = lesson
        let exercises = includeSynthesized ? ExerciseSynthesizer.sequence(for: lesson) : lesson.exercises
        self.steps = exercises.map { Step(exercise: $0, isRetry: false) }
    }

    var currentStep: Step { steps[currentIndex] }
    var current: Exercise { currentStep.exercise }
    var isRetry: Bool { currentStep.isRetry }

    var progress: Double { Double(currentIndex + (answered ? 1 : 0)) / Double(max(steps.count, 1)) }

    /// Position among graded first-attempt questions, for "Question n of N".
    var questionPosition: (index: Int, total: Int)? {
        guard current.type.isGraded, !isRetry else { return nil }
        let graded = steps.filter { !$0.isRetry && $0.exercise.type.isGraded }
        guard let index = graded.firstIndex(of: currentStep) else { return nil }
        return (index + 1, graded.count)
    }

    var retryPosition: (index: Int, total: Int)? {
        guard isRetry else { return nil }
        let retries = steps.filter(\.isRetry)
        guard let index = retries.firstIndex(of: currentStep) else { return nil }
        return (index + 1, retries.count)
    }

    var assessment: LessonAssessment {
        LessonAssessmentEngine.evaluate(level: lesson.levelHint, evidence: evidence)
    }

    var score: Double { assessment.masteryScore }

    func submit(response: String? = nil) {
        guard !answered else { return }
        let value = response ?? selectedAnswer
        if current.type.isGraded {
            lastWasCorrect = current.isCorrect(value)
            if isRetry {
                if lastWasCorrect { recoveredIDs.insert(current.id) }
            } else {
                if lastWasCorrect { correctCount += 1 }
                evidence.append(LessonExerciseEvidence(
                    type: current.type,
                    wasCorrect: lastWasCorrect,
                    choiceCount: Self.choiceCount(for: current)
                ))
                if !lastWasCorrect {
                    missed.append(current)
                    onMistake?(current, value)
                }
            }
            FeedbackSoundEngine.shared.play(lastWasCorrect ? .correct : .incorrect)
        } else {
            lastWasCorrect = true
        }
        answered = true
    }

    func submitArranged() { submit(response: arrangedTokens.joined(separator: " ")) }

    func continueNext() {
        guard answered else { return }
        if currentIndex + 1 >= steps.count, !retryRoundStarted, !missed.isEmpty {
            // One correction round: replay each missed item once.
            retryRoundStarted = true
            steps.append(contentsOf: missed.map { Step(exercise: $0, isRetry: true) })
        }
        if currentIndex + 1 < steps.count {
            currentIndex += 1
            selectedAnswer = ""
            arrangedTokens = []
            answered = false
            lastWasCorrect = false
        } else {
            phase = .result
            FeedbackSoundEngine.shared.play(assessment.passed ? .lessonComplete : .failure)
        }
    }

    /// True on the first retry step, so the view can announce the new round.
    var isFirstRetryStep: Bool {
        isRetry && (currentIndex == 0 || !steps[currentIndex - 1].isRetry)
    }

    var elapsedMinutes: Int { max(1, Int(Date().timeIntervalSince(startedAt) / 60)) }

    /// Chance-level baseline for receptive scoring. Matching n pairs at random
    /// is right with probability 1/n!, so it is treated as n! options.
    static func choiceCount(for exercise: Exercise) -> Int {
        switch exercise.type {
        case .matchPairs:
            let n = max(1, min((exercise.tokens ?? []).count, 6))
            return (1...n).reduce(1, *)
        case .trueFalse:
            return 2
        default:
            return exercise.choices?.count ?? 0
        }
    }
}

extension Lesson {
    var levelHint: CEFRLevel {
        let lower = id.lowercased()
        if lower.contains("c1") { return .c1 }
        if lower.contains("b2") { return .b2 }
        if lower.contains("b1") { return .b1 }
        if lower.contains("a2") { return .a2 }
        if lower.contains("a1") { return .a1 }
        return .a0
    }
}
