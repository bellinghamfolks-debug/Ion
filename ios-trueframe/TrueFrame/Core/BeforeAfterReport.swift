import Foundation

/// Text-first audit of deterministic image correction. It reports only actions
/// the app actually performed and avoids unverifiable claims about the scene.
public struct BeforeAfterReport: Sendable {
    public let original: CorrectionPlan
    public let provenance: EditingProvenance

    public init(original: CorrectionPlan, provenance: EditingProvenance) {
        self.original = original
        self.provenance = provenance
    }

    public var spoken: String {
        spoken(languageCode: "en")
    }

    public func spoken(languageCode: String) -> String {
        let cropPercent = String(format: "%.1f", provenance.croppedAreaFraction * 100)
        let rotation = String(format: "%.1f", abs(provenance.rotationDegrees))

        if languageCode == "ar" {
            var lines: [String] = []
            lines.append("التعديل الذي تم:")
            if abs(provenance.rotationDegrees) >= 0.05 {
                lines.append("تم تدوير الصورة بمقدار \(rotation) درجة لتصحيح الميل.")
            } else {
                lines.append("لم يلزم تدوير ملحوظ للصورة.")
            }
            if abs(provenance.perspectiveVerticalDegrees) < 0.1,
               abs(provenance.perspectiveHorizontalDegrees) < 0.1 {
                lines.append("لم يتم تغيير المنظور.")
            } else {
                lines.append("تم إجراء تصحيح هندسي بسيط للمنظور.")
            }
            lines.append("تم قص نحو \(cropPercent) بالمئة من الحواف الخارجية الناتجة عن التصحيح.")
            lines.append(provenance.generativeModelAlteredPixels
                         ? "استُخدم تعديل توليدي."
                         : "لم يُستخدم أي تعديل توليدي، وكل محتوى الصورة مصدره الصورة الأصلية.")
            return lines.joined(separator: "\n")
        }

        var lines: [String] = []
        lines.append("Changes applied:")
        if abs(provenance.rotationDegrees) >= 0.05 {
            lines.append("Rotated the photo by \(rotation) degrees to correct tilt.")
        } else {
            lines.append("No meaningful rotation was needed.")
        }
        if abs(provenance.perspectiveVerticalDegrees) < 0.1,
           abs(provenance.perspectiveHorizontalDegrees) < 0.1 {
            lines.append("Perspective was not changed.")
        } else {
            lines.append("A small geometric perspective correction was applied.")
        }
        lines.append("Cropped about \(cropPercent) percent from the outer edges created by correction.")
        lines.append(provenance.generativeModelAlteredPixels
                     ? "Generative editing was used."
                     : "No generative editing was used; output content comes from the original photo.")
        return lines.joined(separator: "\n")
    }
}
