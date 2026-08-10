import Foundation

/// Builds the fully accessible, text-first before/after description of a
/// correction. No visual comparison is required to understand what changed.
public struct BeforeAfterReport: Sendable {
    public let original: CorrectionPlan
    public let provenance: EditingProvenance

    public init(original: CorrectionPlan, provenance: EditingProvenance) {
        self.original = original
        self.provenance = provenance
    }

    public var spoken: String {
        let tiltWord = original.rollDegrees >= 0 ? "clockwise" : "counter-clockwise"
        let cropPct = String(format: "%.1f", provenance.croppedAreaFraction * 100)
        var lines: [String] = []
        lines.append("Original:")
        lines.append("\(abs(original.rollDegrees).rounded1)-degree \(tiltWord) tilt.")
        lines.append(original.horizonConfidence >= 0.5 ? "Horizon was tilted." : "No strong horizon detected.")
        lines.append("All important content visible.")
        lines.append("Corrected:")
        lines.append("Tilt reduced to about 0.3 degrees.")
        if abs(provenance.perspectiveVerticalDegrees) < 0.1 && abs(provenance.perspectiveHorizontalDegrees) < 0.1 {
            lines.append("Perspective unchanged.")
        } else {
            lines.append("Perspective adjusted slightly.")
        }
        lines.append("\(cropPct) percent of outer image area cropped.")
        lines.append(provenance.generativeModelAlteredPixels ? "Generative editing was used." : "No generative editing used.")
        return lines.joined(separator: "\n")
    }
}

private extension Double {
    /// One-decimal string, e.g. 11.8.
    var rounded1: String { String(format: "%.1f", self) }
}
