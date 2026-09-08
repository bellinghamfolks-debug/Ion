import AudioToolbox
import Foundation
import UIKit

/// Short, distinctive interface sounds for meaningful learning events.
///
/// The engine intentionally uses System Sound Services instead of owning an
/// AVAudioSession. That keeps it out of the microphone/TTS audio pipeline and
/// lets iOS treat every cue as a UI sound, so the user's sound-effects / silent
/// preferences remain authoritative.
@MainActor
final class FeedbackSoundEngine {
    static let shared = FeedbackSoundEngine()

    enum Cue: String, CaseIterable {
        case success
        case failure
        case correct
        case incorrect
        case info
        case saved
        case sent
        case received
        case recordingStart
        case recordingStop
        case lessonComplete
        case streak
        case milestone

        fileprivate var recipe: [Tone] {
            switch self {
            case .success:
                return [
                    Tone(659.25, 0.060, 0.30, 0.010),
                    Tone(830.61, 0.070, 0.29, 0.010),
                    Tone(1_046.50, 0.120, 0.28, 0)
                ]
            case .failure:
                return [
                    Tone(392.00, 0.075, 0.24, 0.012),
                    Tone(311.13, 0.095, 0.23, 0.012),
                    Tone(246.94, 0.135, 0.21, 0)
                ]
            case .correct:
                return [
                    Tone(783.99, 0.052, 0.27, 0.008),
                    Tone(1_174.66, 0.092, 0.25, 0)
                ]
            case .incorrect:
                return [
                    Tone(349.23, 0.068, 0.23, 0.009),
                    Tone(293.66, 0.112, 0.21, 0)
                ]
            case .info:
                return [Tone(659.25, 0.080, 0.16, 0)]
            case .saved:
                return [
                    Tone(587.33, 0.048, 0.21, 0.007),
                    Tone(880.00, 0.090, 0.20, 0)
                ]
            case .sent:
                return [
                    Tone(523.25, 0.040, 0.18, 0.006),
                    Tone(698.46, 0.048, 0.18, 0.006),
                    Tone(987.77, 0.078, 0.17, 0)
                ]
            case .received:
                return [
                    Tone(987.77, 0.038, 0.15, 0.006),
                    Tone(783.99, 0.047, 0.16, 0.006),
                    Tone(659.25, 0.078, 0.17, 0)
                ]
            case .recordingStart:
                return [
                    Tone(440.00, 0.038, 0.18, 0.005),
                    Tone(659.25, 0.072, 0.19, 0)
                ]
            case .recordingStop:
                return [
                    Tone(659.25, 0.038, 0.18, 0.005),
                    Tone(440.00, 0.078, 0.19, 0)
                ]
            case .lessonComplete:
                return [
                    Tone(523.25, 0.050, 0.25, 0.006),
                    Tone(659.25, 0.058, 0.26, 0.006),
                    Tone(783.99, 0.070, 0.27, 0.006),
                    Tone(1_046.50, 0.135, 0.26, 0)
                ]
            case .streak:
                return [
                    Tone(587.33, 0.048, 0.23, 0.005),
                    Tone(783.99, 0.052, 0.24, 0.005),
                    Tone(987.77, 0.058, 0.23, 0.005),
                    Tone(1_318.51, 0.110, 0.22, 0)
                ]
            case .milestone:
                return [
                    Tone(523.25, 0.046, 0.23, 0.004),
                    Tone(659.25, 0.048, 0.24, 0.004),
                    Tone(783.99, 0.050, 0.25, 0.004),
                    Tone(987.77, 0.066, 0.24, 0.004),
                    Tone(1_318.51, 0.128, 0.23, 0)
                ]
            }
        }

        fileprivate var minimumInterval: TimeInterval {
            switch self {
            case .correct, .incorrect, .info: return 0.12
            case .recordingStart, .recordingStop: return 0.18
            default: return 0.30
            }
        }
    }

    fileprivate struct Tone {
        let frequency: Double
        let duration: TimeInterval
        let volume: Double
        let gap: TimeInterval

        init(_ frequency: Double, _ duration: TimeInterval, _ volume: Double, _ gap: TimeInterval) {
            self.frequency = frequency
            self.duration = duration
            self.volume = volume
            self.gap = gap
        }
    }

    private var soundIDs: [Cue: SystemSoundID] = [:]
    private var lastPlayedAt: [Cue: TimeInterval] = [:]
    private var soundEffectsEnabled = true
    private var hapticsEnabled = true

    private init() {}

