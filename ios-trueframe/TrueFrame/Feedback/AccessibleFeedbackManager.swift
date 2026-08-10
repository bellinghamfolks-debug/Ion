import Foundation
import AVFoundation
import CoreHaptics
import UIKit

/// Speech + haptic output. Speech is reserved for meaningful changes (the
/// throttling lives in `GuidanceThrottle`); haptics give continuous, silent
/// leveling cues so an experienced user can level without any speech.
public final class AccessibleFeedbackManager {

    public enum HapticCue { case rotateLeft, rotateRight, level, shutterReady, captured }

    private let synth = AVSpeechSynthesizer()
    private var hapticEngine: CHHapticEngine?
    public var speechEnabled = true
    public var hapticsEnabled = true
    /// When true, most leveling is haptic and speech is reserved for framing.
    public var hapticFirst = false

    public init() {
        configureAudioSession()
        prepareHaptics()
    }

    private func configureAudioSession() {
        // Duck other audio and mix, so VoiceOver / music continue quietly.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers, .mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        hapticEngine = try? CHHapticEngine()
        try? hapticEngine?.start()
    }

    /// Speak `text`. `interrupt` stops the current utterance (used when a
    /// higher-priority message must be heard now).
    public func speak(_ text: String, interrupt: Bool = true) {
        guard speechEnabled, !text.isEmpty else { return }
        if interrupt && synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        // Pick a voice matching the script (Arabic vs Latin) for correct pronunciation.
        let isArabic = text.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
        u.voice = AVSpeechSynthesisVoice(language: isArabic ? "ar-SA" : "en-US")
        synth.speak(u)
    }

    public func stopSpeaking() { synth.stopSpeaking(at: .immediate) }

    // MARK: Haptics

    public func play(_ cue: HapticCue) {
        guard hapticsEnabled else { return }
        switch cue {
        case .level, .captured, .shutterReady:
            UINotificationFeedbackGenerator().notificationOccurred(cue == .captured ? .success : .success)
        case .rotateLeft, .rotateRight:
            // Directional pattern: two taps for left, one for right (customizable).
            let gen = UIImpactFeedbackGenerator(style: .rigid)
            gen.impactOccurred()
            if cue == .rotateLeft {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { gen.impactOccurred() }
            }
        }
    }
}
