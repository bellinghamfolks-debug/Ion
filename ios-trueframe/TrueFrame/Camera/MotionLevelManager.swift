import Foundation
import CoreMotion
import Combine

/// Orientation-independent leveling from CoreMotion.
/// The old implementation treated landscape as roughly a 90-degree tilt.
/// Here the projected gravity angle is measured relative to the nearest cardinal
/// device orientation, so portrait and both landscape orientations can all read
/// as level when their horizon is straight.
public final class MotionLevelManager: ObservableObject {

    @Published public private(set) var reading = LevelReading(rollDegrees: 0, pitchDegrees: 0)
    @Published public private(set) var motionMagnitude: Double = 0

    private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private let stateLock = NSLock()

    private var latestReading = LevelReading(rollDegrees: 0, pitchDegrees: 0)
    private var latestMotionMagnitude: Double = 0
    private var hasSmoothedReading = false

    public init() {
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
    }

    public var isAvailable: Bool { manager.isDeviceMotionAvailable }

    public func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }

        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }

            let gravity = motion.gravity
            let rawScreenAngle = atan2(gravity.x, -gravity.y) * 180 / .pi
            let cardinalRelativeRoll = LevelMath.cardinalRelativeRoll(
                rawScreenAngleDegrees: rawScreenAngle
            )

            let pitch = atan2(
                gravity.z,
                (gravity.x * gravity.x + gravity.y * gravity.y).squareRoot()
            ) * 180 / .pi

            let rotation = motion.rotationRate
            let instantaneousMotion = (
                rotation.x * rotation.x
                + rotation.y * rotation.y
                + rotation.z * rotation.z
            ).squareRoot()

            self.stateLock.lock()
            let smoothedRoll: Double
            let smoothedPitch: Double
            if self.hasSmoothedReading {
                smoothedRoll = self.latestReading.rollDegrees * 0.72 + cardinalRelativeRoll * 0.28
                smoothedPitch = self.latestReading.pitchDegrees * 0.78 + pitch * 0.22
                self.latestMotionMagnitude = self.latestMotionMagnitude * 0.72 + instantaneousMotion * 0.28
            } else {
                smoothedRoll = cardinalRelativeRoll
                smoothedPitch = pitch
                self.latestMotionMagnitude = instantaneousMotion
                self.hasSmoothedReading = true
            }

            let newReading = LevelReading(rollDegrees: smoothedRoll,
                                          pitchDegrees: smoothedPitch)
            self.latestReading = newReading
            let newMotionMagnitude = self.latestMotionMagnitude
            self.stateLock.unlock()

            DispatchQueue.main.async {
                self.reading = newReading
                self.motionMagnitude = newMotionMagnitude
            }
        }
    }

    public func stop() {
        manager.stopDeviceMotionUpdates()
        stateLock.lock()
        hasSmoothedReading = false
        latestReading = LevelReading(rollDegrees: 0, pitchDegrees: 0)
        latestMotionMagnitude = 0
        stateLock.unlock()
    }

    /// Thread-safe snapshot for the video-analysis queue.
    public func snapshot() -> (reading: LevelReading, isShaking: Bool) {
        stateLock.lock()
        let currentReading = latestReading
        let shaking = latestMotionMagnitude > 0.38
        stateLock.unlock()
        return (currentReading, shaking)
    }

    public var isShaking: Bool {
        snapshot().isShaking
    }

}
