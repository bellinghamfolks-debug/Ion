import Foundation
import CoreMotion
import Combine

/// Publishes a live `LevelReading` (roll + pitch, in degrees) from device
/// motion. Roll is the horizon tilt; pitch is pointing up/down. Motion feedback
/// is effectively instantaneous, so this drives the fastest guidance channel.
public final class MotionLevelManager: ObservableObject {

    @Published public private(set) var reading = LevelReading(rollDegrees: 0, pitchDegrees: 0)
    @Published public private(set) var motionMagnitude: Double = 0   // rad/s, for shake detection

    private let manager = CMMotionManager()
    private let queue = OperationQueue()

    public init() {
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
    }

    public var isAvailable: Bool { manager.isDeviceMotionAvailable }

    public func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            let g = m.gravity
            // Roll: rotation about the camera's viewing axis. 0 when upright.
            let roll = atan2(g.x, -g.y) * 180 / .pi
            // Pitch: how far from vertical the phone is tilted (up/down aim).
            let pitch = atan2(g.z, (g.x * g.x + g.y * g.y).squareRoot()) * 180 / .pi
            let rot = m.rotationRate
            let mag = (rot.x * rot.x + rot.y * rot.y + rot.z * rot.z).squareRoot()
            DispatchQueue.main.async {
                self.reading = LevelReading(rollDegrees: roll, pitchDegrees: pitch)
                self.motionMagnitude = mag
            }
        }
    }

    public func stop() { manager.stopDeviceMotionUpdates() }

    /// True when the device is moving enough that a capture would likely be
    /// shake-blurred.
    public var isShaking: Bool { motionMagnitude > 0.35 }
}
