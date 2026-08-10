import Foundation

/// Natural Arabic rendering for live camera guidance.
/// The goal is short, actionable speech that works well with VoiceOver and does
/// not sound like a literal translation of camera-engine terminology.
public enum GuidanceArabic {

    public static let captureReady = "ممتاز. ثبّت الهاتف، سيتم التقاط الصورة الآن."

    public static func text(for message: GuidanceMessage,
                            analysis: FrameAnalysis,
                            verbosity: Verbosity) -> String {
        let roll = analysis.level.rollDegrees

        switch message.key {
        case "obstruction":
            return "يبدو أن جزءًا من العدسة مغطى. أبعد إصبعك عن الكاميرا."

        case "mostlySky":
            return "معظم الإطار للسماء. اخفض الهاتف قليلًا."

        case "mostlyGround":
            return "معظم الإطار للأرض. ارفع الهاتف قليلًا."

        case "tilt":
            if analysis.level.isLevel {
                return "الهاتف مستقيم."
            }
            if analysis.level.isNearLevel {
                return "بقي تعديل بسيط."
            }

            let direction = roll > 0 ? "إلى اليسار" : "إلى اليمين"
            if abs(roll) >= 8 {
                if verbosity == .minimal {
                    return "لف الهاتف \(direction)."
                }
                return "الميل نحو \(Int(abs(roll).rounded())) درجات. لف الهاتف \(direction)."
            }
            return "لف الهاتف قليلًا \(direction)."

        case "visualHorizon":
            return "خط الأفق في المشهد ما زال مائلًا. عدّل دوران الهاتف قليلًا."

        case "clipTop":
            return "رأس الشخص قريب جدًا من أعلى الإطار. اخفض الهاتف قليلًا."

        case "clipBottom":
            return "قدما الشخص خارج الإطار. ارفع الهاتف أو ابتعد قليلًا إن كان ذلك آمنًا."

        case "subjectEdge":
            let onRight = (analysis.framing.horizontalOffset ?? 0) > 0
            return onRight
                ? "العنصر الرئيسي قريب من الحافة اليمنى. حرّك الهاتف قليلًا إلى اليمين."
                : "العنصر الرئيسي قريب من الحافة اليسرى. حرّك الهاتف قليلًا إلى اليسار."

        case "motion":
            return "ثبّت الهاتف قليلًا."

        case "blur":
            return "الصورة غير واضحة بعد. ثبّت الهاتف لحظة حتى يكتمل التركيز."

        case "exposure":
            switch analysis.exposure {
            case .veryDark:
                return "الإضاءة ضعيفة جدًا. اقترب من مصدر ضوء إن أمكن."
            case .overexposed:
                return "هناك ضوء قوي يفقد الصورة بعض التفاصيل. أبعد الكاميرا قليلًا عن مصدر الضوء."
            case .dark:
                return "الإضاءة منخفضة قليلًا."
            case .bright:
                return "الإضاءة قوية قليلًا."
            case .good:
                return "الإضاءة مناسبة."
            }

        case "ok":
            return "ممتاز، الإطار جاهز."

        default:
            return message.text
        }
    }
}
