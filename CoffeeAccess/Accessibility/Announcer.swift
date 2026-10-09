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
    /// A chosen voice (empty for the language's default) and rate 0…1.
    var voiceID = ""
    var rate: Double = 0.5
    /// A Focus asked for quiet: nothing is spoken without VoiceOver.
    var focusQuiet = false

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
        } else if speakWithoutVoiceOver, !focusQuiet {
            if priority == .high { synthesizer.stopSpeaking(at: .immediate) }
            speak(text)
        }
    }

    enum Priority { case normal, high }

    /// Speaks with the chosen voice and rate, whatever VoiceOver is doing
    /// (used to preview a voice).
    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = (voiceID.isEmpty ? nil : AVSpeechSynthesisVoice(identifier: voiceID))
            ?? AVSpeechSynthesisVoice(language: AppLanguage.current.speechCode)
        let minimum = Double(AVSpeechUtteranceMinimumSpeechRate), maximum = Double(AVSpeechUtteranceMaximumSpeechRate)
        utterance.rate = Float(minimum + (maximum - minimum) * max(0, min(1, rate)))
        synthesizer.speak(utterance)
    }

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
