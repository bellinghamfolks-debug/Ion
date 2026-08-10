import Foundation

/// Renders the current guidance message in Arabic. The prioritization/throttling
/// logic stays in `GuidanceRules` (pure, English, unit-tested); this only
/// produces the spoken/displayed Arabic string for the chosen key, using the
/// same analysis for the dynamic parts. If a key isn't translated, the English
/// text is used as a safe fallback.
public enum GuidanceArabic {

    public static func text(for msg: GuidanceMessage, analysis a: FrameAnalysis, verbosity: Verbosity) -> String {
        let roll = a.level.rollDegrees
        switch msg.key {
        case "obstruction":
            return "الكاميرا مغطّاة عند \(regionAr(a.obstruction.region)). حرّك إصبعك."
        case "mostlySky":
            return "معظم الصورة سماء. اخفض الكاميرا."
        case "mostlyGround":
            return "معظم الصورة أرض. ارفع الكاميرا."
        case "tilt":
            if a.level.isLevel { return "مستوٍ." }
            if a.level.isNearLevel { return "اقتربت من الاستواء." }
            let dir = roll > 0 ? "لليسار" : "لليمين"
            if abs(roll) >= 8 {
                if verbosity == .minimal { return "أدر \(dir)." }
                let sense = roll > 0 ? "باتجاه عقارب الساعة" : "عكس عقارب الساعة"
                return "\(Int(abs(roll).rounded())) درجة ميلان \(sense). أدر \(dir)."
            }
            return "أدر قليلًا \(dir)."
        case "clipTop":
            return "الرأس قريب من الأعلى. اخفض الكاميرا."
        case "clipBottom":
            return "القدمان مقصوصتان. ارفع الكاميرا أو تراجع إن كان آمنًا."
        case "subjectEdge":
            let right = (a.framing.horizontalOffset ?? 0) > 0
            return right ? "الهدف قرب الحافة اليمنى. حرّك الكاميرا يمينًا." : "الهدف قرب الحافة اليسرى. حرّك الكاميرا يسارًا."
        case "motion":
            return "أمسك الجهاز بثبات."
        case "blur":
            return "قد تكون الصورة غير واضحة."
        case "exposure":
            switch a.exposure {
            case .veryDark: return "المشهد مظلم جدًا."
            case .overexposed: return "المناطق الساطعة محترقة."
            case .dark: return "المشهد مظلم قليلًا."
            case .bright: return "الإضاءة ساطعة قليلًا."
            case .good: return "الإضاءة جيدة."
            }
        case "ok":
            return "مستوٍ."
        default:
            return msg.text
        }
    }

    private static func regionAr(_ r: ObstructionRegion) -> String {
        switch r {
        case .lowerLeft: return "أسفل اليسار"
        case .lowerRight: return "أسفل اليمين"
        case .upperLeft: return "أعلى اليسار"
        case .upperRight: return "أعلى اليمين"
        case .center: return "المنتصف"
        case .unknown: return "جزء"
        }
    }
}
