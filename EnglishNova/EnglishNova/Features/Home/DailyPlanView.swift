import SwiftUI

@MainActor
final class DailyPlanViewModel: ObservableObject {
    @Published var plan: DailyLearningPlan?
    @Published var lessonByID: [String: Lesson] = [:]
    @Published var isLoading = true
    @Published var errorMessage: String?

    func load(container: AppContainer) async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let catalogValue = container.courseRepository.catalog()
            async let progressValue = container.progressRepository.snapshot()
            async let dueValue = container.vocabularyRepository.dueCards(on: .now)
            let catalog = try await catalogValue
            let progress = await progressValue
            let due = await dueValue
            lessonByID = Dictionary(uniqueKeysWithValues: catalog.levels.flatMap(\.units).flatMap(\.lessons).map { ($0.id, $0) })
            plan = LearningPlanner.makePlan(
                catalog: catalog,
                progress: progress,
                dueCards: due,
                level: container.session.selectedLevel,
                targetMinutes: container.settings.dailyGoalMinutes,
                reducePressure: container.settings.reduceLearningPressure,
                studyMode: container.settings.studyMode,
                pathway: container.settings.selectedLearningPathway
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct DailyPlanView: View {
    @EnvironmentObject private var container: AppContainer
    @StateObject private var model = DailyPlanViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if model.isLoading {
                    ProgressView(L("جارٍ إعداد خطة اليوم من تقدمك الحالي"))
                } else if let plan = model.plan {
                    Text(Lf("خطة لمدة %@ دقيقة", "\(plan.targetMinutes)"))
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(L("تتغير الخطة بحسب الدروس غير المكتملة، والمراجعات المستحقة، والمهارات التي تحتاج إلى تدريب."))
                        .foregroundStyle(.secondary)
                    AccessibleProgressView(title: L("إنجاز خطة اليوم"), value: plan.progress)

                    ForEach(Array(plan.items.enumerated()), id: \.element.id) { index, item in
                        planItem(item, number: index + 1)
                    }

                    InfoCard(title: L("كيف اختيرت هذه الأنشطة؟"), systemImage: "wand.and.stars") {
                        Text(L("تبدأ الخطة بأهم مهمة تعليمية، ثم تضيف المراجعة أو تدريب المهارة بما يناسب وقتك الحالي."))
                        if container.settings.reduceLearningPressure {
                            Text(L("وضع التعلّم الهادئ مفعّل، لذلك لا تتجاوز الخطة عشر دقائق."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let error = model.errorMessage {
                    ContentUnavailableView(L("تعذر إعداد خطة اليوم"), systemImage: "exclamationmark.triangle", description: Text(error))
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle(L("خطة اليوم"))
        .refreshable { await model.load(container: container) }
        .task { await model.load(container: container) }
    }

    @ViewBuilder
    private func planItem(_ item: LearningPlanItem, number: Int) -> some View {
        let card = InfoCard(title: "\(number). \(item.kind.titleAr)", systemImage: item.kind.systemImage) {
            Text(L(item.titleAr)).font(.title3.bold())
            Text(L(item.subtitleAr)).foregroundStyle(.secondary)
            Label(Lf("%@ دقائق", "\(item.estimatedMinutes)"), systemImage: "clock")
        }

        switch item.kind {
        case .lesson:
            if let id = item.referenceID, let lesson = model.lessonByID[id] {
                NavigationLink { LessonPlayerView(lesson: lesson) } label: { card }
                    .buttonStyle(.plain)
            } else { card }
        case .review:
            NavigationLink { ReviewView() } label: { card }.buttonStyle(.plain)
        case .listening:
            NavigationLink { ListeningLabView() } label: { card }.buttonStyle(.plain)
        case .pronunciation:
            NavigationLink { PronunciationLabView() } label: { card }.buttonStyle(.plain)
        case .story:
            NavigationLink { StoryLibraryView() } label: { card }.buttonStyle(.plain)
        case .conversation:
            NavigationLink { ConversationStudioView() } label: { card }.buttonStyle(.plain)
        case .reading:
            NavigationLink { ReadingComprehensionLabView() } label: { card }.buttonStyle(.plain)
        case .writing:
            NavigationLink { WritingStudioView() } label: { card }.buttonStyle(.plain)
        case .exam:
            NavigationLink { AdvancedPreparationHubView() } label: { card }.buttonStyle(.plain)
        }
    }
}
