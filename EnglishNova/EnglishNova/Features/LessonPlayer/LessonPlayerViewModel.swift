import Foundation
import Combine

@MainActor
final class LessonPlayerViewModel: ObservableObject {
    enum Phase { case lesson, result }

    let lesson: Lesson
    @Published var currentIndex = 0
    @Published var selectedAnswer = ""
    @Published var arrangedTokens: [String] = []
    @Published var correctCount = 0
    @Published var answered = false
    @Published var lastWasCorrect = false
    @Published var phase: Phase = .lesson
    @Published var startedAt = Date()
    @Published private(set) var evidence: [LessonExerciseEvidence] = []

    init(lesson: Lesson) { self.lesson = lesson }

    var current: Exercise { lesson.exercises[currentIndex] }
    var progress: Double { Double(currentIndex + (answered ? 1 : 0)) / Double(max(lesson.exercises.count, 1)) }

    private static func isGraded(_ type: ExerciseType) -> Bool {
        type != .explanation && type != .flashcard
    }

    var assessment: LessonAssessment {
        LessonAssessmentEngine.evaluate(level: lesson.levelHint, evidence: evidence)
    }

    var score: Double { assessment.masteryScore }

    func submit(response: String? = nil) {
        guard !answered else { return }
        let value = response ?? selectedAnswer
        if Self.isGraded(current.type) {
            lastWasCorrect = current.isCorrect(value)
            if lastWasCorrect { correctCount += 1 }
            evidence.append(LessonExerciseEvidence(
                type: current.type,
                wasCorrect: lastWasCorrect,
                choiceCount: current.choices?.count ?? 0
            ))
        } else {
            lastWasCorrect = true
        }
        answered = true
    }

    func submitArranged() { submit(response: arrangedTokens.joined(separator: " ")) }

    func continueNext() {
        guard answered else { return }
        if currentIndex + 1 < lesson.exercises.count {
            currentIndex += 1
            selectedAnswer = ""
            arrangedTokens = []
            answered = false
            lastWasCorrect = false
        } else {
            phase = .result
        }
    }

    var elapsedMinutes: Int { max(1, Int(Date().timeIntervalSince(startedAt) / 60)) }
}

private extension Lesson {
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
