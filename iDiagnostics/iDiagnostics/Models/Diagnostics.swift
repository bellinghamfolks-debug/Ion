import Foundation

/// The result state of a single diagnostic. `unsupported` is used honestly for
/// checks iOS does not expose on a stock device (e.g. ambient-light lux,
/// battery cycle count) so we never fabricate a value.
enum TestOutcome: String, Codable, CaseIterable {
    case pass
    case fail
    case warning
    case unsupported
    case notRun

    var titleAr: String {
        switch self {
        case .pass:        return "ناجح"
        case .fail:        return "فاشل"
        case .warning:     return "تحذير"
        case .unsupported: return "غير متاح في iOS"
        case .notRun:      return "لم يُفحص"
        }
    }

    var systemImage: String {
        switch self {
        case .pass:        return "checkmark.circle.fill"
        case .fail:        return "xmark.octagon.fill"
        case .warning:     return "exclamationmark.triangle.fill"
        case .unsupported: return "lock.slash.fill"
        case .notRun:      return "circle.dashed"
        }
    }

    /// Weight toward the overall health score. Unsupported / notRun are neutral.
    var scoreContribution: (earned: Int, possible: Int) {
        switch self {
        case .pass:        return (100, 100)
        case .warning:     return (60, 100)
        case .fail:        return (0, 100)
        case .unsupported, .notRun: return (0, 0)
        }
    }
}

/// Every diagnostic the app can run. Order here is the order shown on the
/// dashboard.
enum TestCategory: String, CaseIterable, Identifiable, Codable {
    case system
    case display
    case multiTouch
    case sensors
    case connectivity
    case camera
    case microphone
    case speaker
    case haptics
    case buttons
    case biometrics

    var id: String { rawValue }

    var titleAr: String {
        switch self {
        case .system:       return "معلومات النظام"
        case .display:      return "فحص الشاشة"
        case .multiTouch:   return "اللمس المتعدد"
        case .sensors:      return "المستشعرات"
        case .connectivity: return "الاتصالات"
        case .camera:       return "الكاميرا والفلاش"
        case .microphone:   return "الميكروفون"
        case .speaker:      return "مكبّرات الصوت"
        case .haptics:      return "محرّك الاهتزاز"
        case .buttons:      return "الأزرار الجانبية"
        case .biometrics:   return "Face ID / Touch ID"
        }
    }

    var subtitleAr: String {
        switch self {
        case .system:       return "الموديل والنظام والتخزين والذاكرة والحرارة"
        case .display:      return "البكسلات الميتة عبر ألوان كاملة الشاشة"
        case .multiTouch:   return "تتبّع عدة لمسات في وقت واحد"
        case .sensors:      return "التقارب، التسارع، الجيروسكوب، الإضاءة"
        case .connectivity: return "واي فاي، خلوي، بلوتوث، GPS"
        case .camera:       return "الأمامية والخلفية والفلاش"
        case .microphone:   return "تسجيل ثم تشغيل لسماع صوتك"
        case .speaker:      return "نغمة اختبار على كل مكبّر"
        case .haptics:      return "أنماط اهتزاز متدرّجة"
        case .buttons:      return "أزرار الصوت عبر تتبّع مستوى الصوت"
        case .biometrics:   return "المصادقة البيومترية المتاحة"
        }
    }

    var systemImage: String {
        switch self {
        case .system:       return "cpu"
        case .display:      return "display"
        case .multiTouch:   return "hand.point.up.braille"
        case .sensors:      return "gyroscope"
        case .connectivity: return "wifi"
        case .camera:       return "camera"
        case .microphone:   return "mic"
        case .speaker:      return "speaker.wave.3"
        case .haptics:      return "iphone.radiowaves.left.and.right"
        case .buttons:      return "button.horizontal.top.press"
        case .biometrics:   return "faceid"
        }
    }
}

/// The outcome of one diagnostic, plus any detail metrics to show and to place
/// in the PDF report.
struct TestResult: Identifiable, Equatable {
    var id: String { category.rawValue }
    let category: TestCategory
    var outcome: TestOutcome
    var summaryAr: String
    /// Ordered key/value detail rows (e.g. "الموديل" -> "iPhone15,3").
    var metrics: [Metric]
    var timestamp: Date

    struct Metric: Identifiable, Equatable {
        var id: String { label }
        let label: String
        let value: String
    }

    init(category: TestCategory,
         outcome: TestOutcome = .notRun,
         summaryAr: String = "",
         metrics: [Metric] = [],
         timestamp: Date = Date()) {
        self.category = category
        self.outcome = outcome
        self.summaryAr = summaryAr
        self.metrics = metrics
        self.timestamp = timestamp
    }
}

/// A basic identity snapshot of the device for the report header.
struct DeviceSnapshot {
    var modelIdentifier: String
    var marketingName: String
    var systemName: String
    var systemVersion: String
    var generatedAt: Date
}
