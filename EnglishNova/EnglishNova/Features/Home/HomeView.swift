import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var model = HomeViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                greeting
                dailyGoal
                pathwayOverview
                smartPlan
                personalCoach
                continueLearning
                quickActions
                weeklyActivity
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle("EnglishNova")
        .task { await model.load(container: container) }
        .refreshable { await model.load(container: container) }
        .alert("تعذر التحميل", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("حسنًا") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.displayName.isEmpty ? "مرحبًا بك" : "مرحبًا، \(session.displayName)")
                .font(.largeTitle.bold())
            Text(settings.reduceLearningPressure ? "اليوم يكفي أن تتقدم بهدوء." : "خطوة صغيرة اليوم تصنع لغة كاملة غدًا.")
                .foregroundStyle(.secondary)
        }
    }

    private var dailyGoal: some View {
        InfoCard(title: "هدف اليوم", systemImage: "target") {
            AccessibleProgressView(
                title: "\(model.todayMinutes) من \(settings.dailyGoalMinutes) دقيقة",
                value: min(1, Double(model.todayMinutes) / Double(max(1, settings.dailyGoalMinutes)))
            )
            HStack {
                Label("\(session.points) نقطة", systemImage: "star.fill")
                Spacer()
                Label("\(session.streak) يوم", systemImage: "flame.fill")
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    private var pathwayOverview: some View {
        let pathway = LearningPathwayCatalog.definition(for: settings.selectedLearningPathway)
        let progress = LearningPathwayCatalog.progress(for: settings.selectedLearningPathway, snapshot: model.progress)
        return NavigationLink { LearningPathwaysView() } label: {
            InfoCard(title: "مسارك الحالي", systemImage: pathway.id.systemImage) {
                Text(pathway.titleAr).font(.title2.bold())
                Text(pathway.detailAr).foregroundStyle(.secondary)
                AccessibleProgressView(
                    title: "\(progress.completedMilestones) من \(progress.totalMilestones) مراحل",
                    value: progress.overallProgress
                )
                if let current = progress.currentMilestone {
                    Text("المرحلة الحالية: \(current.titleAr)").font(.caption.bold())
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var smartPlan: some View {
        if let plan = model.dailyPlan {
            NavigationLink { DailyPlanView() } label: {
                InfoCard(title: "خطتك الذكية", systemImage: "wand.and.stars") {
                    Text("\(plan.items.count) أنشطة • \(plan.targetMinutes) دقيقة")
                        .font(.title2.bold())
                    ForEach(plan.items.prefix(3)) { item in
                        Label(item.titleAr, systemImage: item.kind.systemImage)
                            .font(.subheadline)
                    }
                    Text("افتح الخطة لمعرفة سبب اختيار كل نشاط.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }


    @ViewBuilder private var personalCoach: some View {
        if settings.adaptiveCoachEnabled, !model.personalizedRecommendations.isEmpty {
            InfoCard(title: "مدربك الشخصي", systemImage: "brain.head.profile") {
                Text("هذه الاقتراحات مبنية على تقدمك وأخطائك الحديثة، لا على ترتيب ثابت.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.personalizedRecommendations.prefix(3)) { recommendation in
                    NavigationLink {
                        recommendationDestination(recommendation.destination)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: recommendation.systemImage)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(recommendation.titleAr).font(.headline)
                                Text(recommendation.detailAr)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.forward")
                                .font(.caption.bold())
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func recommendationDestination(_ destination: RecommendationDestination) -> some View {
        switch destination {
        case .pronunciation: PronunciationLabView()
        case .mistakes: MistakeNotebookView()
        case .review: ReviewView()
        case .conversation: VoiceCoachView()
        case .exam: AdvancedPreparationHubView()
        case .lesson: CurriculumView()
        }
    }

    @ViewBuilder private var continueLearning: some View {
        if let lesson = model.nextLesson(for: session.selectedLevel) {
            NavigationLink(value: lesson) {
                InfoCard(title: "تابع التعلّم", systemImage: "play.circle.fill") {
                    Text(lesson.titleAr).font(.title2.bold())
                    Text(lesson.objectiveAr).foregroundStyle(.secondary)
                    Label("\(lesson.estimatedMinutes) دقائق", systemImage: "clock")
                }
            }
            .buttonStyle(.plain)
            .navigationDestination(for: Lesson.self) { LessonPlayerView(lesson: $0) }
        } else if model.isLoading {
            ProgressView("جاري تجهيز رحلتك التعليمية")
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("وصول سريع").font(.title2.bold())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                NavigationLink { PracticeHubView() } label: { QuickActionCard(title: "تدريب", icon: "mic.fill") }
                NavigationLink { ReviewView() } label: { QuickActionCard(title: "مراجعة \(model.dueCount)", icon: "rectangle.stack.fill") }
                NavigationLink { StoryLibraryView() } label: { QuickActionCard(title: "قصص", icon: "book.pages.fill") }
                NavigationLink { AdvancedSkillsHubView() } label: { QuickActionCard(title: "مختبرات", icon: "books.vertical.fill") }
                NavigationLink { WeeklyProgressReportView() } label: { QuickActionCard(title: "تقرير أسبوعي", icon: "doc.text.image.fill") }
            }
            .buttonStyle(.plain)
        }
    }

    private var weeklyActivity: some View {
        InfoCard(title: "آخر سبعة أيام", systemImage: "chart.bar.fill") {
            ForEach(lastSevenDays, id: \.self) { date in
                let minutes = model.progress.activity.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) })?.minutes ?? 0
                HStack {
                    Text(date, format: .dateTime.weekday(.abbreviated))
                    ProgressView(value: Double(minutes), total: Double(max(settings.dailyGoalMinutes, 1)))
                    Text("\(minutes) د").monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var lastSevenDays: [Date] {
        Array((0..<7).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: .now) }.reversed())
    }
}

private struct QuickActionCard: View {
    let title: String
    let icon: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.title)
            Text(title).font(.headline)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
