import Foundation

public enum GuidancePriority: Int, Comparable, Sendable {
    case safety = 0
    case majorFraming
    case severeTilt
    case subjectClipped
    case blur
    case exposure
    case composition
    case status

    public static func < (lhs: GuidancePriority, rhs: GuidancePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum Verbosity: Int, Sendable { case minimal, normal, detailed }

public struct GuidanceMessage: Equatable, Sendable {
    public var priority: GuidancePriority
    public var text: String
    public var key: String
    public var level: Int

    public init(_ priority: GuidancePriority,
                _ text: String,
                key: String,
                level: Int = 0) {
        self.priority = priority
        self.text = text
        self.key = key
        self.level = level
    }
}

/// Chooses one instruction only: the highest-impact unresolved capture problem.
public enum GuidanceRules {

    public static func topMessage(_ analysis: FrameAnalysis,
                                  verbosity: Verbosity = .normal) -> GuidanceMessage {
        if analysis.obstruction.isObstructed,
           analysis.obstruction.confidence >= 0.78 {
            return GuidanceMessage(
                .safety,
                "Part of the camera may be covered. Move your finger away from the lens.",
                key: "obstruction",
                level: 2
            )
        }

        // These cues are deliberately conservative. The frame analyzer now
        // reports sky/ground only when those bands differ from the middle of the
        // scene, and the high threshold further reduces false positives.
        if analysis.skyFraction >= 0.92 {
            return GuidanceMessage(.majorFraming,
                                   "The frame is mostly sky. Lower the camera a little.",
                                   key: "mostlySky")
        }
        if analysis.groundFraction >= 0.92 {
            return GuidanceMessage(.majorFraming,
                                   "The frame is mostly ground. Raise the camera a little.",
                                   key: "mostlyGround")
        }

        let roll = analysis.level.rollDegrees
        if abs(roll) >= 8 {
            let direction = roll > 0 ? "left" : "right"
            let bucket = Int((abs(roll) / 5).rounded(.down))
            let text = verbosity == .minimal
                ? "Rotate \(direction)."
                : "Tilt is about \(Int(abs(roll).rounded())) degrees. Rotate \(direction)."
            return GuidanceMessage(.severeTilt, text, key: "tilt", level: bucket)
        }

        if let visualHorizon = analysis.visualHorizonDegrees,
           analysis.visualHorizonConfidence >= 0.65,
           abs(visualHorizon) > 3.0 {
            let bucket = Int((abs(visualHorizon) / 3).rounded(.down))
            return GuidanceMessage(.severeTilt,
                                   "The visible horizon still looks tilted. Adjust the phone rotation slightly.",
                                   key: "visualHorizon",
                                   level: bucket)
        }

        let framing = analysis.framing
        if framing.clippedTop && framing.personCount >= 1 {
            return GuidanceMessage(.subjectClipped,
                                   "The person's head is too close to the top edge. Lower the camera a little.",
                                   key: "clipTop")
        }
        if framing.clippedBottom && framing.personCount >= 1 {
            return GuidanceMessage(.subjectClipped,
                                   "The person's feet are cut off. Raise the camera or step back if it is safe.",
                                   key: "clipBottom")
        }

        if let offset = framing.horizontalOffset, abs(offset) > 0.45 {
            let side = offset > 0 ? "right" : "left"
            return GuidanceMessage(.subjectClipped,
                                   "The main subject is near the \(side) edge. Move the camera \(side).",
                                   key: "subjectEdge",
                                   level: offset > 0 ? 1 : 0)
        }

        if analysis.motionHigh {
            return GuidanceMessage(.blur, "Hold the phone steady.", key: "motion")
        }
        if analysis.sharpness == .blurry || analysis.sharpness == .severelyBlurry {
            return GuidanceMessage(.blur,
                                   "The image is not sharp yet. Hold steady and let the camera focus.",
                                   key: "blur",
                                   level: 2)
        }
        if analysis.sharpness == .slightlySoft {
            return GuidanceMessage(.blur,
                                   "Almost sharp. Hold steady for focus.",
                                   key: "blur",
                                   level: 1)
        }

        switch analysis.exposure {
        case .veryDark:
            return GuidanceMessage(.exposure,
                                   "The scene is very dark. Move toward more light if possible.",
                                   key: "exposure",
                                   level: 2)
        case .overexposed:
            return GuidanceMessage(.exposure,
                                   "Bright areas are losing detail. Aim away from the strongest light.",
                                   key: "exposure",
                                   level: 1)
        default:
            break
        }

        if !analysis.level.isLevel && analysis.level.isNearLevel {
            return GuidanceMessage(.severeTilt,
                                   "Almost straight.",
                                   key: "tilt",
                                   level: 0)
        }

        if !analysis.level.isLevel {
            let direction = roll > 0 ? "left" : "right"
            return GuidanceMessage(.severeTilt,
                                   "Rotate slightly \(direction).",
                                   key: "tilt",
                                   level: 0)
        }

        return GuidanceMessage(.status, "Ready.", key: "ok")
    }
}

public struct GuidanceThrottle {
    private var lastKey: String?
    private var lastLevel: Int = 0
    private var lastSpokenAt: TimeInterval = -.infinity
    public var minStatusInterval: TimeInterval = 6
    public var minRepeatInterval: TimeInterval = 1.2

    public init() {}

    public mutating func admit(_ message: GuidanceMessage,
                               now: TimeInterval) -> GuidanceMessage? {
        guard now - lastSpokenAt >= minRepeatInterval else { return nil }

        if message.key == lastKey {
            if message.priority == .status {
                guard now - lastSpokenAt >= minStatusInterval else { return nil }
            } else if message.level == lastLevel {
                return nil
            }
        }

        lastKey = message.key
        lastLevel = message.level
        lastSpokenAt = now
        return message
    }

    public mutating func reset() {
        lastKey = nil
        lastLevel = 0
        lastSpokenAt = -.infinity
    }
}
