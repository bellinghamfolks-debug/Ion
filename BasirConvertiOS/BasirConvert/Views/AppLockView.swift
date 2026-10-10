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

    /// Turning the lock on or off always asks for Face ID or the passcode
    /// first, and the setting changes only when that succeeds. Turning it on
    /// takes effect at once: the next return to Basir asks again.
    @MainActor
    static func change(to enabled: Bool, settings: SettingsStore, l10n: L10n) async {
        guard enabled != settings.appLock else { return }
        var error: NSError?
        guard LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            announce(l10n.t("لتفعيل قفل بصير، عيّن رمز دخول لجهازك أولًا من إعدادات iPhone.",
                            "To use Basir’s app lock, set a device passcode first in iPhone Settings."))
            return
        }
        let reason = enabled
            ? l10n.t("تحقق من هويتك لتفعيل قفل بصير", "Verify your identity to turn on Basir’s lock")
            : l10n.t("تحقق من هويتك لإيقاف قفل بصير", "Verify your identity to turn off Basir’s lock")
        guard await authenticate(reason: reason) else {
            announce(enabled
                ? l10n.t("لم يُفعَّل القفل لأن التحقق لم يكتمل.", "The lock was not turned on because verification did not finish.")
                : l10n.t("بقي القفل مفعّلًا لأن التحقق لم يكتمل.", "The lock is still on because verification did not finish."))
            return
        }
        settings.appLock = enabled
        settings.save()
        OperationFeedback.selectionChanged()
        announce(enabled
            ? l10n.t("تم تفعيل القفل. سيطلب بصير التحقق من هويتك كلما عدت إليه.",
                     "The lock is on. Basir will ask you to verify your identity each time you return.")
            : l10n.t("تم إيقاف القفل.", "The lock is off."))
    }

    private static func announce(_ text: String) {
        // After the Face ID sheet closes, VoiceOver needs a moment before it speaks.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            UIAccessibility.post(notification: .announcement, argument: text)
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
                    PrimaryActionButton(title: l10n.t("فتح بصير", "Unlock Basir"), systemImage: "faceid") { unlock() }
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
            let ok = await AppLock.authenticate(reason: l10n.t("تحقق من هويتك لفتح بصير", "Verify your identity to open Basir"))
            authenticating = false
            if ok {
                locked = false
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            }
        }
    }
}
