import Foundation
import CoreMotion
import UIKit
import Combine

/// Live sensor readings for the `.sensors` diagnostic. Wraps `CMMotionManager`
/// for accelerometer + gyroscope and `UIDevice` proximity monitoring.
///
/// Ambient-light (lux) is intentionally **not** provided: iOS exposes no public
/// API for it, so the view reports that sub-test as `.unsupported` rather than
/// fabricating a value.
@MainActor
final class SensorService: ObservableObject {
    /// Live accelerometer reading in g (x, y, z).
    @Published private(set) var acceleration: (x: Double, y: Double, z: Double) = (0, 0, 0)
    /// Live gyroscope rotation rate in rad/s (x, y, z).
    @Published private(set) var rotation: (x: Double, y: Double, z: Double) = (0, 0, 0)
    /// Whether an object is currently near the proximity sensor (top of screen).
    @Published private(set) var isNear: Bool = false
    /// True once we have received at least one motion sample.
    @Published private(set) var didReceiveMotion: Bool = false

    var isAccelerometerAvailable: Bool { motion.isAccelerometerAvailable }
    var isGyroAvailable: Bool { motion.isGyroAvailable }

    private let motion = CMMotionManager()
    private var proximityObserver: NSObjectProtocol?

    // MARK: - Lifecycle

    func start() {
        startMotion()
        startProximity()
    }

    func stop() {
        if motion.isAccelerometerActive { motion.stopAccelerometerUpdates() }
        if motion.isGyroActive { motion.stopGyroUpdates() }

        if let observer = proximityObserver {
            NotificationCenter.default.removeObserver(observer)
            proximityObserver = nil
        }
        UIDevice.current.isProximityMonitoringEnabled = false
    }

    // MARK: - Motion

    private func startMotion() {
        if motion.isAccelerometerAvailable {
            motion.accelerometerUpdateInterval = 1.0 / 30.0
            motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let self, let a = data?.acceleration else { return }
                self.acceleration = (a.x, a.y, a.z)
                self.didReceiveMotion = true
            }
        }

        if motion.isGyroAvailable {
            motion.gyroUpdateInterval = 1.0 / 30.0
            motion.startGyroUpdates(to: .main) { [weak self] data, _ in
                guard let self, let r = data?.rotationRate else { return }
                self.rotation = (r.x, r.y, r.z)
                self.didReceiveMotion = true
            }
        }
    }

    // MARK: - Proximity

    private func startProximity() {
        let device = UIDevice.current
        device.isProximityMonitoringEnabled = true

        // Only observe if the hardware actually supports monitoring.
        guard device.isProximityMonitoringEnabled else { return }

        proximityObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.proximityStateDidChangeNotification,
            object: device,
            queue: .main
        ) { [weak self] _ in
            self?.isNear = UIDevice.current.proximityState
        }
    }
}
