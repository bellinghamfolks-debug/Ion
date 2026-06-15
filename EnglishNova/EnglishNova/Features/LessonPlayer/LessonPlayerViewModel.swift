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
    var score: Double { Double(correctCount) / Double(max(lesson.exercises.count, 1)) }

    func submit(response: String? = nil) {
        guard !answered else { return }
        let value = response ?? selectedAnswer
        if current.type == .explanation || current.type == .flashcard {
            lastWasCorrect = true
        } else {
            lastWasCorrect = current.isCorrect(value)
        }
        if lastWasCorrect { correctCount += 1 }
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
