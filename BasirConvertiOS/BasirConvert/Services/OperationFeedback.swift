import Foundation
import UIKit
import AudioToolbox
import UserNotifications

@MainActor
enum OperationFeedback {
    static func play(_ event: Event, theme: SoundTheme) {
        guard theme != .off else { return }
        switch theme {
        case .off:
            break
        case .gentle:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(event == .failed ? .error : (event == .completed ? .success : .warning))
        case .clear:
            AudioServicesPlaySystemSound(event == .completed ? 1025 : (event == .failed ? 1073 : 1104))
        case .tactile:
            let generator = UIImpactFeedbackGenerator(style: event == .progress ? .light : .heavy)
            generator.impactOccurred()
        }
    }

    static func selectionChanged() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    static func warningImpact() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
    }

    static func requestNotificationPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    enum Event { case progress, paused, completed, failed }
}

