import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var catalog: CourseCatalog?
    @Published var progress = UserProgressSnapshot()
    @Published var memory = LearnerMemorySnapshot()
    @Published var dueCount = 0
    @Published var dailyPlan: DailyLearningPlan?
    @Published var insights: LearningInsights?
    @Published var personalizedRecommendations: [PersonalizedRecommendation] = []
    @Published var isLoading = true
    @Published var errorMessage: String?

    func load(container: AppContainer) async {
        isLoading = true
        defer { isLoading = false }
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
    }

    var todayMinutes: Int {
        progress.activity.first(where: { Calendar.current.isDateInToday($0.date) })?.minutes ?? 0
    }

    func nextLesson(for level: CEFRLevel) -> Lesson? {
        let lessons = catalog?.levels.first(where: { $0.level == level })?.units.flatMap(\.lessons) ?? []
        return lessons.first { progress.lessons[$0.id]?.completedAt == nil } ?? lessons.first
    }
}
