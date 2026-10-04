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
    }
}
