import Foundation
import CoreGraphics

// MARK: - Leveling

public enum TiltDirection: String, Sendable { case clockwise, counterClockwise, none }

/// A device-attitude reading reduced to the two angles that matter for photos:
/// `roll` (rotation around the viewing axis, the horizon tilt) and `pitch`
/// (tilt forward/back, pointing too high/low).
public struct LevelReading: Equatable, Sendable {
    public var rollDegrees: Double
    public var pitchDegrees: Double

    public init(rollDegrees: Double, pitchDegrees: Double) {
        self.rollDegrees = rollDegrees
        self.pitchDegrees = pitchDegrees
    }

    public var tiltDirection: TiltDirection {
        if abs(rollDegrees) < LevelThresholds.level { return .none }
        return rollDegrees > 0 ? .clockwise : .counterClockwise
    }

    public var isLevel: Bool { abs(rollDegrees) < LevelThresholds.level }
    public var isNearLevel: Bool { abs(rollDegrees) < LevelThresholds.nearLevel }
}

public enum LevelMath {
    /// Converts the gravity-projected screen angle into horizon tilt relative to
    /// the nearest portrait/landscape cardinal orientation.
    public static func cardinalRelativeRoll(rawScreenAngleDegrees: Double) -> Double {
        let nearestCardinal = (rawScreenAngleDegrees / 90).rounded() * 90
        return normalizeDegrees(rawScreenAngleDegrees - nearestCardinal)
    }

    private static func normalizeDegrees(_ value: Double) -> Double {
        var result = value.truncatingRemainder(dividingBy: 360)
        if result > 180 { result -= 360 }
        if result < -180 { result += 360 }
        return result
    }
}

public enum LevelThresholds {
    public static let level: Double = 1.0
    public static let nearLevel: Double = 3.0

    /// Auto capture gets a slightly wider tolerance than the spoken "perfectly
    /// level" state. Requiring exactly ±1 degree made handheld auto capture
    /// unnecessarily difficult and unstable.
    public static let autoCapture: Double = 1.5

    public static let announceStep: Double = 3.0
}

// MARK: - Per-frame vision analysis

public enum Sharpness: String, Sendable {
    case sharp, slightlySoft, blurry, severelyBlurry

    public var spokenLabel: String {
        switch self {
        case .sharp: return "Sharpness is good."
        case .slightlySoft: return "Image is slightly soft."
        case .blurry: return "Image may be blurry."
        case .severelyBlurry: return "Image is very blurry."
        }
    }
}

public enum ExposureState: String, Sendable {
    case good, dark, veryDark, bright, overexposed

    public var spokenLabel: String {
        switch self {
        case .good: return "Exposure good."
        case .dark: return "Scene is a little dark."
        case .veryDark: return "Scene is very dark."
        case .bright: return "Exposure is slightly bright."
        case .overexposed: return "Bright areas are overexposed."
        }
    }
}

public enum ObstructionRegion: String, Sendable {
    case lowerLeft, lowerRight, upperLeft, upperRight, center, unknown

    public var spoken: String {
        switch self {
        case .lowerLeft: return "lower-left"
        case .lowerRight: return "lower-right"
        case .upperLeft: return "upper-left"
        case .upperRight: return "upper-right"
        case .center: return "center"
        case .unknown: return "part"
        }
    }
}

public struct ObstructionResult: Sendable {
    public var isObstructed: Bool
    public var region: ObstructionRegion
    public var confidence: Double

    public init(isObstructed: Bool = false,
                region: ObstructionRegion = .unknown,
                confidence: Double = 0) {
        self.isObstructed = isObstructed
        self.region = region
        self.confidence = confidence
    }
}

/// Subject framing summary. Boxes are in normalized 0...1 coordinates with a
/// top-left origin. `primarySubject` can come from a person/face detector or
/// from Vision saliency when there is no person in the frame.
public struct FramingResult: Sendable {
    public var personCount: Int
    public var faceCount: Int
    public var primarySubject: CGRect?
    public var clippedTop: Bool
    public var clippedBottom: Bool
    public var clippedLeft: Bool
    public var clippedRight: Bool

    public init(personCount: Int = 0,
                faceCount: Int = 0,
                primarySubject: CGRect? = nil,
                clippedTop: Bool = false,
                clippedBottom: Bool = false,
                clippedLeft: Bool = false,
                clippedRight: Bool = false) {
        self.personCount = personCount
        self.faceCount = faceCount
        self.primarySubject = primarySubject
        self.clippedTop = clippedTop
        self.clippedBottom = clippedBottom
        self.clippedLeft = clippedLeft
        self.clippedRight = clippedRight
    }

    public var hasClipping: Bool {
        clippedTop || clippedBottom || clippedLeft || clippedRight
    }

    /// Horizontal offset of the primary subject from center, in [-1, 1].
    public var horizontalOffset: CGFloat? {
        guard let subject = primarySubject else { return nil }
        return (subject.midX - 0.5) * 2
    }
}

public struct FrameAnalysis: Sendable {
    public var level: LevelReading
    public var sharpness: Sharpness
    public var motionHigh: Bool
    public var exposure: ExposureState
    public var obstruction: ObstructionResult
    public var framing: FramingResult
    public var skyFraction: Double
    public var groundFraction: Double
    public var visualHorizonDegrees: Double?
    public var visualHorizonConfidence: Double

    public init(level: LevelReading,
                sharpness: Sharpness = .sharp,
                motionHigh: Bool = false,
                exposure: ExposureState = .good,
                obstruction: ObstructionResult = .init(),
                framing: FramingResult = .init(),
                skyFraction: Double = 0,
                groundFraction: Double = 0,
                visualHorizonDegrees: Double? = nil,
                visualHorizonConfidence: Double = 0) {
        self.level = level
        self.sharpness = sharpness
        self.motionHigh = motionHigh
        self.exposure = exposure
        self.obstruction = obstruction
        self.framing = framing
        self.skyFraction = skyFraction
        self.groundFraction = groundFraction
        self.visualHorizonDegrees = visualHorizonDegrees
        self.visualHorizonConfidence = visualHorizonConfidence
    }
}

// MARK: - Correction

public struct CorrectionPlan: Equatable, Sendable {
    public var rollDegrees: Double
    public var perspectiveVerticalDegrees: Double
    public var perspectiveHorizontalDegrees: Double
    public var cropNormalized: NormalizedRect
    public var horizonConfidence: Double

    public init(rollDegrees: Double = 0,
                perspectiveVerticalDegrees: Double = 0,
                perspectiveHorizontalDegrees: Double = 0,
                cropNormalized: NormalizedRect = .full,
                horizonConfidence: Double = 0) {
        self.rollDegrees = rollDegrees
        self.perspectiveVerticalDegrees = perspectiveVerticalDegrees
        self.perspectiveHorizontalDegrees = perspectiveHorizontalDegrees
        self.cropNormalized = cropNormalized
        self.horizonConfidence = horizonConfidence
    }

    public var isIdentity: Bool {
        abs(rollDegrees) < 0.05
            && abs(perspectiveVerticalDegrees) < 0.05
            && abs(perspectiveHorizontalDegrees) < 0.05
            && cropNormalized == .full
    }
}