    func configure(soundEffectsEnabled: Bool, hapticsEnabled: Bool) {
        self.soundEffectsEnabled = soundEffectsEnabled
        self.hapticsEnabled = hapticsEnabled
        if soundEffectsEnabled { prewarm() }
    }

    func prewarm() {
        guard soundEffectsEnabled else { return }
        for cue in Cue.allCases {
            _ = systemSoundID(for: cue)
        }
    }

    func play(_ cue: Cue) {
        let now = Date().timeIntervalSinceReferenceDate
        if let last = lastPlayedAt[cue], now - last < cue.minimumInterval { return }
        lastPlayedAt[cue] = now

        if soundEffectsEnabled, let soundID = systemSoundID(for: cue) {
            AudioServicesPlaySystemSound(soundID)
        }
        if hapticsEnabled {
            playHaptic(for: cue)
        }
    }

    private func systemSoundID(for cue: Cue) -> SystemSoundID? {
        if let existing = soundIDs[cue] { return existing }

        do {
            let url = try soundURL(for: cue)
            var soundID: SystemSoundID = 0
            guard AudioServicesCreateSystemSoundID(url as CFURL, &soundID) == kAudioServicesNoError else {
                return nil
            }

            // System Sound UI sounds respect the user's Sound Effects / silent
            // preference. The property defaults to 1, but set it explicitly so
            // a future refactor cannot accidentally turn these cues into alerts.
            var mutableSoundID = soundID
            var isUISound: UInt32 = 1
            _ = AudioServicesSetProperty(
                kAudioServicesPropertyIsUISound,
                UInt32(MemoryLayout<SystemSoundID>.size),
                &mutableSoundID,
                UInt32(MemoryLayout<UInt32>.size),
                &isUISound
            )

            soundIDs[cue] = soundID
            return soundID
        } catch {
            return nil
        }
    }

    private func soundURL(for cue: Cue) throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EnglishNovaFeedback", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("\(cue.rawValue).wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            try Self.wavData(for: cue.recipe).write(to: url, options: .atomic)
        }
        return url
    }

    private func playHaptic(for cue: Cue) {
        switch cue {
        case .failure:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .incorrect:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .success, .correct, .lessonComplete, .streak, .milestone:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .recordingStart:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.55)
        case .recordingStop:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.50)
        case .info, .saved, .sent, .received:
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.42)
        }
    }

    private static func wavData(for tones: [Tone]) -> Data {
        let sampleRate: UInt32 = 44_100
        let twoPi = Double.pi * 2
        var pcm = Data()

        for tone in tones {
            let frameCount = max(1, Int(tone.duration * Double(sampleRate)))
            for frame in 0..<frameCount {
                let time = Double(frame) / Double(sampleRate)
                let remaining = tone.duration - time
                let attack = min(1, time / 0.008)
                let release = min(1, max(0, remaining) / 0.032)
                let envelope = max(0, min(attack, release))

                let fundamental = sin(twoPi * tone.frequency * time)
                let harmonic = 0.16 * sin(twoPi * tone.frequency * 2.01 * time + 0.15)
                let warmth = 0.05 * sin(twoPi * tone.frequency * 0.5 * time)
                let value = max(-1, min(1, ((fundamental + harmonic + warmth) / 1.21) * tone.volume * envelope))
                var sample = Int16(value * Double(Int16.max)).littleEndian
                withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
            }

            let gapFrames = max(0, Int(tone.gap * Double(sampleRate)))
            if gapFrames > 0 {
                pcm.append(Data(count: gapFrames * MemoryLayout<Int16>.size))
            }
        }

        let dataSize = UInt32(pcm.count)
        var wave = Data()
        appendASCII("RIFF", to: &wave)
        appendLittleEndian(UInt32(36) + dataSize, to: &wave)
        appendASCII("WAVE", to: &wave)
        appendASCII("fmt ", to: &wave)
        appendLittleEndian(UInt32(16), to: &wave)
        appendLittleEndian(UInt16(1), to: &wave) // PCM
        appendLittleEndian(UInt16(1), to: &wave) // mono
        appendLittleEndian(sampleRate, to: &wave)
        appendLittleEndian(sampleRate * 2, to: &wave)
        appendLittleEndian(UInt16(2), to: &wave)
        appendLittleEndian(UInt16(16), to: &wave)
        appendASCII("data", to: &wave)
        appendLittleEndian(dataSize, to: &wave)
        wave.append(pcm)
        return wave
    }

    private static func appendASCII(_ value: String, to data: inout Data) {
        if let bytes = value.data(using: .ascii) { data.append(bytes) }
    }

    private static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}
