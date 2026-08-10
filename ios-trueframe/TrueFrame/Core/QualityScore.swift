import Foundation

/// Technical capture quality only. It does not score attractiveness, identity,
/// emotion, or any personal characteristic.
public struct QualityScore: Equatable, Sendable {
    public var levelness: Int
    public var sharpness: Int
    public var exposure: Int
    public var framing: Int
    public var obstruction: Int
    public var total: Int

    public init(levelness: Int,
                sharpness: Int,
                exposure: Int,
                framing: Int,
                obstruction: Int) {
        self.levelness = levelness
        self.sharpness = sharpness
        self.exposure = exposure
        self.framing = framing
        self.obstruction = obstruction

        let weighted = Double(levelness) * 0.18
            + Double(sharpness) * 0.30
            + Double(exposure) * 0.16
            + Double(framing) * 0.16
            + Double(obstruction) * 0.20
        self.total = Int(weighted.rounded())
    }

    public static func from(_ analysis: FrameAnalysis) -> QualityScore {
        var effectiveTilt = abs(analysis.level.rollDegrees)
        if let visual = analysis.visualHorizonDegrees,
           analysis.visualHorizonConfidence >= 0.65 {
            effectiveTilt = max(effectiveTilt, abs(visual))
        }

        let levelness = max(0, 100 - Int((effectiveTilt * 6).rounded()))

        let sharpness: Int = {
            switch analysis.sharpness {
            case .sharp: return 96
            case .slightlySoft: return 80
            case .blurry: return 45
            case .severelyBlurry: return 15
            }
        }()

        let exposure: Int = {
            switch analysis.exposure {
            case .good: return 92
            case .bright: return 82
            case .dark: return 74
            case .veryDark: return 45
            case .overexposed: return 55
            }
        }()

        var framing = 90
        if analysis.framing.hasClipping { framing -= 25 }
        if let offset = analysis.framing.horizontalOffset {
            framing -= Int(min(30, abs(offset) * 40))
        }
        framing = max(0, framing)

        let obstruction = analysis.obstruction.isObstructed
            ? max(0, 100 - Int(analysis.obstruction.confidence * 100))
            : 100

        return QualityScore(levelness: levelness,
                            sharpness: sharpness,
                            exposure: exposure,
                            framing: framing,
                            obstruction: obstruction)
    }

    public var spokenReport: String {
        spokenReport(languageCode: "en")
    }

    public func spokenReport(languageCode: String) -> String {
        if languageCode == "ar" {
            return """
            جودة الالتقاط التقنية: \(total) من 100.
            الاستقامة: \(levelness). الوضوح: \(sharpness). الإضاءة: \(exposure). الإطار: \(framing). سلامة العدسة: \(obstruction).
            """
        }

        return """
        Technical quality: \(total) out of 100.
        Levelness: \(levelness). Sharpness: \(sharpness). Exposure: \(exposure). Framing: \(framing). Lens visibility: \(obstruction).
        """
    }
}
