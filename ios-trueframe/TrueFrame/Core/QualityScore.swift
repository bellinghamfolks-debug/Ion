import Foundation

/// A purely TECHNICAL photographic quality score (0–100). It never scores
/// attractiveness, beauty, or any personal trait — only measurable capture
/// quality. Pure and unit-tested.
public struct QualityScore: Equatable, Sendable {
    public var levelness: Int
    public var sharpness: Int
    public var exposure: Int
    public var framing: Int
    public var obstruction: Int
    public var total: Int

    public init(levelness: Int, sharpness: Int, exposure: Int, framing: Int, obstruction: Int) {
        self.levelness = levelness
        self.sharpness = sharpness
        self.exposure = exposure
        self.framing = framing
        self.obstruction = obstruction
        // Weighted mean; obstruction and sharpness weigh most because they can
        // ruin a photo outright.
        let weighted = Double(levelness) * 0.18
            + Double(sharpness) * 0.30
            + Double(exposure) * 0.16
            + Double(framing) * 0.16
            + Double(obstruction) * 0.20
        self.total = Int(weighted.rounded())
    }

    public static func from(_ a: FrameAnalysis) -> QualityScore {
        let levelness = max(0, 100 - Int((abs(a.level.rollDegrees) * 6).rounded()))
        let sharpness: Int = {
            switch a.sharpness { case .sharp: return 96; case .slightlySoft: return 80
            case .blurry: return 45; case .severelyBlurry: return 15 }
        }()
        let exposure: Int = {
            switch a.exposure { case .good: return 92; case .bright: return 82; case .dark: return 74
            case .veryDark: return 45; case .overexposed: return 55 }
        }()
        var framing = 90
        if a.framing.hasClipping { framing -= 25 }
        if let off = a.framing.horizontalOffset { framing -= Int(min(30, abs(off) * 40)) }
        framing = max(0, framing)
        let obstruction = a.obstruction.isObstructed
            ? max(0, 100 - Int(a.obstruction.confidence * 100)) : 100
        return QualityScore(levelness: levelness, sharpness: sharpness,
                            exposure: exposure, framing: framing, obstruction: obstruction)
    }

    /// A VoiceOver-friendly multi-line report.
    public var spokenReport: String {
        """
        Technical quality: \(total) out of 100.
        Levelness: \(levelness). Sharpness: \(sharpness). Exposure: \(exposure). \
        Framing: \(framing). Lens obstruction: \(obstruction).
        """
    }
}
