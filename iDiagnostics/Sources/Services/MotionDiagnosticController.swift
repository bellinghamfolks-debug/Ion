import Combine
import CoreMotion
import Foundation
import UIKit

final class MotionDiagnosticController: ObservableObject {
    @Published private(set) var motionAvailable = false
    @Published private(set) var sampleCount = 0
    @Published private(set) var accelerationMagnitude = 0.0
    @Published private(set) var rotationMagnitude = 0.0
    @Published private(set) var peakAcceleration = 0.0
    @Published private(set) var peakRotation = 0.0
    @Published private(set) var proximitySupported = false
    @Published private(set) var isNear = false
    @Published private(set) var proximityChanged = false
    @Published private(set) var errorMessage: String?

    private let manager = CMMotionManager()
    private var proximityObserver: NSObjectProtocol?
    private var initialProximity: Bool?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        errorMessage = nil
        sampleCount = 0
        peakAcceleration = 0
        peakRotation = 0

        motionAvailable = manager.isDeviceMotionAvailable
        if manager.isDeviceMotionAvailable {
            manager.deviceMotionUpdateInterval = 0.1
            manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
                guard let self else { return }
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let motion else { return }
                let acceleration = Self.magnitude(
                    motion.userAcceleration.x,
                    motion.userAcceleration.y,
                    motion.userAcceleration.z
                )
                let rotation = Self.magnitude(
                    motion.rotationRate.x,
                    motion.rotationRate.y,
                    motion.rotationRate.z
                )
                self.accelerationMagnitude = acceleration
                self.rotationMagnitude = rotation
                self.peakAcceleration = max(self.peakAcceleration, acceleration)
                self.peakRotation = max(self.peakRotation, rotation)
                self.sampleCount += 1
            }
        }

        UIDevice.current.isProximityMonitoringEnabled = true
        proximitySupported = UIDevice.current.isProximityMonitoringEnabled
        isNear = UIDevice.current.proximityState
        initialProximity = isNear
        proximityObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.proximityStateDidChangeNotification,
            object: UIDevice.current,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isNear = UIDevice.current.proximityState
            if let initialProximity = self.initialProximity, initialProximity != self.isNear {
                self.proximityChanged = true
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        if let proximityObserver {
            NotificationCenter.default.removeObserver(proximityObserver)
        }
        proximityObserver = nil
        UIDevice.current.isProximityMonitoringEnabled = false
        started = false
    }

    var receivedUsefulMotion: Bool {
        sampleCount >= 5 && (peakAcceleration > 0.01 || peakRotation > 0.01)
    }

    var metrics: [DiagnosticMetric] {
        [
            .init(label: "عينات الحركة", value: "\(sampleCount)"),
            .init(label: "أقصى تسارع", value: String(format: "%.3f g", peakAcceleration)),
            .init(label: "أقصى دوران", value: String(format: "%.3f rad/s", peakRotation)),
            .init(label: "مستشعر التقارب", value: proximitySupported ? (proximityChanged ? "استجاب" : "لم يتغير بعد") : "غير متاح"),
            .init(label: "مستشعر الإضاءة", value: "لا تتيحه واجهات iOS العامة")
        ]
    }

    private static func magnitude(_ x: Double, _ y: Double, _ z: Double) -> Double {
        sqrt(x * x + y * y + z * z)
    }
}
