import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var model = HomeViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                dailyGoal
                pathwayOverview
                smartPlan
                personalCoach
                continueLearning
                quickActions
                HomeLeaderboardCard()
                weeklyActivity
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle("EnglishNova")
        .task { await model.load(container: container) }
        .refreshable { await model.load(container: container) }
        .alert(L("تعذر التحميل"), isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button(L("حسنًا")) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.displayName.isEmpty ? L("مرحبًا بك 👋") : "مرحبًا، \(session.displayName) 👋")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                Text(settings.reduceLearningPressure ? L("اليوم يكفي أن تتقدم بهدوء.") : L("خطوة صغيرة اليوم تصنع لغة كاملة غدًا."))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            }
            HStack(spacing: 10) {
                heroStat(icon: "graduationcap.fill", value: session.selectedLevel.rawValue, label: "المستوى")
                heroStat(icon: "star.fill", value: "\(session.points)", label: "نقطة")
                heroStat(icon: "flame.fill", value: "\(session.streak)", label: "يوم متتالٍ")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.heroGradient,
                    in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .shadow(color: AppTheme.brand.opacity(0.35), radius: 16, x: 0, y: 8)
    }

    private func heroStat(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Label(value, systemImage: icon)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var dailyGoal: some View {
        InfoCard(title: "هدف اليوم", systemImage: "target") {
            AccessibleProgressView(
                title: Lf("%@ من %@ دقيقة", "\(model.todayMinutes)", "\(settings.dailyGoalMinutes)"),
                value: min(1, Double(model.todayMinutes) / Double(max(1, settings.dailyGoalMinutes)))
            )
            HStack {
                Label(Lf("%@ نقطة", "\(session.points)"), systemImage: "star.fill")
                Spacer()
                Label(Lf("%@ يوم", "\(session.streak)"), systemImage: "flame.fill")
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    private var pathwayOverview: some View {
        let pathway = LearningPathwayCatalog.definition(for: settings.selectedLearningPathway)
        let progress = LearningPathwayCatalog.progress(for: settings.selectedLearningPathway, snapshot: model.progress)
        return NavigationLink { LearningPathwaysView() } label: {
            InfoCard(title: "مسارك الحالي", systemImage: pathway.id.systemImage) {
                Text(L(pathway.titleAr)).font(.title2.bold())
                Text(pathway.detailAr).foregroundStyle(.secondary)
                AccessibleProgressView(
                    title: Lf("%@ من %@ مراحل", "\(progress.completedMilestones)", "\(progress.totalMilestones)"),
                    value: progress.overallProgress
                )
                if let current = progress.currentMilestone {
                    Text(Lf("المرحلة الحالية: %@", "\(current.titleAr)")).font(.caption.bold())
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var smartPlan: some View {
        if let plan = model.dailyPlan {
            NavigationLink { DailyPlanView() } label: {
                InfoCard(title: "خطتك الذكية", systemImage: "wand.and.stars") {
                    Text(Lf("%@ أنشطة • %@ دقيقة", "\(plan.items.count)", "\(plan.targetMinutes)"))
                        .font(.title2.bold())
                    ForEach(plan.items.prefix(3)) { item in
                        Label(item.titleAr, systemImage: item.kind.systemImage)
                            .font(.subheadline)
                    }
                    Text(L("افتح الخطة لمعرفة سبب اختيار كل نشاط."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }


    @ViewBuilder private var personalCoach: some View {
        if settings.adaptiveCoachEnabled, !model.personalizedRecommendations.isEmpty {
            InfoCard(title: "مدربك الشخصي", systemImage: "brain.head.profile") {
                Text(L("هذه الاقتراحات مبنية على تقدمك وأخطائك الحديثة، لا على ترتيب ثابت."))
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
                                Text(L(recommendation.titleAr)).font(.headline)
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
                    Text(L(lesson.titleAr)).font(.title2.bold())
                    Text(L(lesson.objectiveAr)).foregroundStyle(.secondary)
                    Label(Lf("%@ دقائق", "\(lesson.estimatedMinutes)"), systemImage: "clock")
                }
            }
            .buttonStyle(.plain)
            .navigationDestination(for: Lesson.self) { LessonPlayerView(lesson: $0) }
        } else if model.isLoading {
            ProgressView(L("جاري تجهيز رحلتك التعليمية"))
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("وصول سريع")).font(.title2.bold())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                NavigationLink { PracticeHubView() } label: { QuickActionCard(title: "تدريب", icon: "mic.fill", colors: [AppTheme.brand, AppTheme.brandSecondary]) }
                NavigationLink { ReviewView() } label: { QuickActionCard(title: Lf("مراجعة %@", "\(model.dueCount)"), icon: "rectangle.stack.fill", colors: [AppTheme.accentTeal, AppTheme.success]) }
                NavigationLink { StoryLibraryView() } label: { QuickActionCard(title: "قصص", icon: "book.pages.fill", colors: [AppTheme.brandSecondary, AppTheme.streak]) }
                NavigationLink { AdvancedSkillsHubView() } label: { QuickActionCard(title: "مختبرات", icon: "books.vertical.fill", colors: [AppTheme.warning, AppTheme.streak]) }
                NavigationLink { WeeklyProgressReportView() } label: { QuickActionCard(title: "تقرير أسبوعي", icon: "doc.text.image.fill", colors: [AppTheme.success, AppTheme.accentTeal]) }
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
                    Text(Lf("%@ د", "\(minutes)")).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var lastSevenDays: [Date] {
        Array((0..<7).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: .now) }.reversed())
    }
}

/// Compact leaderboard preview for the Home screen: the user's rank + the top
/// three, tappable to open the full board. Only shown when signed in (the
/// leaderboard endpoint requires auth). Failures fall back to nothing.
private struct HomeLeaderboardCard: View {
    @EnvironmentObject private var account: AccountService
    @State private var me: MyRank?
    @State private var top: [LeaderboardEntry] = []
    @State private var loaded = false

    private let service = AIStudioService()

    var body: some View {
        if account.isAuthenticated {
            NavigationLink { LeaderboardView() } label: {
                InfoCard(title: "لوحة الصدارة", systemImage: "trophy.fill", tint: AppTheme.warning) {
                    if let me {
                        HStack {
                            Text(Lf("ترتيبك #%@", "\(me.rank)"))
                                .font(.title3.bold()).foregroundStyle(AppTheme.brand)
                            Spacer()
                            Label("\(me.points)", systemImage: "star.fill")
                                .foregroundStyle(AppTheme.warning)
                            if me.streak > 0 {
                                Label("\(me.streak)", systemImage: "flame.fill")
                                    .foregroundStyle(AppTheme.streak)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    ForEach(top.prefix(3)) { entry in
                        HStack(spacing: 10) {
                            Text(medal(entry.rank))
                            Text(entry.name).lineLimit(1)
                            if entry.isMe {
                                Text(L("أنت")).font(.caption2.bold()).foregroundStyle(AppTheme.brand)
                            }
                            Spacer()
                            Text("\(entry.points)").monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                    if !loaded {
                        Text(L("جارٍ التحميل…")).font(.caption).foregroundStyle(.secondary)
                    } else if top.isEmpty && me == nil {
                        Text(L("احفظ تقدّمك من شاشة الحساب لتدخل المنافسة."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .task { await load() }
        }
    }

    private func medal(_ rank: Int) -> String {
        [1: "🥇", 2: "🥈", 3: "🥉"][rank] ?? "#\(rank)"
    }

    private func load() async {
        defer { loaded = true }
        guard let result = try? await service.leaderboard() else { return }
        top = result.top
        me = result.me
    }
}

private struct QuickActionCard: View {
    let title: String
    let icon: String
    var colors: [Color] = [AppTheme.brand, AppTheme.brandSecondary]
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.22), in: Circle())
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 118)
        .padding(.vertical, 10)
        .background(AppTheme.gradient(colors),
                   in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .cardShadow()
        .accessibilityElement(children: .combine)
    }
}
