import SwiftUI

@MainActor
final class CourseSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var lessons: [Lesson] = []
    @Published var isLoading = true

    var filtered: [Lesson] {
        guard !query.isEmpty else { return lessons }
        return lessons.filter {
            $0.titleAr.localizedCaseInsensitiveContains(query) ||
            $0.titleEn.localizedCaseInsensitiveContains(query) ||
            $0.objectiveAr.localizedCaseInsensitiveContains(query) ||
            $0.vocabulary.contains { word in
                word.english.localizedCaseInsensitiveContains(query) ||
                word.arabic.localizedCaseInsensitiveContains(query)
            }
        }
    }

    func load(repository: CourseRepositoryProtocol) async {
        isLoading = true
        if let catalog = try? await repository.catalog() {
            lessons = catalog.levels.flatMap(\.units).flatMap(\.lessons)
        }
        isLoading = false
    }
}

struct CourseSearchView: View {
    @EnvironmentObject private var container: AppContainer
    @StateObject private var model = CourseSearchViewModel()

    var body: some View {
        List {
            if model.isLoading {
                ProgressView(L("جارٍ تجهيز البحث"))
            }
            ForEach(model.filtered) { lesson in
                NavigationLink(value: lesson) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L(lesson.titleAr)).font(.headline)
                        Text(lesson.titleEn)
                            .foregroundStyle(.secondary)
                            .environment(\.layoutDirection, .leftToRight)
                        Text(L(lesson.objectiveAr))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .searchable(text: $model.query, prompt: L("درس، مهارة، أو كلمة"))
        .navigationTitle(L("البحث في المنهج"))
        .navigationDestination(for: Lesson.self) { LessonPlayerView(lesson: $0) }
        .task { await model.load(repository: container.courseRepository) }
    }
}
