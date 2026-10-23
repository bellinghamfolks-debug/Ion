import XCTest
@testable import BasirConvert

final class ServerTasksTests: XCTestCase {
    func testTheRecordIsKeptOnDiskAndReadBackTheSame() {
        let previous = ServerTaskStore.load()
        defer { ServerTaskStore.save(previous) }
        var task = ServerTask(id: "restyle-test", kind: .restyle, title: "رواية", notificationID: UUID().uuidString)
        task.jobID = String(repeating: "a", count: 32)
        task.state = .working
        task.done = 3
        task.total = 9
        ServerTaskStore.save([task])
        let loaded = ServerTaskStore.load()
        XCTAssertEqual(loaded.map(\.id), ["restyle-test"])
        XCTAssertEqual(loaded.first?.jobID, task.jobID)
        XCTAssertEqual(loaded.first?.percent, 33)
        XCTAssertEqual(loaded.first?.isActive, true)
    }

    func testTheRequestBodyStaysUntilItIsNoLongerNeeded() {
        let id = "restyle-body-\(UUID().uuidString)"
        ServerTaskStore.saveBody(Data("{\"text\":\"نص\"}".utf8), for: id)
        XCTAssertNotNil(ServerTaskStore.body(for: id))
        ServerTaskStore.removeBody(for: id)
        XCTAssertNil(ServerTaskStore.body(for: id))
    }

    @MainActor
    func testAJobTheServerLostIsSentAgainButOtherErrorsAreWaitedOut() {
        XCTAssertTrue(ServerTaskCenter.isMissing(BasirError.conversionFailed("Server HTTP 404: Job not found.")))
        XCTAssertFalse(ServerTaskCenter.isMissing(BasirError.conversionFailed("Server HTTP 503: busy")))
        XCTAssertFalse(ServerTaskCenter.isMissing(URLError(.notConnectedToInternet)))
    }

    func testEndedTasksAreNotActive() {
        for state in [ServerTask.State.finished, .failed, .cancelled] {
            var task = ServerTask(id: "x", kind: .summary, title: "t", notificationID: "n")
            task.state = state
            XCTAssertFalse(task.isActive, state.rawValue)
        }
    }

    @MainActor
    func testAFinishedSummaryOpensItsOwnDocumentAgain() throws {
        let id = "summary-reopen-\(UUID().uuidString)"
        let body = SummaryRequestBody(text: "نص العقد كاملًا", title: "العقد", language: "ar")
        ServerTaskStore.saveBody(try body.encoded(), for: id)
        defer { ServerTaskStore.removeBody(for: id) }
        var task = ServerTask(id: id, kind: .summary, title: "ملخص: العقد", notificationID: "n")
        task.summaryHome = "key:abc"
        task.summaryVariant = body.variantKey
        let source = try XCTUnwrap(ServerTaskDestination.summarySource(task))
        XCTAssertEqual(source.title, "العقد")
        XCTAssertEqual(source.text, "نص العقد كاملًا")
        XCTAssertEqual(source.home, .key("abc"))
    }

    @MainActor
    func testProgressIsDescribedByStage() {
        let center = ServerTaskCenter.shared
        XCTAssertFalse(center.stage(kind: .summary, done: 1, total: 5).isEmpty)
        XCTAssertTrue(center.stage(kind: .restyle, done: 7, total: 9).contains("77"))
    }
}
