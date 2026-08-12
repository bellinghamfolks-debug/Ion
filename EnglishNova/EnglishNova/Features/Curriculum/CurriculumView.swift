import SwiftUI

struct CurriculumView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @StateObject private var model = CurriculumViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("مستوى الدراسة"))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Picker(L("مستوى الدراسة"), selection: $model.selectedLevel) {
                        ForEach(CEFRLevel.allCases) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: model.selectedLevel) { _, newLevel in
                        guard session.selectedLevel != newLevel else { return }
                        session.selectedLevel = newLevel
                        Task { await session.save() }
                    }
                }

                if let course = model.selectedCourse {
                    Text(L(course.titleAr))
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(L(course.descriptionAr))
                        .foregroundStyle(.secondary)

                    ForEach(course.units) { unit in
                        UnitCard(
                            unit: unit,
                            completion: model.completion(for: unit),
                            progress: model.progress
                        )
                    }
                } else if model.isLoading {
                    ProgressView(L("جارٍ تحميل المنهج"))
                } else {
                    ContentUnavailableView(
                        L("لا يوجد محتوى لهذا المستوى"),
                        systemImage: "books.vertical",
                        description: Text(L("جرّب مستوى آخر أو تحقق من تحديثات المنهج."))
                    )
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle(L("المنهج"))
        .toolbar {
            NavigationLink { CourseSearchView() } label: {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel(L("البحث في الدروس"))
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
        InfoCard(title: L(unit.titleAr), systemImage: unit.icon) {
            Text(L(unit.descriptionAr)).foregroundStyle(.secondary)
            AccessibleProgressView(title: L("إنجاز الوحدة"), value: completion)

            VStack(spacing: 8) {
                ForEach(unit.lessons) { lesson in
                    NavigationLink(value: lesson) {
                        HStack(spacing: 12) {
                            Image(systemName: isCompleted(lesson) ? "checkmark.circle.fill" : "circle")
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L(lesson.titleAr)).font(.headline)
                                Text(Lf("%@ دقائق • %@ نقطة", "\(lesson.estimatedMinutes)", "\(lesson.points)"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.forward")
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        Lf("%@، %@ دقائق", "\(lesson.titleAr)", "\(lesson.estimatedMinutes)")
                    )
                    .accessibilityValue(isCompleted(lesson) ? L("مكتمل") : L("لم يكتمل بعد"))
                }
            }
        }
    }

    private func isCompleted(_ lesson: Lesson) -> Bool {
        progress.lessons[lesson.id]?.completedAt != nil
    }
}
