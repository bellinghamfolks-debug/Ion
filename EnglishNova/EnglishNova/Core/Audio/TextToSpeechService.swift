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
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = min(max(rate, 0.25), 0.58)
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
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
