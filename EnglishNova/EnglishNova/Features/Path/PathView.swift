import SwiftUI

/// The "Path" tab: units as a vertical trail of lessons with clear states —
/// finished, up next, and still ahead. Every lesson stays open; the path
/// guides rather than locks.
struct PathView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @StateObject private var model = CurriculumViewModel()
    @State private var didLoad = false

    enum LessonState { case done, next, ahead }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                levelPicker

                if let course = model.selectedCourse {
                    levelHeader(course)
                    ForEach(course.units) { unit in
                        unitSection(unit, course: course)
                    }
                } else if model.isLoading {
                    ProgressView(L("جارٍ تحميل المنهج"))
                        .frame(maxWidth: .infinity, minHeight: 120)
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
        .navigationTitle(LE("المسار", "Path"))
        .toolbar {
            NavigationLink { CourseSearchView() } label: {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel(L("البحث في الدروس"))
        }
        .navigationDestination(for: Lesson.self) { LessonPlayerView(lesson: $0) }
        .task {
            guard !didLoad else { return }
            didLoad = true
            await model.load(container: container, initialLevel: session.selectedLevel)
        }
        .onAppear {
            // Refresh states after returning from a lesson.
            guard didLoad else { return }
            Task { model.progress = await container.progressRepository.snapshot() }
        }
    }

    private var levelPicker: some View {
        Picker(LE("المستوى المعروض", "Level shown"), selection: $model.selectedLevel) {
            ForEach(CEFRLevel.allCases) { level in
                Text(level.rawValue).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityHint(LE("يعرض مسار مستوى آخر دون تغيير مستواك المسجّل.", "Shows another level's path without changing your saved level."))
    }

    private func levelHeader(_ course: CourseLevel) -> some View {
        let lessons = course.units.flatMap(\.lessons)
        let done = lessons.filter { model.progress.lessons[$0.id]?.completedAt != nil }.count
        return VStack(alignment: .leading, spacing: 8) {
            Text(L(course.titleAr))
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(L(course.descriptionAr))
                .foregroundStyle(.secondary)
            AccessibleProgressView(
                title: LfE("%@ من %@ دروس مكتملة", "%@ of %@ lessons done", "\(done)", "\(lessons.count)"),
                value: lessons.isEmpty ? 0 : Double(done) / Double(lessons.count)
            )
        }
    }

    private func unitSection(_ unit: CourseUnit, course: CourseLevel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: unit.icon)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.brandGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LfE("الوحدة %@", "Unit %@", "\(unit.order)"))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(LE(unit.titleAr, unit.titleEn))
                        .font(.title3.bold())
                }
                Spacer()
                Text("\(Int((model.completion(for: unit) * 100).rounded()))%")
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(AppTheme.brand)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .padding(.bottom, 12)

            ForEach(Array(unit.lessons.enumerated()), id: \.element.id) { index, lesson in
                NavigationLink(value: lesson) {
                    lessonNode(lesson, state: state(for: lesson, in: course), isLast: index == unit.lessons.count - 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(AppTheme.cardSurface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }

    private func lessonNode(_ lesson: Lesson, state: LessonState, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(fill(for: state))
                        .frame(width: state == .next ? 46 : 38, height: state == .next ? 46 : 38)
                    Image(systemName: symbol(for: state))
                        .font(state == .next ? .headline : .subheadline.bold())
                        .foregroundStyle(state == .ahead ? Color.secondary : Color.white)
                }
                .frame(width: 46, height: 46)
                if !isLast {
                    Rectangle()
                        .fill(state == .done ? AppTheme.success.opacity(0.6) : Color.secondary.opacity(0.25))
                        .frame(width: 3)
                        .frame(minHeight: 22, maxHeight: .infinity)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(LE(lesson.titleAr, lesson.titleEn))
                    .font(state == .next ? .headline : .body.weight(.semibold))
                    .foregroundStyle(state == .ahead ? .secondary : .primary)
                HStack(spacing: 10) {
                    Label(LfE("%@ د", "%@ min", "\(lesson.estimatedMinutes)"), systemImage: "clock")
                    if let best = model.progress.lessons[lesson.id], best.completedAt != nil {
                        Label("\(Int((best.bestScore * 100).rounded()))%", systemImage: "checkmark.seal")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if state == .next {
                    Text(LE("ابدأ من هنا", "Start here"))
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppTheme.brand, in: Capsule())
                }
            }
            .padding(.top, 8)
            .padding(.bottom, isLast ? 0 : 14)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(lesson, state: state))
        .accessibilityAddTraits(.isButton)
    }

    private func accessibilityLabel(_ lesson: Lesson, state: LessonState) -> String {
        let title = LE(lesson.titleAr, lesson.titleEn)
        switch state {
        case .done:
            let best = Int(((model.progress.lessons[lesson.id]?.bestScore ?? 0) * 100).rounded())
            return LfE("%@، مكتمل، أفضل نتيجة %@٪", "%@, done, best score %@%", title, "\(best)")
        case .next:
            return LfE("%@، الدرس التالي، %@ دقائق", "%@, up next, %@ minutes", title, "\(lesson.estimatedMinutes)")
        case .ahead:
            return LfE("%@، لم يبدأ بعد", "%@, not started", title)
        }
    }

    private func state(for lesson: Lesson, in course: CourseLevel) -> LessonState {
        if model.progress.lessons[lesson.id]?.completedAt != nil { return .done }
        let firstOpen = course.units.flatMap(\.lessons).first { model.progress.lessons[$0.id]?.completedAt == nil }
        return firstOpen?.id == lesson.id ? .next : .ahead
    }

    private func fill(for state: LessonState) -> AnyShapeStyle {
        switch state {
        case .done: return AnyShapeStyle(AppTheme.success)
        case .next: return AnyShapeStyle(AppTheme.brandGradient)
        case .ahead: return AnyShapeStyle(Color.secondary.opacity(0.15))
        }
    }

    private func symbol(for state: LessonState) -> String {
        switch state {
        case .done: return "checkmark"
        case .next: return "play.fill"
        case .ahead: return "circle.fill"
        }
    }
}
