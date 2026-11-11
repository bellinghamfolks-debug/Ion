import XCTest
@testable import BasirConvert

final class ServerTasksTests: XCTestCase {
    func testTheRecordIsKeptOnDiskAndReadBackTheSame() {
        let previous = ServerTaskStore.load()
        defer { ServerTaskStore.save(previous) }
        var task = ServerTask(id: "summary-test", kind: .summary, title: "مستند", notificationID: UUID().uuidString)
        task.jobID = String(repeating: "a", count: 32)
        task.state = .working
        task.done = 3
        task.total = 9
        ServerTaskStore.save([task])
        let loaded = ServerTaskStore.load()
        XCTAssertEqual(loaded.map(\.id), ["summary-test"])
        XCTAssertEqual(loaded.first?.jobID, task.jobID)
        XCTAssertEqual(loaded.first?.percent, 33)
        XCTAssertEqual(loaded.first?.isActive, true)
    }

    func testTheRequestBodyStaysUntilItIsNoLongerNeeded() {
        let id = "summary-body-\(UUID().uuidString)"
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

    func testRetiredAndUnknownRecordsDoNotLoseActiveSummaries() throws {
        let task = ServerTask(id: "retained-summary", kind: .summary, title: "مستند", notificationID: "n")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(task)
        let row = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var retired = row
        retired["kind"] = "restyle"
        retired["id"] = "retired-task"
        var unknown = row
        unknown["kind"] = "future-task"
        let data = try JSONSerialization.data(withJSONObject: [retired, row, unknown])
        let retained = ServerTaskStore.decodeLedger(data)
        XCTAssertEqual(retained.map(\.id), [task.id])
        XCTAssertEqual(retained.first?.kind, .summary)
        XCTAssertEqual(retained.first?.state, .sending)
        XCTAssertEqual(ServerTaskStore.decodeLedger(Data("invalid".utf8)), [])
    }

    @MainActor
    func testProgressIsDescribedByStage() {
        let center = ServerTaskCenter.shared
        XCTAssertFalse(center.stage(kind: .summary, done: 1, total: 5).isEmpty)
        XCTAssertFalse(center.stage(kind: .summary, done: 7, total: 9).isEmpty)
    }
}
