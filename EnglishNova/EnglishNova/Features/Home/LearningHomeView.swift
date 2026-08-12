import SwiftUI

struct LearningHomeView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var model = HomeViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.cardSpacing) {
                welcome
                continueLearning
                dueReview
                todayPlan
                aiLearningBrief
                progressSummary
                practiceShortcuts
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle(L("اليوم"))
        .navigationDestination(for: Lesson.self) { LessonPlayerView(lesson: $0) }
        .task { await model.load(container: container) }
        .refreshable { await model.load(container: container) }
        .alert(L("تعذر تحديث الصفحة"), isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button(L("حسنًا")) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var greetingName: String {
        let local = session.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !local.isEmpty { return local }
        return container.accountService.currentUser?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greetingName.isEmpty ? L("مرحبًا") : Lf("مرحبًا، %@", greetingName))
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(Lf("مستوى الدراسة: %@", session.selectedLevel.rawValue))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Lf("مستوى الدراسة %@", session.selectedLevel.rawValue))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var continueLearning: some View {
        if let lesson = model.nextLesson(for: session.selectedLevel) {
            NavigationLink(value: lesson) {
                InfoCard(title: L("الدرس التالي"), systemImage: "play.fill", tint: AppTheme.brand) {
                    Text(L(lesson.titleAr))
                        .font(.title2.bold())
                    Text(L(lesson.objectiveAr))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        Label(Lf("%@ دقائق", "\(lesson.estimatedMinutes)"), systemImage: "clock")
                        Label(Lf("%@ مفردات", "\(lesson.vocabulary.count)"), systemImage: "textformat.abc")
                    }
                    .font(.subheadline)
                    Text(L("ابدأ"))
                        .font(.headline)
                        .foregroundStyle(AppTheme.brand)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(L("يفتح الدرس التالي في المستوى الحالي"))
        } else if model.isLoading {
            ProgressView(L("جارٍ تحميل خطتك"))
                .frame(maxWidth: .infinity, minHeight: 80)
        }
    }

    @ViewBuilder
    private var dueReview: some View {
        if model.dueCount > 0 {
            NavigationLink { ReviewView() } label: {
                InfoCard(title: L("مراجعات مستحقة"), systemImage: "rectangle.stack.fill", tint: AppTheme.accentTeal) {
                    Text(Lf("حان وقت مراجعة %@ كلمة.", "\(model.dueCount)"))
                        .font(.title3.weight(.semibold))
                    Text(L("يمكنك مراجعتها الآن أو العودة إليها لاحقًا من تبويب المراجعة."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var todayPlan: some View {
        if let plan = model.dailyPlan {
            NavigationLink { DailyPlanView() } label: {
                InfoCard(title: L("خطة اليوم"), systemImage: "checklist", tint: AppTheme.brandSecondary) {
                    Text(Lf("%@ أنشطة • قرابة %@ دقيقة", "\(plan.items.count)", "\(plan.targetMinutes)"))
                        .font(.title3.bold())
                    ForEach(plan.items.prefix(3)) { item in
                        Label(L(item.titleAr), systemImage: item.kind.systemImage)
                            .font(.subheadline)
                    }
                    Text(L("تتغير الخطة بحسب ما أنجزته وما حان وقت مراجعته."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var aiLearningBrief: some View {
        if let brief = model.aiBrief {
            InfoCard(title: L("اقتراح المدرب"), systemImage: "brain.head.profile", tint: AppTheme.accentTeal) {
                Text(brief.headlineAr)
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                if !brief.focusAr.isEmpty {
                    Text(brief.focusAr).font(.headline)
                }
                if !brief.whyAr.isEmpty {
                    Text(brief.whyAr).foregroundStyle(.secondary)
                }
                ForEach(brief.actionsAr, id: \.self) { action in
                    Label(action, systemImage: "checkmark.circle")
                        .font(.subheadline)
                }
                if !brief.challengeEn.isEmpty {
                    Divider()
                    Text(L("تطبيق قصير"))
                        .font(.caption.bold())
                    Text(brief.challengeEn)
                        .environment(\.layoutDirection, .leftToRight)
                        .textSelection(.enabled)
                }
                NavigationLink { AIExerciseView(startAdaptive: true) } label: {
                    Label(L("أنشئ تدريبًا يناسب احتياجي"), systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 48)
                }
                .accessibilityHint(L("ينشئ تدريبًا جديدًا بناءً على أخطائك ونتائجك الأخيرة"))
            }
        } else if model.isLoadingAIBrief && container.accountService.isAuthenticated {
            ProgressView(L("جارٍ إعداد اقتراح المدرب"))
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        }
    }

    private var progressSummary: some View {
        InfoCard(title: L("تقدّمك اليوم"), systemImage: "chart.line.uptrend.xyaxis", tint: AppTheme.success) {
            AccessibleProgressView(
                title: Lf("%@ من %@ دقيقة", "\(model.todayMinutes)", "\(settings.dailyGoalMinutes)"),
                value: min(1, Double(model.todayMinutes) / Double(max(1, settings.dailyGoalMinutes)))
            )
            if let insights = model.insights {
                HStack(spacing: 12) {
                    metric(value: "\(insights.completedLessons)", label: L("الدروس المكتملة"))
                    metric(value: "\(insights.activeDaysLast30)", label: L("أيام الدراسة خلال 30 يومًا"))
                }
            }
        }
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var practiceShortcuts: some View {
        InfoCard(title: L("اختصارات"), systemImage: "arrow.up.forward.app", tint: AppTheme.warning) {
            NavigationLink { PracticeHubView() } label: {
                Label(L("افتح مركز التدريب"), systemImage: "waveform.and.mic")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 48)
            }
            NavigationLink { CurriculumView() } label: {
                Label(L("تصفح المنهج"), systemImage: "graduationcap")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 48)
            }
            NavigationLink { WeeklyProgressReportView() } label: {
                Label(L("التقرير الأسبوعي"), systemImage: "doc.text.image")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 48)
            }
        }
    }
}
