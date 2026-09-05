import XCTest
@testable import iDiagnostics

final class DiagnosticDomainTests: XCTestCase {
    func testNewSessionHasNoMisleadingZeroScore() {
        let session = makeSession()
        XCTAssertNil(session.healthScore)
        XCTAssertEqual(session.completedCount, 0)
        XCTAssertEqual(session.progress, 0)
    }

    func testScoreExcludesNotRunAndUnsupportedResults() {
        var session = makeSession()
        session.record(result(.display, .pass))
        session.record(result(.camera, .fail))
        session.record(result(.biometrics, .unsupported))

        XCTAssertEqual(session.healthScore, 50)
        XCTAssertEqual(session.completedCount, 3)
    }

    func testWarningUsesPartialScoreAndCategoryWeights() {
        var session = makeSession()
        session.record(result(.system, .pass))
        session.record(result(.display, .warning))

        let expected = Int((((0.5 * 1.0) + (1.2 * 0.6)) / 1.7 * 100).rounded())
        XCTAssertEqual(session.healthScore, expected)
    }

    func testReplacingResultDoesNotIncreaseProgressTwice() {
        var session = makeSession()
        session.record(result(.speaker, .warning))
        session.record(result(.speaker, .pass))

        XCTAssertEqual(session.completedCount, 1)
        XCTAssertEqual(session.result(for: .speaker).outcome, .pass)
    }

    private func makeSession() -> DiagnosticSession {
        DiagnosticSession(device: DeviceSnapshot(
            modelIdentifier: "iPhone16,2",
            marketingName: "iPhone 15 Pro Max",
            systemName: "iOS",
            systemVersion: "18.0",
            appVersion: "2.0.0",
            generatedAt: Date(timeIntervalSince1970: 1)
        ))
    }

    private func result(_ category: TestCategory, _ outcome: TestOutcome) -> DiagnosticResult {
        DiagnosticResult(category: category, outcome: outcome, summaryAr: "اختبار")
    }
}
