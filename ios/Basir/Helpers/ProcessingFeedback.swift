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

    /// A ~4s seamless loop: a soft A3+E4 (perfect fifth) pad whose
    /// amplitude follows a half-sine window — silent at both ends, so
    /// the loop joins without a click, and "breathing" in the middle.
    private static func makeBuffer() -> AVAudioPCMBuffer? {
        let sampleRate = 44_100.0
        let duration = 4.0
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                       channels: 1),
            let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                          frameCapacity: frames)
        else { return nil }
        buffer.frameLength = frames

        guard let channel = buffer.floatChannelData?[0] else { return nil }
        let f1 = 220.0   // A3
        let f2 = 330.0   // E4 (perfect fifth)
        let peak: Float = 0.12
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            // Half-sine window: 0 → 1 → 0 across the whole buffer.
            let window = sin(Double.pi * t / duration)
            let s1 = sin(2 * Double.pi * f1 * t)
            let s2 = sin(2 * Double.pi * f2 * t) * 0.6
            channel[i] = Float((s1 + s2) * window) * peak
        }
        return buffer
    }
}
