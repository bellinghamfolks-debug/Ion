// ProcessingFeedback.swift
// Short audible + haptic cues so AI tasks aren't silent: a soft tone when
// work starts and a different one when the result is ready or fails.
//
// The tone is played through a brief .playback audio session (mixing with
// others) so it's audible even when the ring/silent switch is off — which
// matters for a blind-accessibility app where silence is ambiguous.

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
    }

    @MainActor static func done() {
        activateAudible()
        AudioServicesPlaySystemSound(1114) // soft "end" tone
        if BasirSettings.shared.vibrationEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    @MainActor static func failed() {
        AudioServicesPlaySystemSound(1073) // short error tone
        if BasirSettings.shared.vibrationEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
