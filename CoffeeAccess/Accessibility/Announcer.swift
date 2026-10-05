import AVFoundation
import SwiftUI
import UIKit

/// Speaks status changes. With VoiceOver on it posts announcements (so they
/// queue politely with VoiceOver's own speech); without it, it can speak
/// through the speech synthesizer for low-vision users who opt in.
@MainActor
final class Announcer {
    static let shared = Announcer()

    var speakWithoutVoiceOver = false
    var hapticsEnabled = true

    private let synthesizer = AVSpeechSynthesizer()
    private let notification = UINotificationFeedbackGenerator()
    private let impact = UIImpactFeedbackGenerator(style: .medium)

    func announce(_ text: String, priority: Priority = .normal) {
        guard !text.isEmpty else { return }
        if UIAccessibility.isVoiceOverRunning {
            let attributed = NSAttributedString(string: text, attributes: [
                .accessibilitySpeechAnnouncementPriority: priority == .high ? UIAccessibilityPriority.high : UIAccessibilityPriority.default,
                .accessibilitySpeechQueueAnnouncement: priority != .high,
            ])
            UIAccessibility.post(notification: .announcement, argument: attributed)
        } else if speakWithoutVoiceOver {
            if priority == .high { synthesizer.stopSpeaking(at: .immediate) }
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: AppLanguage.current.speechCode)
            synthesizer.speak(utterance)
        }
    }

    enum Priority { case normal, high }

    func success() {
        guard hapticsEnabled else { return }
        notification.notificationOccurred(.success)
    }

    func warning() {
        guard hapticsEnabled else { return }
        notification.notificationOccurred(.warning)
    }

    func tick() {
        guard hapticsEnabled else { return }
        impact.impactOccurred(intensity: 0.6)
    }
}
