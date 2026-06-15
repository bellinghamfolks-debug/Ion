import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: UserSession

    var body: some View {
        Group {
            if session.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .task { await session.load() }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("الرئيسية", systemImage: "house.fill") }
            NavigationStack { CurriculumView() }
                .tabItem { Label("التعلّم", systemImage: "graduationcap.fill") }
            NavigationStack { PracticeHubView() }
                .tabItem { Label("التدريب", systemImage: "waveform.badge.mic") }
            NavigationStack { ReviewView() }
                .tabItem { Label("المراجعة", systemImage: "arrow.triangle.2.circlepath") }
            NavigationStack { SettingsView() }
                .tabItem { Label("الإعدادات", systemImage: "gearshape.fill") }
        }
    }
}
