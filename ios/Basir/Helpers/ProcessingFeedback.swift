// ProcessingFeedback.swift
// Short audible + haptic cues so AI tasks aren't silent: a soft tone when
// work starts and a different one when the result is ready or fails.

import UIKit
import AudioToolbox

enum ProcessingFeedback {
    @MainActor static func start() {
        AudioServicesPlaySystemSound(1113) // soft "begin" tone
        if BasirSettings.shared.vibrationEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    @MainActor static func done() {
        AudioServicesPlaySystemSound(1114) // soft "end" tone
        if BasirSettings.shared.vibrationEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    @MainActor static func failed() {
        if BasirSettings.shared.vibrationEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
