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
                    ProgressView(L("جارٍ إعداد التقرير"))
                } else if let report = model.report {
                    Text(L("تقرير الأسبوع")).font(.largeTitle.bold())
                    Text(dateRange(report))
                        .foregroundStyle(.secondary)

                    InfoCard(title: L("الاستمرارية"), systemImage: "calendar.badge.checkmark") {
                        AccessibleProgressView(
                            title: Lf("%@ من %@ أيام مستهدفة", "\(report.activeDays)", "\(settings.weeklyTargetDays)"),
                            value: min(1, Double(report.activeDays) / Double(max(1, settings.weeklyTargetDays)))
                        )
                        Text(localizedNarrative(report))
                    }

                    InfoCard(title: L("ملخص الأسبوع"), systemImage: "chart.bar.fill") {
                        LabeledContent(L("وقت التعلّم"), value: Lf("%@ دقيقة", "\(report.totalMinutes)"))
                        LabeledContent(L("الدروس المكتملة"), value: "\(report.completedLessons)")
                        LabeledContent(L("جلسات التدريب"), value: "\(report.practiceSessions)")
                        LabeledContent(L("متوسط نتائج التدريب"), value: "\(Int(report.averagePracticeScore * 100))%")
                        LabeledContent(L("مراجعات مستحقة"), value: "\(report.dueReviewCount)")
                    }

                    if let strongest = report.strongestDomain {
                        InfoCard(title: L("أقوى مجال هذا الأسبوع"), systemImage: "crown.fill") {
                            Label(strongest.titleAr, systemImage: strongest.systemImage)
                                .font(.title2.bold())
                        }
                    }
                    if let focus = report.focusDomain {
                        InfoCard(title: L("مجال مقترح للأسبوع القادم"), systemImage: "location.fill") {
                            Label(focus.titleAr, systemImage: focus.systemImage)
                                .font(.title2.bold())
                        }
                    }

                    InfoCard(title: L("خطوات الأسبوع القادم"), systemImage: "list.bullet.clipboard.fill") {
                        ForEach(Array(localizedActions(report).enumerated()), id: \.offset) { index, action in
                            Text("\(index + 1). \(action)")
                        }
                    }

                    ShareLink(item: localizedShareText(report)) {
                        Label(L("مشاركة التقرير كنص"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Text(L("يُنشأ هذا التقرير من بيانات التعلّم الموجودة في التطبيق. لا تؤدي مشاهدة التقرير وحدها إلى إرسال بيانات جديدة."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle(L("التقرير الأسبوعي"))
        .task { await model.load(container: container) }
        .refreshable { await model.load(container: container) }
    }

    private func dateRange(_ report: WeeklyLearningReport) -> String {
        let start = report.startDate.formatted(date: .abbreviated, time: .omitted)
        let end = report.endDate.formatted(date: .abbreviated, time: .omitted)
        return LfE("من %@ إلى %@", "From %@ to %@", start, end)
    }

    private func localizedNarrative(_ report: WeeklyLearningReport) -> String {
        if report.activeDays >= 5 {
            return LE(
                "أسبوع ثابت وقوي. الاستمرارية هنا أهم من جلسة طويلة منفردة.",
                "A strong, consistent week. Regular practice matters more than one long session."
            )
        }
        if report.activeDays >= 3 {
            return LE(
                "الإيقاع جيد، ويحتاج يومين قصيرين إضافيين حتى تصبح اللغة عادة أسبوعية.",
                "Your rhythm is good. Two more short days would make practice more consistent."
            )
        }
        return LE(
            "النشاط متقطع. ثلاث جلسات من عشر دقائق ستكون أكثر فائدة من انتظار يوم مثالي.",
            "Practice was irregular. Three ten-minute sessions would be more useful than waiting for a perfect day."
        )
    }

    private func localizedActions(_ report: WeeklyLearningReport) -> [String] {
        var actions: [String] = []
        if let focus = report.focusDomain {
            actions.append(LfE("نفّذ جلستين في مهارة %@.", "Complete two sessions in %@.", focus.titleAr))
        }
        if report.dueReviewCount > 0 {
            actions.append(LfE(
                "راجع %@ بطاقة مستحقة على دفعتين.",
                "Review %@ due cards in two short sets.",
                "\(min(report.dueReviewCount, 25))"
            ))
        }
        actions.append(LE(
            "اكتب مسودة واحدة ثم أعد كتابتها بعد قراءة التقييم.",
            "Write one draft, review the feedback, then rewrite it."
        ))
        actions.append(LE(
            "نفّذ مقطعي استماع، الأول دون نص والثاني مع كشف النص في النهاية.",
            "Complete two listening tasks: first without a transcript, then reveal it at the end of the second."
        ))
        return Array(actions.prefix(4))
    }

    private func localizedShareText(_ report: WeeklyLearningReport) -> String {
        let lines = [
            LE("تقرير EnglishNova الأسبوعي", "EnglishNova Weekly Report"),
            dateRange(report),
            LfE("الأيام النشطة: %@", "Active days: %@", "\(report.activeDays)"),
            LfE("وقت التعلّم: %@ دقيقة", "Learning time: %@ min", "\(report.totalMinutes)"),
            LfE("الدروس المكتملة: %@", "Completed lessons: %@", "\(report.completedLessons)"),
            LfE("جلسات المهارات: %@", "Practice sessions: %@", "\(report.practiceSessions)"),
            LfE("متوسط جلسات المهارات: %@٪", "Average practice score: %@%", "\(Int(report.averagePracticeScore * 100))"),
            localizedNarrative(report),
            LE("خطوات الأسبوع القادم:", "Next-week actions:")
        ] + localizedActions(report).enumerated().map { "\($0.offset + 1). \($0.element)" }
        return lines.joined(separator: "\n")
    }
}
