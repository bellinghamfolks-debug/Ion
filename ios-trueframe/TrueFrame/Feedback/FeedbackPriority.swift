import Foundation

/// Priority buckets, highest first. The guidance loop only ever speaks ONE thing
/// at a time — the most important unresolved problem — so a blind user is guided
/// progressively rather than flooded.
public enum GuidancePriority: Int, Comparable, Sendable {
    case safety = 0        // safety-critical (e.g. lens fully blocked -> can't shoot)
    case majorFraming      // subject mostly outside / pointed at sky or ground
    case severeTilt        // large roll
    case subjectClipped    // head/feet/edges cut off
    case blur              // motion / focus
    case exposure          // too dark / blown out
    case composition       // optional suggestions
    case status            // "level", "ready" — reassurance only

    public static func < (a: GuidancePriority, b: GuidancePriority) -> Bool { a.rawValue < b.rawValue }
}

public enum Verbosity: Int, Sendable { case minimal, normal, detailed }

/// One spoken instruction. `key` identifies the CONDITION (so we don't repeat
/// it), `level` is a coarse severity bucket (so we DO re-announce when severity
/// meaningfully changes).
public struct GuidanceMessage: Equatable, Sendable {
    public var priority: GuidancePriority
    public var text: String
    public var key: String
    public var level: Int
    public init(_ priority: GuidancePriority, _ text: String, key: String, level: Int = 0) {
        self.priority = priority; self.text = text; self.key = key; self.level = level
    }
}

/// Turns a `FrameAnalysis` into the single most important instruction. Pure and
/// deterministic — unit-tested without any camera.
public enum GuidanceRules {

    public static func topMessage(_ a: FrameAnalysis, verbosity: Verbosity = .normal) -> GuidanceMessage {
        // 1. Safety-critical: lens appears fully blocked -> no photo possible.
        if a.obstruction.isObstructed && a.obstruction.confidence >= 0.85 {
            return GuidanceMessage(.safety,
                "Camera appears covered at the \(a.obstruction.region.spoken). Move your finger.",
                key: "obstruction", level: 2)
        }
        // 2. Major framing: pointed mostly at sky or ground.
        if a.skyFraction >= 0.8 {
            return GuidanceMessage(.majorFraming, "Mostly sky. Lower the camera.", key: "mostlySky")
        }
        if a.groundFraction >= 0.8 {
            return GuidanceMessage(.majorFraming, "Mostly ground. Raise the camera.", key: "mostlyGround")
        }
        // 3. Severe tilt.
        let roll = a.level.rollDegrees
        if abs(roll) >= 8 {
            let dir = roll > 0 ? "left" : "right"   // rotate the top toward level
            let bucket = Int((abs(roll) / 5).rounded(.down))
            let text = verbosity == .minimal
                ? "Rotate \(dir)."
                : "\(Int(abs(roll).rounded())) degrees tilted \(roll > 0 ? "clockwise" : "counter-clockwise"). Rotate \(dir)."
            return GuidanceMessage(.severeTilt, text, key: "tilt", level: bucket)
        }
        // 4. Subject clipped.
        let f = a.framing
        if f.clippedTop && f.personCount >= 1 {
            return GuidanceMessage(.subjectClipped, "Head is close to the top. Lower the camera.", key: "clipTop")
        }
        if f.clippedBottom && f.personCount >= 1 {
            return GuidanceMessage(.subjectClipped, "Feet are cut off. Raise the camera or step back if safe.", key: "clipBottom")
        }
        if let off = f.horizontalOffset, abs(off) > 0.45 {
            let side = off > 0 ? "right" : "left"
            return GuidanceMessage(.subjectClipped, "Subject near the \(side) edge. Move the camera \(side == "right" ? "right" : "left").", key: "subjectEdge", level: off > 0 ? 1 : 0)
        }
        // 5. Blur / motion.
        if a.motionHigh {
            return GuidanceMessage(.blur, "Hold steady.", key: "motion")
        }
        if a.sharpness == .blurry || a.sharpness == .severelyBlurry {
            return GuidanceMessage(.blur, "Image may be blurry.", key: "blur")
        }
        // 6. Exposure.
        switch a.exposure {
        case .veryDark: return GuidanceMessage(.exposure, "Scene is very dark.", key: "exposure", level: 2)
        case .overexposed: return GuidanceMessage(.exposure, "Bright areas are overexposed.", key: "exposure", level: 1)
        default: break
        }
        // 7. Near-level nudge (gentle) when not yet within tolerance.
        if !a.level.isLevel && a.level.isNearLevel {
            return GuidanceMessage(.severeTilt, verbosity == .minimal ? "Almost level." : "Almost level.", key: "tilt", level: 0)
        }
        if !a.level.isLevel {
            let dir = roll > 0 ? "left" : "right"
            return GuidanceMessage(.severeTilt, "Rotate slightly \(dir).", key: "tilt", level: 0)
        }
        // All clear.
        return GuidanceMessage(.status, "Level.", key: "ok")
    }
}

/// Emission gate: decides whether the planned message is actually spoken now,
/// implementing the "smart speech throttling" rules. Stateful but tiny and
/// deterministic (time is injected), so it is unit-tested.
public struct GuidanceThrottle {
    private var lastKey: String?
    private var lastLevel: Int = 0
    private var lastSpokenAt: TimeInterval = -.infinity
    private var lastKeyClearedAt: TimeInterval = 0
    public var minStatusInterval: TimeInterval = 6      // reassurance repeats slowly
    public var minRepeatInterval: TimeInterval = 1.2     // floor between any two utterances

    public init() {}

    /// Returns the message to speak, or nil to stay silent.
    public mutating func admit(_ msg: GuidanceMessage, now: TimeInterval) -> GuidanceMessage? {
        // Never talk over ourselves too quickly.
        if now - lastSpokenAt < minRepeatInterval { return nil }

        let sameCondition = (msg.key == lastKey)
        if sameCondition {
            // Same problem persisting: only re-announce if severity changed, or
            // (for status/reassurance) after a long interval.
            if msg.priority == .status {
                if now - lastSpokenAt < minStatusInterval { return nil }
            } else if msg.level == lastLevel {
                return nil
            }
        }
        lastKey = msg.key
        lastLevel = msg.level
        lastSpokenAt = now
        return msg
    }

    /// Call when the condition set changes so a re-appearing problem is spoken.
    public mutating func noteCleared(now: TimeInterval) { lastKeyClearedAt = now }
}
