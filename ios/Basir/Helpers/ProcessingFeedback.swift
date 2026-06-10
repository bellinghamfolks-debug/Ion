// ProcessingFeedback.swift
// Audible + haptic cues so AI tasks aren't silent.
//
// Two layers:
//   1. Short one-shot tones at the start / end / failure of a task.
//   2. A SUSTAINED, soft "breathing" pad that loops the whole time a
//      task is in flight — so during a long document conversion the
//      user keeps hearing that work is still happening, instead of
//      wondering whether the app froze. The pad is synthesized on the
//      fly (no bundled audio asset) as a gentle perfect-fifth chord
//      whose amplitude swells from silence to a low peak and back,
//      which also makes the loop seamless.
//
// Everything plays through a .playback session (mixing with others) so
// it's audible even when the ring/silent switch is off — which matters
// for a blind-accessibility app where silence is ambiguous.

import UIKit
import AVFoundation
import AudioToolbox

enum ProcessingFeedback {

    private static func activateAudible() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers, .duckOthers])
        try? session.setActive(true, options: [])
    }

    @MainActor static func start() {
        activateAudible()
        AudioServicesPlaySystemSound(1113) // soft "begin" tone
        if BasirSettings.shared.vibrationEnabled {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        WaitingTone.shared.start()
    }

    @MainActor static func done() {
        WaitingTone.shared.stop()
        activateAudible()
        AudioServicesPlaySystemSound(1114) // soft "end" tone
        if BasirSettings.shared.vibrationEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    @MainActor static func failed() {
        WaitingTone.shared.stop()
        AudioServicesPlaySystemSound(1073) // short error tone
        if BasirSettings.shared.vibrationEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

/// Synthesizes and loops a soft ambient pad while a task runs.
/// Reference-counted so overlapping tasks (e.g. an OCR pass feeding a
/// conversion) don't cut each other's audio off early — the pad stops
/// only when the last in-flight task finishes.
@MainActor
final class WaitingTone {
    static let shared = WaitingTone()
    private init() {}

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?
    private var active = 0

    func start() {
        active += 1
        guard active == 1 else { return }   // already playing
        do {
            if buffer == nil { buffer = Self.makeBuffer() }
            guard let buffer else { return }

            if engine.attachedNodes.contains(player) == false {
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode,
                               format: buffer.format)
            }
            engine.mainMixerNode.outputVolume = 0.5
            if engine.isRunning == false { try engine.start() }
            player.scheduleBuffer(buffer, at: nil, options: [.loops])
            player.play()
        } catch {
            active = 0   // engine couldn't start; don't get stuck "active"
        }
    }

    func stop() {
        guard active > 0 else { return }
        active -= 1
        guard active == 0 else { return }   // another task still running
        player.stop()
        engine.stop()
    }

    /// A calm, looping chime motif — NOT a sustained drone (the previous
    /// continuous tone read like an air-conditioner hum). We synthesize a
    /// short pentatonic phrase of soft, bell-like notes, each with a quick
    /// attack and a gentle exponential decay, followed by a restful tail
    /// of near-silence before the phrase repeats. Pentatonic notes never
    /// clash, so any loop point sounds pleasant, and because every note
    /// has decayed to silence well before the buffer ends the loop joins
    /// without a click.
    private static func makeBuffer() -> AVAudioPCMBuffer? {
        let sampleRate = 44_100.0
        let duration = 6.0
        let frameCount = Int(sampleRate * duration)
        guard
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                       channels: 1),
            let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                          frameCapacity: AVAudioFrameCount(frameCount))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        for i in 0..<frameCount { channel[i] = 0 }

        // A gentle four-note phrase (E5–G5–B5–G5: a soothing major-ish
        // pentatonic shape), spaced ~0.5s apart, then ~4s of quiet.
        let notes: [(freq: Double, start: Double)] = [
            (659.25, 0.00),   // E5
            (783.99, 0.50),   // G5
            (987.77, 1.00),   // B5
            (783.99, 1.50),   // G5
        ]
        let decay = 4.5          // per-second amplitude falloff (bell-like)
        let ring  = 1.4          // seconds a note keeps sounding
        let attack = 0.008       // short fade-in to avoid a click on onset
        let peak: Float = 0.16
        for note in notes {
            let startSample = Int(note.start * sampleRate)
            let endSample = min(frameCount, startSample + Int(ring * sampleRate))
            guard startSample < endSample else { continue }
            for n in startSample..<endSample {
                let t = Double(n - startSample) / sampleRate
                let env = exp(-decay * t) * min(1.0, t / attack)
                let fundamental = sin(2 * Double.pi * note.freq * t)
                let octave = sin(2 * Double.pi * note.freq * 2 * t) * 0.25
                channel[n] += Float((fundamental + octave) * env) * peak
            }
        }
        return buffer
    }
}
