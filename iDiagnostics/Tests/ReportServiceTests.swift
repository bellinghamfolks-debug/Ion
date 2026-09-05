import XCTest
@testable import iDiagnostics

final class ReportServiceTests: XCTestCase {
    func testTextReportContainsAccessibilityAndAccuracyContext() {
        var session = DiagnosticSession(device: DeviceSnapshot(
            modelIdentifier: "iPhone16,2",
            marketingName: "iPhone 15 Pro Max",
            systemName: "iOS",
            systemVersion: "18.0",
            appVersion: "2.0.0",
            generatedAt: Date(timeIntervalSince1970: 1)
        ))
        session.record(DiagnosticResult(
            category: .camera,
            outcome: .warning,
            summaryAr: "لم يكتمل الفحص",
            metrics: [.init(label: "الكاميرا", value: "الأمامية")],
            evidence: .mixed,
            limitationAr: "لا يقيس الحساس مخبريًا"
        ))

        let report = ReportService().textReport(session: session)
        XCTAssertTrue(report.contains("ليس تشخيصًا معتمدًا من Apple"))
        XCTAssertTrue(report.contains("لم يكتمل الفحص"))
        XCTAssertTrue(report.contains("حدود الفحص"))
    }
}
