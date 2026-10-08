import LocalAuthentication
import SwiftUI
import UIKit

/// Face ID, Touch ID or the device passcode before Basir shows anything,
/// when the person turned the lock on in Settings.
enum AppLock {
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    /// Turning the lock on needs a passcode on the device; otherwise it is undone.
    @MainActor
    static func confirmCanLock(settings: SettingsStore, l10n: L10n) {
        var error: NSError?
        if !LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            settings.appLock = false
            UIAccessibility.post(notification: .announcement, argument: l10n.t(
                "لا يمكن القفل لأن الجهاز بلا رمز دخول.", "The lock needs a device passcode, which is not set."))
        }
    }
}

struct AppLockModifier: ViewModifier {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var l10n: L10n
    @Environment(\.scenePhase) private var scenePhase
    @State private var locked = false
    @State private var covered = false
    @State private var authenticating = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if settings.appLock && (locked || covered) {
                    lockScreen
                }
            }
            .onAppear {
                if settings.appLock {
                    locked = true
                    unlock()
                }
            }
            .onChange(of: scenePhase) { phase in
                guard settings.appLock else { return }
                switch phase {
                case .background:
                    locked = true
                case .inactive:
                    // Hide content in the app switcher without asking yet.
                    covered = true
                case .active:
                    covered = false
                    if locked { unlock() }
                @unknown default:
                    break
                }
            }
    }

    private var lockScreen: some View {
        ZStack {
            BasirPalette.background.ignoresSafeArea()
            VStack(spacing: BasirSpacing.l) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(BasirPalette.accent)
                    .accessibilityHidden(true)
                Text(l10n.t("بصير مقفل", "Basir is locked"))
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                if locked {
                    PrimaryActionButton(title: l10n.t("افتح القفل", "Unlock"), systemImage: "faceid") { unlock() }
                        .padding(.horizontal, BasirSpacing.xl)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func unlock() {
        guard !authenticating else { return }
        authenticating = true
        Task {
            let ok = await AppLock.authenticate(reason: l10n.t("افتح بصير", "Unlock Basir"))
            authenticating = false
            if ok {
                locked = false
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            }
        }
    }
}
