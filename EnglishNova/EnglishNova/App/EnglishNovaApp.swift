import SwiftUI
import GoogleSignIn

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
                .environment(\.locale, Locale(identifier: container.settings.interfaceLanguage == .arabic ? "ar" : "en"))
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
