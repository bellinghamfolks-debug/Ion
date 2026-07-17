import SwiftUI

@main
struct EnglishNovaApp: App {
    @StateObject private var container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
                .environmentObject(container.settings)
                .environmentObject(container.session)
                .environmentObject(container.networkMonitor)
                .environmentObject(container.speechService)
                .environmentObject(container.textToSpeech)
                .environmentObject(container.reminderService)
                .environmentObject(container.accountService)
                .environmentObject(container.progressSyncService)
                .environment(\.layoutDirection, container.settings.interfaceLanguage == .arabic ? .rightToLeft : .leftToRight)
                // Force the interface locale so system-rendered strings (weekday
                // names, Stepper's Increment/Decrement, date formats…) follow the
                // chosen language instead of leaking English.
                .environment(\.locale, Locale(identifier: container.settings.interfaceLanguage == .arabic ? "ar" : "en"))
        }
    }
}
