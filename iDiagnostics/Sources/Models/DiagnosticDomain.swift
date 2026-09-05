import Foundation

enum TestOutcome: String, Codable, CaseIterable, Sendable {
    case pass
    case fail
    case warning
    case unsupported
    case notRun

    var titleAr: String {
        switch self {
        case .pass: return "سليم"
        case .fail: return "توجد مشكلة"
        case .warning: return "يحتاج انتباهًا"
        case .unsupported: return "غير قابل للفحص"
        case .notRun: return "لم يُفحص"
        }
    }

    var systemImage: String {
        switch self {
        case .pass: return "checkmark.circle.fill"
        case .fail: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .unsupported: return "lock.slash.fill"
        case .notRun: return "circle.dashed"
        }
    }

    var scoreFraction: Double? {
        switch self {
        case .pass: return 1
        case .warning: return 0.6
        case .fail: return 0
        case .unsupported, .notRun: return nil
        }
    }

    var isCompleted: Bool { self != .notRun }
}

enum EvidenceKind: String, Codable, Sendable {
    case automatic
    case userConfirmed
    case mixed

    var titleAr: String {
        switch self {
        case .automatic: return "قياس آلي"
        case .userConfirmed: return "تأكيد المستخدم"
        case .mixed: return "قياس آلي وتأكيد المستخدم"
        }
    }
}

enum TestCategory: String, Codable, CaseIterable, Identifiable, Sendable {
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
        case .system: return "النظام والبطارية"
        case .display: return "الشاشة والبكسلات"
        case .multiTouch: return "اللمس المتعدد"
        case .sensors: return "مستشعرات الحركة"
        case .connectivity: return "الاتصالات وGPS"
        case .camera: return "الكاميرات والفلاش"
        case .microphone: return "الميكروفون"
        case .speaker: return "مكبر الصوت"
        case .haptics: return "الاهتزاز"
        case .buttons: return "الأزرار"
        case .biometrics: return "Face ID أو Touch ID"
        }
    }

    var subtitleAr: String {
        switch self {
        case .system: return "الموديل، النظام، التخزين، الذاكرة والحرارة"
        case .display: return "ألوان كاملة لاكتشاف البكسلات غير السليمة بصريًا"
        case .multiTouch: return "عدد اللمسات المتزامنة وتغطية سطح الشاشة"
        case .sensors: return "التسارع، الجيروسكوب ومستشعر التقارب"
        case .connectivity: return "مسار الإنترنت، البلوتوث وقراءة موقع واحدة"
        case .camera: return "معاينة الأمامية والخلفية وتشغيل الفلاش"
        case .microphone: return "تسجيل محلي قصير ثم تشغيله وحذفه"
        case .speaker: return "نغمة آمنة ثم تأكيد وضوح الصوت"
        case .haptics: return "أنماط اهتزاز خفيف ومتوسط وقوي"
        case .buttons: return "رصد تغيّر مستوى الصوت وتأكيد بقية الأزرار"
        case .biometrics: return "اختبار مصادقة محلي يحميه النظام"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "cpu"
        case .display: return "display"
        case .multiTouch: return "hand.point.up.braille"
        case .sensors: return "gyroscope"
        case .connectivity: return "antenna.radiowaves.left.and.right"
        case .camera: return "camera.fill"
        case .microphone: return "mic.fill"
        case .speaker: return "speaker.wave.3.fill"
        case .haptics: return "iphone.radiowaves.left.and.right"
        case .buttons: return "button.horizontal.top.press.fill"
        case .biometrics: return "faceid"
        }
    }

    var scoreWeight: Double {
        switch self {
        case .system: return 0.5
        case .display, .multiTouch, .camera, .microphone, .speaker: return 1.2
        case .sensors, .connectivity, .haptics, .buttons, .biometrics: return 1.0
        }
    }
}

struct DiagnosticMetric: Codable, Equatable, Identifiable, Sendable {
    var id: String { "\(label):\(value)" }
    let label: String
    let value: String
}

struct DiagnosticResult: Codable, Equatable, Identifiable, Sendable {
    var id: String { category.rawValue }
    let category: TestCategory
    var outcome: TestOutcome
    var summaryAr: String
    var metrics: [DiagnosticMetric]
    var evidence: EvidenceKind
    var limitationAr: String?
    var startedAt: Date
    var completedAt: Date

    init(
        category: TestCategory,
        outcome: TestOutcome = .notRun,
        summaryAr: String = "",
        metrics: [DiagnosticMetric] = [],
        evidence: EvidenceKind = .userConfirmed,
        limitationAr: String? = nil,
        startedAt: Date = Date(),
        completedAt: Date = Date()
    ) {
        self.category = category
        self.outcome = outcome
        self.summaryAr = summaryAr
        self.metrics = metrics
        self.evidence = evidence
        self.limitationAr = limitationAr
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

struct DeviceSnapshot: Codable, Equatable, Sendable {
    let modelIdentifier: String
    let marketingName: String
    let systemName: String
    let systemVersion: String
    let appVersion: String
    let generatedAt: Date
}

struct DiagnosticSession: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 2

    let id: UUID
    let schema: Int
    let startedAt: Date
    var updatedAt: Date
    var device: DeviceSnapshot
    var results: [TestCategory: DiagnosticResult]

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        device: DeviceSnapshot,
        results: [TestCategory: DiagnosticResult] = [:]
    ) {
        self.id = id
        self.schema = Self.schemaVersion
        self.startedAt = startedAt
        self.updatedAt = startedAt
        self.device = device
        self.results = results
    }

    mutating func record(_ result: DiagnosticResult, now: Date = Date()) {
        results[result.category] = result
        updatedAt = now
    }

    mutating func clear(_ category: TestCategory, now: Date = Date()) {
        results.removeValue(forKey: category)
        updatedAt = now
    }

    func result(for category: TestCategory) -> DiagnosticResult {
        results[category] ?? DiagnosticResult(category: category)
    }

    var completedCount: Int {
        TestCategory.allCases.filter { result(for: $0).outcome.isCompleted }.count
    }

    var progress: Double {
        guard !TestCategory.allCases.isEmpty else { return 0 }
        return Double(completedCount) / Double(TestCategory.allCases.count)
    }

    /// Nil means there is not enough evidence yet; it is intentionally not 0.
    var healthScore: Int? {
        let scored = TestCategory.allCases.compactMap { category -> (Double, Double)? in
            guard let fraction = result(for: category).outcome.scoreFraction else { return nil }
            return (fraction * category.scoreWeight, category.scoreWeight)
        }
        let possible = scored.reduce(0) { $0 + $1.1 }
        guard possible > 0 else { return nil }
        let earned = scored.reduce(0) { $0 + $1.0 }
        return Int((earned / possible * 100).rounded())
    }
}
