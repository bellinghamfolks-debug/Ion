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
    var body: some View {
        TabView {
            NavigationStack { LearningHomeView() }
                .tabItem { Label(L("الرئيسية"), systemImage: "house.fill") }
            NavigationStack { CurriculumView() }
                .tabItem { Label(L("التعلّم"), systemImage: "graduationcap.fill") }
            NavigationStack { PracticeHubView() }
                .tabItem { Label(L("التدريب"), systemImage: "waveform.badge.mic") }
            NavigationStack { ReviewView() }
                .tabItem { Label(L("المراجعة"), systemImage: "arrow.triangle.2.circlepath") }
            NavigationStack { SettingsView() }
                .tabItem { Label(L("الإعدادات"), systemImage: "gearshape.fill") }
        }
        .tint(AppTheme.brand)
    }
}
