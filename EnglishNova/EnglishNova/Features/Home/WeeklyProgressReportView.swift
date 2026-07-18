import SwiftUI

@MainActor
final class WeeklyProgressReportViewModel: ObservableObject {
    @Published var report: WeeklyLearningReport?
    @Published var isLoading = true

    func load(container: AppContainer) async {
        isLoading = true
        async let progressTask = container.progressRepository.snapshot()
        async let dueTask = container.vocabularyRepository.dueCards(on: .now)
        let progress = await progressTask
        let dueCards = await dueTask
        report = AdvancedAnalyticsEngine.weeklyReport(
            progress: progress,
            dueReviewCount: dueCards.count
        )
        isLoading = false
    }
}

struct WeeklyProgressReportView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var model = WeeklyProgressReportViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if model.isLoading {
                    ProgressView(L("جاري إعداد التقرير محليًا"))
                } else if let report = model.report {
                    Text(L("تقرير الأسبوع")).font(.largeTitle.bold())
                    Text("من \(report.startDate.formatted(date: .abbreviated, time: .omitted)) إلى \(report.endDate.formatted(date: .abbreviated, time: .omitted))")
                        .foregroundStyle(.secondary)

                    InfoCard(title: L("الاستمرارية"), systemImage: "calendar.badge.checkmark") {
                        AccessibleProgressView(
                            title: Lf("%@ من %@ أيام مستهدفة", "\(report.activeDays)", "\(settings.weeklyTargetDays)"),
                            value: min(1, Double(report.activeDays) / Double(max(1, settings.weeklyTargetDays)))
                        )
                        Text(report.narrativeAr)
                    }

                    InfoCard(title: L("الأرقام"), systemImage: "chart.bar.fill") {
                        LabeledContent(L("وقت التعلم"), value: Lf("%@ دقيقة", "\(report.totalMinutes)"))
                        LabeledContent(L("الدروس المكتملة"), value: "\(report.completedLessons)")
                        LabeledContent(L("جلسات المهارات"), value: "\(report.practiceSessions)")
                        LabeledContent(L("متوسط المهارات"), value: "\(Int(report.averagePracticeScore * 100))٪")
                        LabeledContent(L("بطاقات مستحقة"), value: "\(report.dueReviewCount)")
                    }

                    if let strongest = report.strongestDomain {
                        InfoCard(title: L("أقوى مجال هذا الأسبوع"), systemImage: "crown.fill") {
                            Label(strongest.titleAr, systemImage: strongest.systemImage)
                                .font(.title2.bold())
                        }
                    }
                    if let focus = report.focusDomain {
                        InfoCard(title: L("بوصلة الأسبوع القادم"), systemImage: "location.fill") {
                            Label(focus.titleAr, systemImage: focus.systemImage)
                                .font(.title2.bold())
                        }
                    }

                    InfoCard(title: L("خطة الأسبوع القادم"), systemImage: "list.bullet.clipboard.fill") {
                        ForEach(Array(report.nextWeekActions.enumerated()), id: \.offset) { index, action in
                            Text("\(index + 1). \(action)")
                        }
                    }

                    ShareLink(item: report.shareText) {
                        Label(L("مشاركة التقرير كنص"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Text(L("التقرير خاص بجهازك ويُبنى من بيانات التعلّم المحلية. لا تُرفع بياناته تلقائيًا."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle(L("التقرير الأسبوعي"))
        .task { await model.load(container: container) }
        .refreshable { await model.load(container: container) }
    }
}
