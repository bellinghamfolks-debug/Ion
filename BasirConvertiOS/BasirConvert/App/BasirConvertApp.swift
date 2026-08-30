import SwiftUI
import UIKit
import UserNotifications

final class BasirAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundTransferCoordinator.shared.reconnectBackgroundEvents(
            identifier: identifier,
            completionHandler: completionHandler
        )
    }
}

@main
struct BasirConvertApp: App {
    @UIApplicationDelegateAdaptor(BasirAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var l10n = L10n()
    @StateObject private var settings = SettingsStore()
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var network = NetworkMonitor.shared
    @StateObject private var outputLibrary = OutputLibraryStore()

    init() {
        BackgroundExecution.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(l10n)
                .environmentObject(settings)
                .environmentObject(viewModel)
                .environmentObject(network)
                .environmentObject(outputLibrary)
                .environment(\.layoutDirection, l10n.layoutDirection)
                .environment(\.locale, l10n.locale)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { phase in
                    if phase == .background {
                        BackgroundExecution.shared.schedule()
                    }
                }
        }
    }
}

