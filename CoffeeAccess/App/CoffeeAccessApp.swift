import SwiftUI
import UIKit
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
                // The machine's clock follows the phone's when the time or time zone changes.
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    model.syncClockIfNeeded(force: true)
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                    model.syncClockIfNeeded(force: true)
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
    @State var showingWhatsNew = false

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
                        NavigationStack { BrewingView() }.environment(model)
                    }
            } else {
                tabs
            }
        }
        .onOpenURL(perform: open)
        .sheet(item: $importedRecipe) { ImportedRecipeSheet(recipe: $0) }
        .sheet(isPresented: Binding(get: { model.askWhichBean }, set: { model.askWhichBean = $0 })) {
            WhichBeanSheet().environment(model)
        }
        .sheet(isPresented: $showingWhatsNew) { WhatsNewView() }
        .alert(L("offer.title"), isPresented: Binding(get: { model.offer != nil }, set: { if !$0 { model.offer = nil } }),
               presenting: model.offer) { offer in
            Button(L("action.brewNow")) {
                model.offer = nil
                Task { await model.brew(offer.recipe) }
            }
            Button(L("offer.notNow"), role: .cancel) { model.offer = nil }
        } message: { offer in
            Text(offer.message)
        }
        .onChange(of: model.pendingScheduledRecipe) { _, recipe in if recipe != nil { tab = .home } }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            guard model.settings.shakeForStatus else { return }
            if model.settings.hapticOnly { HapticPatterns.play(.attention) }
            Announcer.shared.announce(model.statusSentence, priority: .high)
            if !UIAccessibility.isVoiceOverRunning, !model.settings.speakWithoutVoiceOver { Announcer.shared.speak(model.statusSentence) }
        }
        .onAppear(perform: checkWhatsNew)
    }

    /// After an update (not on a first install), say what is new once.
    private func checkWhatsNew() {
        guard model.settings.lastSeenVersion != WhatsNew.version else { return }
        let firstRun = !model.settings.hasCompletedOnboarding
        model.updateSettings { $0.lastSeenVersion = WhatsNew.version }
        if !firstRun { showingWhatsNew = true }
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
            NavigationStack { BrewingView() }
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
