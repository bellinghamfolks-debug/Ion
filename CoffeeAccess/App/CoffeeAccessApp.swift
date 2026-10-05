import SwiftUI

@main
struct CoffeeAccessApp: App {
    @State var model = AppModel.shared
    @Environment(\.scenePhase) var scenePhase

    init() {
        Theme.configureBars()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.accent)
                .onAppear { model.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, model.connection.isConnected { model.link.refresh() }
                }
        }
    }
}

enum AppTab: Hashable {
    case home, drinks, machine, settings
}

struct RootView: View {
    @Environment(AppModel.self) var model
    @State var tab: AppTab = .home

    var body: some View {
        if model.settings.hasCompletedOnboarding {
            tabs
        } else {
            OnboardingView()
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            HomeView(selectedTab: $tab)
                .tabItem { Label(L("tab.home"), systemImage: "house") }
                .tag(AppTab.home)
            MachineView()
                .tabItem { Label(L("tab.machine"), image: "MachineTab") }
                .tag(AppTab.machine)
            DrinksView()
                .tabItem { Label(L("tab.drinks"), systemImage: "cup.and.saucer") }
                .tag(AppTab.drinks)
            SettingsView()
                .tabItem { Label(L("tab.settings"), systemImage: "person") }
                .tag(AppTab.settings)
        }
        .fullScreenCover(isPresented: Binding(
            get: { model.session != nil },
            set: { if !$0 { model.dismissSession() } }
        )) {
            BrewingView()
                .environment(model)
        }
        .alert(L("alert.title"), isPresented: Binding(
            get: { model.lastMessage != nil },
            set: { if !$0 { model.lastMessage = nil } }
        )) {
            Button(L("action.ok"), role: .cancel) { model.lastMessage = nil }
        } message: {
            Text(model.lastMessage ?? "")
        }
    }
}
