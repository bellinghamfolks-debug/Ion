import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: UserSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if showSplash {
                SplashView()
                    .transition(reduceMotion ? .identity : .opacity)
            } else {
                Group {
                    if session.hasCompletedOnboarding {
                        MainTabView()
                    } else {
                        OnboardingView()
                    }
                }
                .transition(reduceMotion ? .identity : .opacity)
            }
        }
        .toastLayer()
        .task { await session.load() }
        .task { await Localizer.shared.refreshFromServer() }
        .task {
            let delay: UInt64 = reduceMotion ? 120_000_000 : 700_000_000
            try? await Task.sleep(nanoseconds: delay)
            if reduceMotion {
                showSplash = false
            } else {
                withAnimation(.easeOut(duration: 0.22)) { showSplash = false }
            }
        }
    }
}

struct MainTabView: View {
    enum Tab: Hashable { case today, path, practice, me }
    @EnvironmentObject private var container: AppContainer
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Tab = .today

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { LearningHomeView() }
                .tabItem { Label(LE("اليوم", "Today"), systemImage: "sun.max.fill") }
                .tag(Tab.today)
            NavigationStack { PathView() }
                .tabItem { Label(LE("المسار", "Path"), systemImage: "map.fill") }
                .tag(Tab.path)
            NavigationStack { PracticeHubView() }
                .tabItem { Label(L("التدريب"), systemImage: "waveform.badge.mic") }
                .tag(Tab.practice)
            NavigationStack { MeView() }
                .tabItem { Label(LE("أنا", "Me"), systemImage: "person.crop.circle.fill") }
                .tag(Tab.me)
        }
        .tint(AppTheme.brand)
        .onChange(of: scenePhase) { _, phase in
            // Re-plan reminders with fresh numbers whenever the app leaves the screen.
            if phase == .background { Task { await refreshSmartReminders() } }
        }
    }

    private func refreshSmartReminders() async {
        let settings = container.settings
        guard settings.reminderEnabled else { return }
        await container.reminderService.refreshAuthorization()
        let session = container.session
        async let due = container.vocabularyRepository.dueCards(on: .now)
        async let memory = container.learningMemoryRepository.snapshot()
        async let progress = container.progressRepository.snapshot()
        let catalog = try? await container.courseRepository.catalog()
        let loadedProgress = await progress
        let dueCount = (await due).count
        let loadedMemory = await memory
        let lessons = catalog?.levels.first { $0.level == session.selectedLevel }?.units.flatMap(\.lessons) ?? []
        let next = lessons.first { loadedProgress.lessons[$0.id]?.completedAt == nil }
        let studiedToday = session.lastStudyDate.map(Calendar.current.isDateInToday) ?? false
        let context = ReminderPlanner.Context(
            hour: settings.reminderHour,
            minute: settings.reminderMinute,
            studiedToday: studiedToday,
            streak: session.streak,
            dueReviews: dueCount,
            openMistakes: RemedialPracticeEngine.items(mistakes: loadedMemory.mistakes, catalog: catalog).count,
            nextLessonTitle: next.map { LE($0.titleAr, $0.titleEn) }
        )
        await container.reminderService.scheduleSmart(context)
    }
}
