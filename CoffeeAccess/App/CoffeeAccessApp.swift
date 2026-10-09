import SwiftUI
import UserNotifications

@main
struct CoffeeAccessApp: App {
    @State var model = AppModel.shared
    @Environment(\.scenePhase) var scenePhase

    init() {
        Theme.configureBars()
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        NotificationManager.shared.registerCategories()
        WatchBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.accent)
                .onAppear {
                    model.start()
                    model.appBecameActive()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, model.connection.isConnected { model.link.refresh() }
                    if phase == .active { model.appBecameActive() }
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
    @State var importedRecipe: Recipe?

    var body: some View {
        Group {
            if !model.settings.hasCompletedOnboarding {
                OnboardingView()
            } else if model.settings.simpleMode {
                SimpleModeView()
                    .fullScreenCover(isPresented: Binding(
                        get: { model.session != nil },
                        set: { if !$0 { model.dismissSession() } }
                    )) {
                        BrewingView().environment(model)
                    }
            } else {
                tabs
            }
        }
        .onOpenURL(perform: open)
        .sheet(item: $importedRecipe) { ImportedRecipeSheet(recipe: $0) }
    }

    /// coffeeaccess:// links from widgets, controls and shared recipes.
    private func open(_ url: URL) {
        if let recipe = RecipeShare.recipe(from: url) {
            importedRecipe = recipe
            return
        }
        switch url.host {
        case "usual":
            tab = .home
            model.pendingScheduledRecipe = model.usualRecipe
        case "stop":
            Task { await model.stopBrewing() }
        default:
            tab = .home
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
