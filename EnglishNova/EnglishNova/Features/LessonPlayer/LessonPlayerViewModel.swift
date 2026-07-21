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

    init(lesson: Lesson) { self.lesson = lesson }

    var current: Exercise { lesson.exercises[currentIndex] }
    var progress: Double { Double(currentIndex + (answered ? 1 : 0)) / Double(max(lesson.exercises.count, 1)) }

    /// Only real questions are graded; explanations and flashcards are
    /// informational and must NOT count toward the score.
    private static func isGraded(_ type: ExerciseType) -> Bool {
        type != .explanation && type != .flashcard
    }
    private var gradedCount: Int { lesson.exercises.filter { Self.isGraded($0.type) }.count }

    /// Score over graded questions only. A lesson with no graded questions
    /// (pure explanation) counts as fully complete.
    var score: Double { gradedCount == 0 ? 1 : Double(correctCount) / Double(gradedCount) }

    func submit(response: String? = nil) {
        guard !answered else { return }
        let value = response ?? selectedAnswer
        if Self.isGraded(current.type) {
            lastWasCorrect = current.isCorrect(value)
            if lastWasCorrect { correctCount += 1 }   // only graded answers score
        } else {
            lastWasCorrect = true   // informational: shown as done, not scored
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
