import Foundation

/// Stateful gate for automatic capture.
///
/// A single "good" frame is never enough. The scene must remain technically
/// ready for a continuous time window. After a capture, the gate stays disarmed
/// until the scene becomes not-ready for a short period, which prevents bursts
/// caused by frame-to-frame jitter.
public struct AutoCaptureGate: Sendable {
    public var minimumStableDuration: TimeInterval = 0.8
    public var minimumRearmDuration: TimeInterval = 0.6
    public var minimumCaptureInterval: TimeInterval = 2.5

    private var stableSince: TimeInterval?
    private var readySampleCount = 0
    private var notReadySince: TimeInterval?
    private var lastCaptureAt: TimeInterval = -.infinity
    private var armed = true

    public init() {}

    public mutating func reset() {
        stableSince = nil
        readySampleCount = 0
        notReadySince = nil
        lastCaptureAt = -.infinity
        armed = true
    }

    /// Returns true exactly once when a stable, technically ready scene has
    /// remained ready long enough and the camera itself can accept a capture.
    public mutating func shouldCapture(_ analysis: FrameAnalysis,
                                       now: TimeInterval,
                                       cameraReady: Bool) -> Bool {
        let ready = cameraReady && Self.isTechnicallyReady(analysis)

        guard ready else {
            stableSince = nil
            readySampleCount = 0

            if notReadySince == nil {
                notReadySince = now
            }
            if !armed,
               let since = notReadySince,
               now - since >= minimumRearmDuration {
                armed = true
            }
            return false
        }

        notReadySince = nil
        guard armed else { return false }
        guard now - lastCaptureAt >= minimumCaptureInterval else { return false }

        if stableSince == nil {
            stableSince = now
            readySampleCount = 1
            return false
        }

        readySampleCount += 1
        guard readySampleCount >= 5,
              let since = stableSince,
              now - since >= minimumStableDuration else {
            return false
        }

        armed = false
        stableSince = nil
        readySampleCount = 0
        lastCaptureAt = now
        return true
    }

    /// Technical readiness only. This intentionally does not judge artistic
    /// taste. It blocks captures that are tilted, moving, blurred, badly
    /// exposed, obstructed, or obviously clipping the detected subject.
    public static func isTechnicallyReady(_ a: FrameAnalysis) -> Bool {
        guard abs(a.level.rollDegrees) <= LevelThresholds.autoCapture else { return false }
        if let horizon = a.visualHorizonDegrees,
           a.visualHorizonConfidence >= 0.65,
           abs(horizon) > 2.5 {
            return false
        }
        guard !a.motionHigh else { return false }
        guard a.sharpness == .sharp else { return false }
        guard a.exposure != .veryDark, a.exposure != .overexposed else { return false }
        guard !a.obstruction.isObstructed else { return false }
        guard !a.framing.hasClipping else { return false }
        guard a.skyFraction < 0.92, a.groundFraction < 0.92 else { return false }

        if let offset = a.framing.horizontalOffset, abs(offset) > 0.55 {
            return false
        }
        return true
    }
}
