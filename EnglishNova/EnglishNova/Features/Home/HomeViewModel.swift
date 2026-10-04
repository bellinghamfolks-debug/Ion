import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var catalog: CourseCatalog?
    @Published var progress = UserProgressSnapshot()
    @Published var memory = LearnerMemorySnapshot()
    @Published var dueCount = 0
    @Published var dueLessonReviewCount = 0
    @Published var remedialCount = 0
    @Published var dailyPlan: DailyLearningPlan?
    @Published var insights: LearningInsights?
    @Published var personalizedRecommendations: [PersonalizedRecommendation] = []
    @Published var aiBrief: AILearningBrief?
    @Published var isLoadingAIBrief = false
    @Published var isLoading = true
    @Published var errorMessage: String?

    func load(container: AppContainer) async {
        isLoading = true
        errorMessage = nil
        do {
            async let catalogValue = container.courseRepository.catalog()
            async let snapshotValue = container.progressRepository.snapshot()
            async let dueValue = container.vocabularyRepository.dueCards(on: .now)
            async let memoryValue = container.learningMemoryRepository.snapshot()
            let loadedCatalog = try await catalogValue
            let loadedProgress = await snapshotValue
            let dueCards = await dueValue
            let loadedMemory = await memoryValue
            catalog = loadedCatalog
            progress = loadedProgress
            memory = loadedMemory
            dueCount = dueCards.count
            dueLessonReviewCount = LessonReviewEngine.dueCandidates(catalog: loadedCatalog, snapshot: loadedProgress).count
            remedialCount = RemedialPracticeEngine.items(mistakes: loadedMemory.mistakes, catalog: loadedCatalog).count
            dailyPlan = LearningPlanner.makePlan(
                catalog: loadedCatalog,
                progress: loadedProgress,
                dueCards: dueCards,
                level: container.session.selectedLevel,
                targetMinutes: container.settings.dailyGoalMinutes,
                reducePressure: container.settings.reduceLearningPressure,
                studyMode: container.settings.studyMode,
                pathway: container.settings.selectedLearningPathway
            )
            insights = LearningPlanner.insights(progress: loadedProgress, dueCards: dueCards)
            personalizedRecommendations = PersonalizationEngine.recommendations(
                progress: loadedProgress,
                memory: loadedMemory,
                dueCards: dueCards
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false

        // The local plan appears immediately. AI is an enhancement and loads in
        // parallel afterward so a slow network never blocks the learning home.
        await loadAIBrief(container: container)
    }

    private func loadAIBrief(container: AppContainer) async {
        guard container.accountService.isAuthenticated else {
            aiBrief = nil
            return
        }
        isLoadingAIBrief = true
        defer { isLoadingAIBrief = false }

        // Quietly refresh the server learner profile at most every few minutes.
        _ = await container.progressSyncService.pushIfStale()
        do {
            aiBrief = try await AIStudioService().learningBrief()
        } catch {
            // Personalization is additive. Keep Home fully usable when AI or the
            // server is unavailable instead of presenting a blocking alert.
            aiBrief = nil
        }
    }

    var todayMinutes: Int {
        progress.activity.first(where: { Calendar.current.isDateInToday($0.date) })?.minutes ?? 0
    }

    func nextLesson(for level: CEFRLevel) -> Lesson? {
        let lessons = catalog?.levels.first(where: { $0.level == level })?.units.flatMap(\.lessons) ?? []
        return lessons.first { progress.lessons[$0.id]?.completedAt == nil } ?? lessons.first
    }

    var lessonCompletedToday: Bool {
        progress.lessons.values.contains { $0.completedAt.map(Calendar.current.isDateInToday) ?? false }
    }

    func dailySession(level: CEFRLevel, store: DailySessionStore, goalMinutes: Int) -> DailySession {
        let next = nextLesson(for: level)
        return DailySessionEngine.makeSession(DailySessionInput(
            hasNextLesson: next != nil,
            lessonMinutes: next?.estimatedMinutes ?? 8,
            lessonCompletedToday: lessonCompletedToday,
            dueReviewCount: dueCount + dueLessonReviewCount,
            openMistakeCount: remedialCount,
            plannedToday: store.planned,
            completedToday: store.completed,
            dailyGoalMinutes: goalMinutes
        ))
    }

    /// A real sentence for the speaking step: from the most recently finished
    /// lesson if there is one today, otherwise from the next lesson.
    func speakingSentence(for level: CEFRLevel) -> String {
        let lessons = catalog?.levels.flatMap { $0.units.flatMap(\.lessons) } ?? []
        let recent = progress.lessons.values
            .filter { $0.completedAt != nil }
            .max { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
            .flatMap { record in lessons.first { $0.id == record.lessonID } }
        for lesson in [recent, nextLesson(for: level)].compactMap({ $0 }) {
            if let sentence = ExerciseSynthesizer.dictationSentence(for: lesson, words: lesson.vocabulary) {
                return sentence
            }
        }
        return "I would like a cup of coffee, please."
    }
}
