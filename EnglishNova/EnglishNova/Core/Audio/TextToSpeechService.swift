import AVFoundation
import Combine

@MainActor
final class TextToSpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, language: String = "en-US", rate: Float = 0.45) {
        speakInternal(text, language: language, rate: rate)
    }

    func speak(_ text: String, accent: AccentVariant, rate: Float = 0.45) {
        speakInternal(text, language: accent.localeIdentifier, rate: rate)
    }

    private func speakInternal(_ text: String, language: String, rate: Float) {
        stop()
        // Re-establish a playback-capable session before every utterance. The
        // mic flow (SpeechService) reconfigures the shared AVAudioSession for
        // recording and then deactivates it; without restoring a playback
        // category here the synthesizer stays muted after the first mic use.
        // .duckOthers lets us speak over other audio; .spokenAudio is tuned for
        // voice and routes correctly to the speaker, receiver, or headphones.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true, options: [])
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.preferredVoice(for: language)
        utterance.rate = min(max(rate, 0.25), 0.58)
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    // MARK: - Natural voices

    /// A voice the learner can pick, with its download quality.
    struct VoiceOption: Identifiable, Hashable {
        let id: String
        let name: String
        let language: String
        let quality: AVSpeechSynthesisVoiceQuality

        var qualityRank: Int {
            switch quality {
            case .premium: return 3
            case .enhanced: return 2
            default: return 1
            }
        }
    }

    nonisolated static func preferenceKey(for language: String) -> String { "tts.voice.\(language)" }

    /// English voices for a locale, best quality first. Novelty and Personal
    /// Voices are excluded: they are hard to understand for learners.
    nonisolated static func voices(for language: String) -> [VoiceOption] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language }
            .filter { !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice) }
            .map { VoiceOption(id: $0.identifier, name: $0.name, language: $0.language, quality: $0.quality) }
            .sorted { lhs, rhs in
                lhs.qualityRank != rhs.qualityRank ? lhs.qualityRank > rhs.qualityRank : lhs.name < rhs.name
            }
    }

    /// The learner's chosen voice, otherwise the most natural installed one.
    nonisolated static func preferredVoice(for language: String) -> AVSpeechSynthesisVoice? {
        if let identifier = UserDefaults.standard.string(forKey: preferenceKey(for: language)),
           let chosen = AVSpeechSynthesisVoice(identifier: identifier) {
            return chosen
        }
        if let best = voices(for: language).first, let voice = AVSpeechSynthesisVoice(identifier: best.id) {
            return voice
        }
        return AVSpeechSynthesisVoice(language: language)
    }

    /// True when only the basic compact voice is installed for the locale.
    nonisolated static func hasOnlyBasicVoices(for language: String) -> Bool {
        !voices(for: language).contains { $0.qualityRank > 1 }
    }

    func choose(_ option: VoiceOption?, for language: String) {
        if let option {
            UserDefaults.standard.set(option.id, forKey: Self.preferenceKey(for: language))
        } else {
            UserDefaults.standard.removeObject(forKey: Self.preferenceKey(for: language))
        }
        objectWillChange.send()
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
