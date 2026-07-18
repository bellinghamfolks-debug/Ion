import SwiftUI

struct CurriculumView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @StateObject private var model = CurriculumViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("المستوى", selection: $model.selectedLevel) {
                    ForEach(CEFRLevel.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                // Changing the level here becomes the learner's active level, so
                // the Home screen and "continue learning" follow it instead of
                // always restarting from A0.
                .onChange(of: model.selectedLevel) { newLevel in
                    guard session.selectedLevel != newLevel else { return }
                    session.selectedLevel = newLevel
                    Task { await session.save() }
                }

                if let course = model.selectedCourse {
                    Text(L(course.titleAr)).font(.largeTitle.bold())
                    Text(L(course.descriptionAr)).foregroundStyle(.secondary)
                    ForEach(course.units) { unit in
                        UnitCard(unit: unit, completion: model.completion(for: unit), progress: model.progress)
                    }
                } else if model.isLoading {
                    ProgressView("جاري تحميل المنهج")
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle("المنهج")
        .toolbar {
            NavigationLink { CourseSearchView() } label: { Image(systemName: "magnifyingglass") }
                .accessibilityLabel("البحث في المنهج")
        }
        .navigationDestination(for: Lesson.self) { LessonPlayerView(lesson: $0) }
        .task { await model.load(container: container, initialLevel: session.selectedLevel) }
    }
}

private struct UnitCard: View {
    let unit: CourseUnit
    let completion: Double
    let progress: UserProgressSnapshot

    var body: some View {
        InfoCard(title: unit.titleAr, systemImage: unit.icon) {
            Text(L(unit.descriptionAr)).foregroundStyle(.secondary)
            AccessibleProgressView(title: "تقدم الوحدة", value: completion)
            VStack(spacing: 8) {
                ForEach(unit.lessons) { lesson in
                    NavigationLink(value: lesson) {
                        HStack(spacing: 12) {
                            Image(systemName: progress.lessons[lesson.id]?.completedAt == nil ? "circle" : "checkmark.circle.fill")
                            VStack(alignment: .leading) {
                                Text(L(lesson.titleAr)).font(.headline)
                                Text("\(lesson.estimatedMinutes) دقائق • \(lesson.points) نقطة").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.forward")
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("درس \(lesson.titleAr)، مدته \(lesson.estimatedMinutes) دقائق")
                    .accessibilityValue(progress.lessons[lesson.id]?.completedAt == nil ? "غير مكتمل" : "مكتمل")
                }
            }
        }
    }
}
