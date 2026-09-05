import Combine
import Foundation

@MainActor
final class DiagnosticsStore: ObservableObject {
    @Published private(set) var session: DiagnosticSession
    @Published var persistenceAlert: String?

    private let repository: SessionRepository

    init(repository: SessionRepository = DiskSessionRepository()) {
        self.repository = repository
        do {
            if let restored = try repository.load() {
                session = restored
                AppLog.persistence.info("Restored diagnostic session \(restored.id.uuidString, privacy: .public)")
            } else {
                session = DiagnosticSession(device: DeviceIdentity.snapshot())
            }
        } catch {
            session = DiagnosticSession(device: DeviceIdentity.snapshot())
            persistenceAlert = error.localizedDescription
            AppLog.persistence.error("Session recovery: \(error.localizedDescription, privacy: .public)")
        }
        persist()
    }

    var completedCount: Int { session.completedCount }
    var totalCount: Int { TestCategory.allCases.count }
    var progress: Double { session.progress }
    var healthScore: Int? { session.healthScore }

    func result(for category: TestCategory) -> DiagnosticResult {
        session.result(for: category)
    }

    func record(_ result: DiagnosticResult) {
        session.record(result)
        persist()
        AccessibilityAnnouncer.post("تم حفظ نتيجة \(result.category.titleAr): \(result.outcome.titleAr)")
        AppLog.diagnostics.info("Recorded \(result.category.rawValue, privacy: .public): \(result.outcome.rawValue, privacy: .public)")
    }

    func record(
        category: TestCategory,
        outcome: TestOutcome,
        summary: String,
        metrics: [DiagnosticMetric] = [],
        evidence: EvidenceKind,
        limitation: String? = nil,
        startedAt: Date = Date()
    ) {
        record(DiagnosticResult(
            category: category,
            outcome: outcome,
            summaryAr: summary,
            metrics: metrics,
            evidence: evidence,
            limitationAr: limitation,
            startedAt: startedAt,
            completedAt: Date()
        ))
    }

    func clear(_ category: TestCategory) {
        session.clear(category)
        persist()
    }

    func startNewSession() {
        session = DiagnosticSession(device: DeviceIdentity.snapshot())
        persist()
        AccessibilityAnnouncer.post("بدأت جلسة فحص جديدة")
    }

    func saveNow() {
        persist()
    }

    private func persist() {
        do {
            try repository.save(session)
        } catch {
            persistenceAlert = "تعذر حفظ نتائج الفحص على الجهاز. حاول توفير مساحة ثم أعد المحاولة."
            AppLog.persistence.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
