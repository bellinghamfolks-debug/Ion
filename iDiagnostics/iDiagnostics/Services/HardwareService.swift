import Foundation
import UIKit
import CoreHaptics
import AVFoundation
import LocalAuthentication
import Combine

/// Backs the haptics, volume-button and biometrics diagnostics.
///
/// - Haptics: uses `CHHapticEngine` when the hardware supports it, otherwise
///   falls back to `UIKit` feedback generators.
/// - Volume buttons: iOS exposes no key-press event, so presses are inferred by
///   observing `AVAudioSession.outputVolume` via KVO.
/// - Biometrics: reports the enrolled `LABiometryType` and can authenticate.
@MainActor
final class HardwareService: NSObject, ObservableObject {

    enum VolumeDirection: String {
        case up, down
    }

    // MARK: - Published state

    /// Direction of the most recently detected volume change.
    @Published private(set) var lastVolumeDirection: VolumeDirection?
    @Published private(set) var volumeUpCount: Int = 0
    @Published private(set) var volumeDownCount: Int = 0
    /// The device's enrolled biometry type (or `.none` when unavailable).
    @Published private(set) var biometryType: LABiometryType = .none
    /// True when biometrics can actually be evaluated on this device.
    @Published private(set) var biometricsAvailable: Bool = false

    var supportsHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    var volumeUpDetected: Bool { volumeUpCount > 0 }
    var volumeDownDetected: Bool { volumeDownCount > 0 }

    // MARK: - Private

    private var hapticEngine: CHHapticEngine?
    private let audioSession = AVAudioSession.sharedInstance()
    private var isObservingVolume = false
    private var lastVolume: Float = 0

    override init() {
        super.init()
        refreshBiometry()
    }

    // MARK: - Haptics

    /// Prepare the Core Haptics engine if supported. Safe to call repeatedly.
    func prepareHaptics() {
        guard supportsHaptics, hapticEngine == nil else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            try engine.start()
            hapticEngine = engine
        } catch {
            hapticEngine = nil
        }
    }

    func playLight()   { impact(.light) }
    func playMedium()  { impact(.medium) }
    func playHeavy()   { impact(.heavy) }

    func playSuccess() {
        if supportsHaptics, playCoreHaptic(intensity: 1.0, sharpness: 0.7, doublePulse: true) {
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let intensity: Float
        let sharpness: Float
        switch style {
        case .light:  intensity = 0.4; sharpness = 0.3
        case .medium: intensity = 0.7; sharpness = 0.5
        case .heavy:  intensity = 1.0; sharpness = 0.7
        default:      intensity = 0.7; sharpness = 0.5
        }
        if supportsHaptics, playCoreHaptic(intensity: intensity, sharpness: sharpness) {
            return
        }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Returns true on success so callers can fall back to UIKit on failure.
    private func playCoreHaptic(intensity: Float, sharpness: Float, doublePulse: Bool = false) -> Bool {
        prepareHaptics()
        guard let engine = hapticEngine else { return false }
        let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
        let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
        var events: [CHHapticEvent] = [
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [intensityParam, sharpnessParam],
                          relativeTime: 0)
        ]
        if doublePulse {
            events.append(CHHapticEvent(eventType: .hapticTransient,
                                        parameters: [intensityParam, sharpnessParam],
                                        relativeTime: 0.12))
        }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try engine.start()
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Volume buttons

    func startVolumeMonitoring() {
        guard !isObservingVolume else { return }
        do {
            try audioSession.setActive(true)
        } catch {
            // Even if activation fails we still attempt KVO; readings may lag.
        }
        lastVolume = audioSession.outputVolume
        audioSession.addObserver(self,
                                 forKeyPath: "outputVolume",
                                 options: [.new],
                                 context: nil)
        isObservingVolume = true
    }

    func stopVolumeMonitoring() {
        guard isObservingVolume else { return }
        audioSession.removeObserver(self, forKeyPath: "outputVolume")
        isObservingVolume = false
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    func resetVolumeDetection() {
        lastVolumeDirection = nil
        volumeUpCount = 0
        volumeDownCount = 0
    }

    // KVO callback. Not isolated to the main actor, so hop back before mutating.
    nonisolated override func observeValue(forKeyPath keyPath: String?,
                                           of object: Any?,
                                           change: [NSKeyValueChangeKey: Any]?,
                                           context: UnsafeMutableRawPointer?) {
        guard keyPath == "outputVolume",
              let newVolume = change?[.newKey] as? Float else { return }
        Task { @MainActor in
            self.handleVolumeChange(newVolume)
        }
    }

    private func handleVolumeChange(_ newVolume: Float) {
        let delta = newVolume - lastVolume
        lastVolume = newVolume
        guard abs(delta) > 0.001 else { return }
        if delta > 0 {
            lastVolumeDirection = .up
            volumeUpCount += 1
        } else {
            lastVolumeDirection = .down
            volumeDownCount += 1
        }
    }

    // MARK: - Biometrics

    func refreshBiometry() {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                    error: &error)
        biometricsAvailable = canEvaluate
        biometryType = context.biometryType
    }

    var biometryTypeAr: String {
        switch biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        case .none:    return "لا يوجد"
        @unknown default: return "غير معروف"
        }
    }

    func authenticate() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                    localizedReason: "التحقق من عمل المصادقة البيومترية")
        } catch {
            return false
        }
    }
}
