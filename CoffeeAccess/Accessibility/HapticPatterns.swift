import AVFoundation
import SwiftUI
import UIKit

/// Vibration patterns that say what the machine is doing, for people who
/// can neither see the screen nor hear speech: each phase has its own rhythm.
@MainActor
enum HapticPatterns {
    enum Pattern: String, CaseIterable, Identifiable {
        case started, grinding, pouring, milk, finished, problem, attention

        var id: String { rawValue }
        var title: String { L("haptic.\(rawValue)") }

        /// Pulses: intensity 0…1 and the pause after it in seconds.
        var pulses: [(Double, Double)] {
            switch self {
            case .started: return [(0.6, 0.15)]
            case .grinding: return [(0.9, 0.08), (0.9, 0.08), (0.9, 0.08)]
            case .pouring: return [(0.4, 0.35), (0.4, 0.35)]
            case .milk: return [(0.7, 0.5), (0.7, 0.5)]
            case .finished: return [(1, 0.12), (1, 0.12), (1, 0.4), (1, 0)]
            case .problem: return [(1, 0.6), (1, 0.6), (1, 0)]
            case .attention: return [(0.8, 0.2), (0.3, 0)]
            }
        }
    }

    static func play(_ pattern: Pattern) {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        Task { @MainActor in
            for (intensity, pause) in pattern.pulses {
                generator.impactOccurred(intensity: intensity)
                if pause > 0 { try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000)) }
            }
        }
    }

    static func pattern(for activity: MachineActivity) -> Pattern? {
        switch activity {
        case .grinding: return .grinding
        case .brewingCoffee, .dispensingWater: return .pouring
        case .dispensingMilk, .steaming: return .milk
        default: return nil
        }
    }
}

extension Notification.Name {
    /// The phone was shaken (posted by the window).
    static let deviceDidShake = Notification.Name("CoffeeAccess.deviceDidShake")
}

extension UIWindow {
    /// Shake anywhere: the app says the machine's status.
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { NotificationCenter.default.post(name: .deviceDidShake, object: nil) }
        super.motionEnded(motion, with: event)
    }
}

/// Speech voices for announcements spoken without VoiceOver.
enum SpeechVoices {
    struct Voice: Identifiable, Hashable {
        let id: String
        let name: String
    }

    static func available(for language: AppLanguage = .current) -> [Voice] {
        let prefix = language == .arabic ? "ar" : "en"
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) }
            .sorted { $0.quality.rawValue == $1.quality.rawValue ? $0.name < $1.name : $0.quality.rawValue > $1.quality.rawValue }
            .map { Voice(id: $0.identifier, name: "\($0.name) (\($0.language))") }
    }
}
