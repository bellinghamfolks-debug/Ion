import SwiftUI

@MainActor
final class LearningInsightsViewModel: ObservableObject {
    @Published var insights: LearningInsights?
    @Published var isLoading = true

    func load(container: AppContainer) async {
        isLoading = true
        async let progress = container.progressRepository.snapshot()
        async let due = container.vocabularyRepository.dueCards(on: .now)
        insights = LearningPlanner.insights(progress: await progress, dueCards: await due)
        isLoading = false
    }
}

struct LearningInsightsView: View {
    @EnvironmentObject private var container: AppContainer
    @StateObject private var model = LearningInsightsViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if model.isLoading {
                    ProgressView(L("جارٍ تحليل تقدّمك"))
                } else if let insights = model.insights {
                    Text(L("تحليل التقدّم"))
                        .font(.largeTitle.bold())
                    Text(L("هذه الأرقام تخص تعلّمك على هذا الجهاز، ولا تقارنك بمستخدمين آخرين."))
                        .foregroundStyle(.secondary)

                    ForEach(insights.insights) { insight in
                        InfoCard(title: insight.titleAr, systemImage: insight.systemImage) {
                            Text(insight.valueAr).font(.title.bold())
                            Text(insight.detailAr).foregroundStyle(.secondary)
                        }
                    }

                    InfoCard(title: L("نتائج الدروس"), systemImage: "scope") {
                        AccessibleProgressView(
                            title: Lf("متوسط أفضل نتيجة %@٪", "\(Int(insights.averageLessonScore * 100))"),
                            value: insights.averageLessonScore
                        )
                        LabeledContent(L("إجمالي المحاولات"), value: "\(insights.totalAttempts)")
                        LabeledContent(L("كلمات مستحقة للمراجعة"), value: "\(insights.dueVocabulary)")
                    }

                    if let strongest = insights.strongestSkill {
                        InfoCard(title: L("أقوى مهارة مسجلة"), systemImage: "crown.fill") {
                            Text(L(strongest.skill.titleAr)).font(.title2.bold())
                            AccessibleProgressView(
                                title: Lf("الدقة %@٪", "\(Int(strongest.accuracy * 100))"),
                                value: strongest.accuracy
                            )
                        }
                    }

                    if let focus = insights.focusSkill {
                        InfoCard(title: L("مهارة تستحق تدريبًا إضافيًا"), systemImage: "location.fill") {
                            Text(L(focus.skill.titleAr)).font(.title2.bold())
                            Text(L("اختر تدريبًا قصيرًا لهذه المهارة، ثم عد إلى خطتك الأساسية."))
                            NavigationLink(L("فتح مركز التدريب")) { PracticeHubView() }
                        }
                    }
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle(L("تحليل التقدّم"))
        .task { await model.load(container: container) }
        .refreshable { await model.load(container: container) }
    }
}
