import Foundation
import Combine

@MainActor
final class LessonReviewQueueViewModel: ObservableObject {
    @Published private(set) var candidates: [LessonReviewCandidate] = []
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?

    var due: [LessonReviewCandidate] { candidates.filter(\.isDue) }
    var dueCount: Int { due.count }
    var completedCount: Int { candidates.count }
    var nextDue: LessonReviewCandidate? { candidates.first(where: { !$0.isDue }) }

    func load(
        courseRepository: CourseRepositoryProtocol,
        progressRepository: ProgressRepositoryProtocol,
        now: Date = .now
    ) async {
        isLoading = true
        errorMessage = nil
        do {
            let catalog = try await courseRepository.catalog()
            let snapshot = await progressRepository.snapshot()
            candidates = LessonReviewEngine.allCandidates(catalog: catalog, snapshot: snapshot, now: now)
        } catch {
            candidates = []
            errorMessage = LE("تعذر تحميل الدروس المجتازة.", "Completed lessons could not be loaded.")
        }
        isLoading = false
    }
}

@MainActor
final class LessonReviewSessionViewModel: ObservableObject {
    enum Phase { case review, result }

    let candidate: LessonReviewCandidate
    let exercises: [Exercise]

    @Published var currentIndex = 0
    @Published var selectedAnswer = ""
    @Published var arrangedTokens: [String] = []
    @Published var answered = false
    @Published var lastWasCorrect = false
    @Published var phase: Phase = .review
    @Published private(set) var evidence: [LessonExerciseEvidence] = []
    @Published private(set) var startedAt = Date()

    init(candidate: LessonReviewCandidate) {
        self.candidate = candidate
        self.exercises = LessonReviewEngine.reviewExercises(
            for: candidate.lesson,
            reviewCount: candidate.state?.repetitions ?? 0
        )
        if exercises.isEmpty { phase = .result }
    }

    var current: Exercise? {
        exercises.indices.contains(currentIndex) ? exercises[currentIndex] : nil
    }

    var progress: Double {
        guard !exercises.isEmpty else { return 1 }
        return Double(currentIndex + (answered ? 1 : 0)) / Double(exercises.count)
    }

    var assessment: LessonAssessment {
        LessonAssessmentEngine.evaluate(level: candidate.lesson.reviewLevel, evidence: evidence)
    }

    var score: Double { assessment.masteryScore }
    var scorePercent: Int { assessment.percent }

    var predictedState: LessonReviewState {
        LessonReviewEngine.updatedState(
            lessonID: candidate.lesson.id,
            current: candidate.state,
            score: score,
            now: .now
        )
    }

    var elapsedMinutes: Int {
        max(1, Int(Date().timeIntervalSince(startedAt) / 60))
    }

    func submit(response: String? = nil) {
        guard !answered, let current else { return }
        let value = response ?? selectedAnswer
        lastWasCorrect = current.isCorrect(value)
        evidence.append(LessonExerciseEvidence(
            type: current.type,
            wasCorrect: lastWasCorrect,
            choiceCount: current.choices?.count ?? 0
        ))
        answered = true
    }

    func submitArranged() {
        submit(response: arrangedTokens.joined(separator: " "))
    }

    func continueNext() {
        guard answered else { return }
        if currentIndex + 1 < exercises.count {
            currentIndex += 1
            selectedAnswer = ""
            arrangedTokens = []
            answered = false
            lastWasCorrect = false
        } else {
            phase = .result
        }
    }
}
