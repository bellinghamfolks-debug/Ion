import SwiftUI
import UIKit
import UserNotifications

final class BasirAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Reconnects the background requests that follow server tasks, so
        // their answers reach Basir even after it was closed.
        JobWatcher.shared.resume()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // In the foreground the app already shows progress, so progress updates
        // only refresh Notification Center; results and failures still show a banner.
        let kind = notification.request.content.userInfo["basir_kind"] as? String
        if kind == "progress" || kind == "working" {
            completionHandler([.list])
        } else {
            completionHandler([.banner, .list, .sound])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Tapping a Basir notification opens that task's details.
        if let value = response.notification.request.content.userInfo["job_id"] as? String,
           let jobID = UUID(uuidString: value) {
            Task { @MainActor in IntentRouter.shared.pendingJobID = jobID }
        }
        completionHandler()
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushRegistrar.shared.didReceiveDeviceToken(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushRegistrar.shared.didFailToRegister(error) }
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        if identifier == JobWatcher.sessionIdentifier {
            JobWatcher.shared.reconnect(identifier: identifier, completionHandler: completionHandler)
            return
        }
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
    @StateObject private var intents = IntentRouter.shared

    init() {
        #if DEBUG
        ScreenshotSeed.runIfRequested()
        #endif
        BackgroundExecution.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modifier(AppLockModifier())
                .environmentObject(l10n)
                .environmentObject(settings)
                .environmentObject(viewModel)
                .environmentObject(network)
                .environmentObject(outputLibrary)
                .environmentObject(intents)
                .environment(\.layoutDirection, l10n.layoutDirection)
                .environment(\.locale, l10n.locale)
                // Purchases are followed from launch, so a renewal or an
                // approved Ask to Buy is never missed.
                .task { SubscriptionStore.shared.start(language: l10n.isArabic ? "ar" : "en") }
                .onChange(of: scenePhase) { phase in
                    if phase == .background {
                        BackgroundExecution.shared.schedule()
                        JobWatcher.shared.appWillLeave()
                    } else if phase == .active {
                        Task { await SubscriptionStore.shared.refreshStatus() }
                        JobWatcher.shared.prune()
                        JobWatcher.shared.resume()
                    }
                }
        }
    }
}

