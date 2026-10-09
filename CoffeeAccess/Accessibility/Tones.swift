import AVFoundation

/// Short synthesized tones: a pitch that rises with an amount while it is
/// changed, and a distinct little sound for each brewing phase. Generated on
/// the phone; no sound files.
@MainActor
final class Tones {
    static let shared = Tones()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var started = false

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    enum Cue {
        case grinding, pouring, milk, ready, problem

        /// Notes (Hz) played one after another.
        var notes: [Double] {
            switch self {
            case .grinding: return [220, 196]
            case .pouring: return [330, 392]
            case .milk: return [523, 494, 523]
            case .ready: return [523, 659, 784]
            case .problem: return [392, 311]
            }
        }
    }

    /// A tone between 300 and 900 Hz for a fraction 0…1.
    func level(_ fraction: Double) {
        play([300 + 600 * max(0, min(1, fraction))], noteLength: 0.07)
    }

    func cue(_ cue: Cue) {
        play(cue.notes, noteLength: 0.12)
    }

    private func play(_ notes: [Double], noteLength: Double) {
        guard prepare() else { return }
        let sampleRate = format.sampleRate
        let framesPerNote = AVAudioFrameCount(sampleRate * noteLength)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesPerNote * AVAudioFrameCount(notes.count)),
              let samples = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = buffer.frameCapacity
        for (index, frequency) in notes.enumerated() {
            for frame in 0..<Int(framesPerNote) {
                let t = Double(frame) / sampleRate
                // Short fade in and out so the tone does not click.
                let edge = min(1, min(t, noteLength - t) / 0.01)
                samples[index * Int(framesPerNote) + frame] = Float(sin(2 * .pi * frequency * t) * 0.25 * edge)
            }
        }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    private func prepare() -> Bool {
        if started { return true }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try engine.start()
            started = true
        } catch {
            started = false
        }
        return started
    }
}
