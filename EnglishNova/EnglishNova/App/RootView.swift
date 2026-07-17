import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: UserSession
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if showSplash {
                SplashView()
                    .transition(.opacity)
            } else {
                Group {
                    if session.hasCompletedOnboarding {
                        MainTabView()
                    } else {
                        OnboardingView()
                    }
                }
                .transition(.opacity)
            }
        }
        .task { await session.load() }
        .task {
            // Keep the branded splash for ~3 seconds, then reveal the app.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation(.easeInOut(duration: 0.4)) { showSplash = false }
        }
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
        .tint(AppTheme.brand)   // brand accent across tabs, links and controls
    }
}
