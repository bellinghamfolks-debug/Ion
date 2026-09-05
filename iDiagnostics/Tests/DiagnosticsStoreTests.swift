import XCTest
@testable import iDiagnostics

@MainActor
final class DiagnosticsStoreTests: XCTestCase {
    func testRecordingImmediatelyPersists() {
        let repository = MemorySessionRepository()
        let store = DiagnosticsStore(repository: repository)

        store.record(
            category: .speaker,
            outcome: .pass,
            summary: "واضح",
            evidence: .userConfirmed
        )

        XCTAssertEqual(repository.session?.result(for: .speaker).outcome, .pass)
        XCTAssertEqual(store.completedCount, 1)
    }

    func testNewSessionClearsAllResultsAndChangesID() {
        let repository = MemorySessionRepository()
        let store = DiagnosticsStore(repository: repository)
        let oldID = store.session.id
        store.record(category: .camera, outcome: .fail, summary: "مشكلة", evidence: .mixed)

        store.startNewSession()

        XCTAssertNotEqual(store.session.id, oldID)
        XCTAssertEqual(store.completedCount, 0)
        XCTAssertNil(store.healthScore)
    }
}
