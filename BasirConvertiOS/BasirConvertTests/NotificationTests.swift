import XCTest
@testable import BasirConvert

/// One notification per task that only ever moves forward, and the rules
/// for what a background wake-up from the server means.
final class NotificationTests: XCTestCase {
    func testANotificationNeverGoesBackwards() {
        XCTAssertTrue(JobNotifier.allows(.working, after: nil))
        XCTAssertTrue(JobNotifier.allows(.progress, after: .working))
        XCTAssertTrue(JobNotifier.allows(.progress, after: .progress))
        XCTAssertTrue(JobNotifier.allows(.ready, after: .progress))
        // Once the file is ready, a late quarter or "still working" is wrong.
        XCTAssertFalse(JobNotifier.allows(.progress, after: .ready))
        XCTAssertFalse(JobNotifier.allows(.working, after: .ready))
        XCTAssertTrue(JobNotifier.allows(.finished, after: .ready))
        // The end is said once.
        XCTAssertFalse(JobNotifier.allows(.finished, after: .finished))
        XCTAssertFalse(JobNotifier.allows(.failed, after: .finished))
    }

    func testTheWordsAreTrue() {
        let working = JobNotifier.working(task: .conversion, title: "عقد", percent: 35, uploading: false, arabic: true)
        XCTAssertTrue(working.body.contains("35٪"))
        XCTAssertTrue(working.body.contains("ولو أغلقت التطبيق"))
        XCTAssertFalse(working.body.contains("متوقف"))
        let uploading = JobNotifier.working(task: .conversion, title: "عقد", percent: 40, uploading: true, arabic: true)
        XCTAssertTrue(uploading.body.contains("أبقِ بصير مفتوحًا"))
        let progress = JobNotifier.progress(task: .summary, title: "ملخص", percent: 50,
                                            at: Date(timeIntervalSince1970: 0), arabic: false)
        XCTAssertTrue(progress.body.hasPrefix("Summary: 50%"))
        XCTAssertTrue(progress.body.contains("Updated"))
        XCTAssertEqual(JobNotifier.failed(title: "x", reason: "  ", arabic: true).body,
                       "لم تكتمل المهمة. افتح بصير لإعادة المحاولة.")
        XCTAssertTrue(JobNotifier.finished(task: .conversion, title: "x", partial: true, arabic: false)
            .body.contains("retry"))
    }

    func testOneIdentifierPerTaskMatchesTheServersPush() {
        let id = UUID().uuidString
        XCTAssertEqual(JobNotifier.identifier(id), "basir-\(id)")
    }

    private func entry(percent: Int = 10, finished: Bool = false, age: TimeInterval = 60) -> JobWatcher.Entry {
        JobWatcher.Entry(id: "A", serverJobID: String(repeating: "a", count: 32), work: .conversion, title: "t",
                         arabic: true, percent: percent, uploading: false,
                         startedAt: Date(timeIntervalSinceNow: -age), finished: finished, appJobID: nil)
    }

    private func answer(_ outcome: String, _ status: String? = "processing", _ percent: Int? = nil) -> JobWatcher.Answer {
        JobWatcher.Answer(outcome: outcome, status: status, percent: percent, error: nil)
    }

    func testWakeUpsAreReadCorrectly() {
        let now = Date()
        XCTAssertEqual(JobWatcher.decide(entry: entry(), httpStatus: 200, answer: answer("finished", "completed", 100),
                                         cancelled: false, now: now),
                       .finished(status: "completed", percent: 100, error: nil))
        XCTAssertEqual(JobWatcher.decide(entry: entry(), httpStatus: 200, answer: answer("progress", "processing", 52),
                                         cancelled: false, now: now), .progressed(percent: 52))
        // Never report a lower percentage than already shown.
        XCTAssertEqual(JobWatcher.decide(entry: entry(percent: 60), httpStatus: 200,
                                         answer: answer("progress", "processing", 40), cancelled: false, now: now),
                       .askAgain(percent: 60))
        XCTAssertEqual(JobWatcher.decide(entry: entry(), httpStatus: 200, answer: answer("waiting"),
                                         cancelled: false, now: now), .askAgain(percent: 10))
        XCTAssertEqual(JobWatcher.decide(entry: entry(), httpStatus: 0, answer: nil, cancelled: false, now: now),
                       .retryLater)
        XCTAssertEqual(JobWatcher.decide(entry: entry(), httpStatus: 503, answer: nil, cancelled: false, now: now),
                       .retryLater)
        XCTAssertEqual(JobWatcher.decide(entry: entry(), httpStatus: 404, answer: nil, cancelled: false, now: now),
                       .forget)
        XCTAssertEqual(JobWatcher.decide(entry: entry(age: 2 * 24 * 3600), httpStatus: 200, answer: answer("waiting"),
                                         cancelled: false, now: now), .forget)
        XCTAssertEqual(JobWatcher.decide(entry: entry(), httpStatus: 200, answer: answer("finished"),
                                         cancelled: true, now: now), .ignore)
        XCTAssertEqual(JobWatcher.decide(entry: entry(finished: true), httpStatus: 200, answer: answer("finished"),
                                         cancelled: false, now: now), .ignore)
        XCTAssertEqual(JobWatcher.decide(entry: nil, httpStatus: 200, answer: answer("finished"),
                                         cancelled: false, now: now), .ignore)
    }

    func testTheServersAnswerIsReadThroughItsHeartbeats() throws {
        let body = Data("     {\"outcome\":\"progress\",\"status\":\"processing\",\"percent\":27,\"error\":null}".utf8)
        let decoded = try JSONDecoder().decode(JobWatcher.Answer.self, from: body)
        XCTAssertEqual(decoded.percent, 27)
    }

    func testTaskLabelsRoundTrip() {
        let parsed = JobWatcher.parse("6F1C-AA|step")
        XCTAssertEqual(parsed?.id, "6F1C-AA")
        XCTAssertEqual(parsed?.mode, .step)
        XCTAssertNil(JobWatcher.parse("nothing"))
    }

    @MainActor
    func testSummaryTasksGetAStableUUIDIdentifier() throws {
        let data = Data("{\"text\":\"نص\"}".utf8)
        let id = SummaryRunner.notificationID(data)
        XCTAssertNotNil(UUID(uuidString: id))
        XCTAssertEqual(id, SummaryRunner.notificationID(data))
    }
}
