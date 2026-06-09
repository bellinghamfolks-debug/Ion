import Foundation
import Combine

@MainActor
final class CurriculumViewModel: ObservableObject {
    @Published var catalog: CourseCatalog?
    @Published var progress = UserProgressSnapshot()
    @Published var selectedLevel: CEFRLevel = .a0
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(container: AppContainer, initialLevel: CEFRLevel) async {
        selectedLevel = initialLevel
        isLoading = true
        defer { isLoading = false }
        do {
            catalog = try await container.courseRepository.catalog()
            progress = await container.progressRepository.snapshot()
        } catch { errorMessage = error.localizedDescription }
    }

    var selectedCourse: CourseLevel? { catalog?.levels.first { $0.level == selectedLevel } }

    func completion(for unit: CourseUnit) -> Double {
        guard !unit.lessons.isEmpty else { return 0 }
        let complete = unit.lessons.filter { progress.lessons[$0.id]?.completedAt != nil }.count
        return Double(complete) / Double(unit.lessons.count)
    }
}
