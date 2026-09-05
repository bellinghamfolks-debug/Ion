import AVFoundation
import Combine
import CoreHaptics
import Foundation
import LocalAuthentication
import UIKit

final class HapticDiagnosticController: ObservableObject {
    @Published private(set) var supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    @Published private(set) var errorMessage: String?

    private var engine: CHHapticEngine?

    func prepare() {
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        guard supportsHaptics, engine == nil else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            engine.stoppedHandler = { [weak self] _ in
                DispatchQueue.main.async { self?.engine = nil }
            }
            engine.resetHandler = { [weak self] in
                DispatchQueue.main.async { self?.prepare() }
            }
            try engine.start()
            self.engine = engine
        } catch {
            engine = nil
            errorMessage = "تعذر إعداد محرّك الاهتزاز: \(error.localizedDescription)"
        }
    }

    func play(intensity: Float, sharpness: Float, doublePulse: Bool = false) {
        errorMessage = nil
        guard supportsHaptics else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return
        }
        prepare()
        guard let engine else {
            errorMessage = "محرّك الاهتزاز غير جاهز. أعد المحاولة."
            return
        }
        do {
            let intensityParameter = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
            let sharpnessParameter = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            var events = [CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [intensityParameter, sharpnessParameter],
                relativeTime: 0
            )]
            if doublePulse {
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [intensityParameter, sharpnessParameter],
                    relativeTime: 0.16
                ))
            }
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            self.engine = nil
            errorMessage = "تعذر تشغيل الاهتزاز: \(error.localizedDescription)"
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    func stop() {
        engine?.stop(completionHandler: nil)
        engine = nil
    }
}

final class VolumeButtonMonitor: ObservableObject {
    enum Direction: String {
        case up
        case down

        var titleAr: String { self == .up ? "رفع الصوت" : "خفض الصوت" }
    }

    @Published private(set) var upCount = 0
    @Published private(set) var downCount = 0
    @Published private(set) var lastDirection: Direction?
    @Published private(set) var errorMessage: String?

    private let audioSession = AVAudioSession.sharedInstance()
    private var observation: NSKeyValueObservation?
    private var lastVolume: Float = 0

    func start() {
        guard observation == nil else { return }
        do {
            try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
            lastVolume = audioSession.outputVolume
            observation = audioSession.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
                guard let self, let newValue = change.newValue else { return }
                DispatchQueue.main.async {
                    guard abs(newValue - self.lastVolume) > 0.001 else { return }
                    if newValue > self.lastVolume {
                        self.upCount += 1
                        self.lastDirection = .up
                    } else {
                        self.downCount += 1
                        self.lastDirection = .down
                    }
                    self.lastVolume = newValue
                    AccessibilityAnnouncer.post("تم رصد زر \(self.lastDirection?.titleAr ?? "الصوت")")
                }
            }
        } catch {
            errorMessage = "تعذر مراقبة تغيّر الصوت: \(error.localizedDescription)"
        }
    }

    func resetCounts() {
        upCount = 0
        downCount = 0
        lastDirection = nil
    }

    func stop() {
        observation?.invalidate()
        observation = nil
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    var bothDetected: Bool { upCount > 0 && downCount > 0 }
}

final class BiometricDiagnosticService: ObservableObject {
    @Published private(set) var typeTitle = "غير متاح"
    @Published private(set) var isAvailable = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var errorMessage: String?

    func refresh() {
        let context = LAContext()
        var error: NSError?
        isAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        if #available(iOS 17.0, *), context.biometryType == .opticID {
            typeTitle = "Optic ID"
        } else {
            switch context.biometryType {
            case .faceID: typeTitle = "Face ID"
            case .touchID: typeTitle = "Touch ID"
            case .none: typeTitle = "غير متاح"
            default: typeTitle = "نوع غير معروف"
            }
        }
        errorMessage = isAvailable ? nil : biometricErrorTitle(error)
    }

    func authenticate(completion: @escaping (Bool, String?) -> Void) {
        let context = LAContext()
        var capabilityError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &capabilityError) else {
            let message = biometricErrorTitle(capabilityError) ?? "المصادقة البيومترية غير متاحة."
            errorMessage = message
            completion(false, message)
            return
        }

        isAuthenticating = true
        errorMessage = nil
        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "التحقق من استجابة المصادقة البيومترية"
        ) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isAuthenticating = false
                let message = success ? nil : self.biometricErrorTitle(error as NSError?)
                self.errorMessage = message
                completion(success, message)
            }
        }
    }

    private func biometricErrorTitle(_ error: NSError?) -> String? {
        guard let error else { return nil }
        guard error.domain == LAError.errorDomain, let code = LAError.Code(rawValue: error.code) else {
            return error.localizedDescription
        }
        switch code {
        case .biometryNotAvailable: return "لا يدعم الجهاز مصادقة بيومترية متاحة."
        case .biometryNotEnrolled: return "لم تُسجّل بصمة أو وجه على الجهاز."
        case .biometryLockout: return "المصادقة مقفلة مؤقتًا؛ افتح الجهاز برمز الدخول أولًا."
        case .userCancel, .systemCancel, .appCancel: return "أُلغي الاختبار قبل اكتماله."
        case .authenticationFailed: return "لم تتطابق المصادقة. يمكنك إعادة المحاولة."
        default: return error.localizedDescription
        }
    }
}
