import XCTest
@testable import BasirConvert

final class JobQueuePolicyTests: XCTestCase {
    private func job(_ status: JobStatus, id: UUID = UUID()) -> BasirJob {
        BasirJob(
            id: id, sourcePath: "/tmp/a.pdf", sourceName: "a.pdf", sourceMetadata: nil,
            options: ConversionOptions(operation: .convert, outputMode: .full, targetLanguage: nil,
                                       embedVisuals: true, includeMath: false, interfaceLanguage: .arabic),
            status: status,
            progress: ConversionProgress(current: 0, total: 10, stage: .preparing, detail: nil),
            resultPath: nil, diagnosticPath: nil, errorMessage: nil, failedItems: [], skippedBlankItems: [],
            requestID: "request-123456", createdAt: Date(), updatedAt: Date(), startedAt: nil,
            completedAt: nil, automaticResumePending: nil, executedModel: nil, qualityReport: nil
        )
    }

    func testNextTaskFollowsTheQueueOrderUnlessAPreferredOneCanRun() {
        let preferred = UUID()
        let jobs = [job(.completed), job(.waitingForNetwork), job(.queued, id: preferred), job(.paused)]
        XCTAssertEqual(JobQueuePolicy.nextIndex(in: jobs), 1)
        XCTAssertEqual(JobQueuePolicy.nextIndex(in: jobs, preferred: preferred), 2)
        // A preferred task that cannot run does not jump the queue.
        XCTAssertEqual(JobQueuePolicy.nextIndex(in: jobs, preferred: jobs[3].id), 1)
        XCTAssertNil(JobQueuePolicy.nextIndex(in: [job(.paused), job(.failed)]))
    }

    func testBarShowsTheRunningTaskFirstAndCountsOnlyUnfinishedWork() {
        let jobs = [job(.paused), job(.completed), job(.running), job(.queued)]
        XCTAssertEqual(JobQueuePolicy.barJob(in: jobs)?.id, jobs[2].id)
        XCTAssertEqual(JobQueuePolicy.barJob(in: [job(.completed), job(.paused)])?.status, .paused)
        XCTAssertNil(JobQueuePolicy.barJob(in: [job(.completed), job(.cancelled)]))
        XCTAssertEqual(JobQueuePolicy.pendingCount(in: jobs), 3)
    }

    /// A completed task leaves the Tasks list by itself; anything that can
    /// still be retried stays.
    func testCompletedTasksLeaveTheListAndEverythingElseStays() {
        let jobs = [job(.completed), job(.running), job(.partial), job(.failed), job(.cancelled), job(.completed)]
        XCTAssertEqual(JobQueuePolicy.listed(jobs).map(\.id), [jobs[1].id, jobs[2].id, jobs[3].id, jobs[4].id])
    }

    func testReorderingTheListKeepsHiddenTasksInPlace() {
        let a = job(.queued), done = job(.completed), b = job(.paused), c = job(.failed)
        let reordered = JobQueuePolicy.reordered([a, done, b, c], listedOrder: [c.id, a.id, b.id])
        XCTAssertEqual(reordered.map(\.id), [c.id, done.id, a.id, b.id])
    }

    func testLaunchSelectsUnfinishedWorkBeforeTheNewestResult() {
        let jobs = [job(.completed), job(.failed), job(.paused)]
        XCTAssertEqual(JobQueuePolicy.initialSelection(in: jobs), jobs[2].id)
        XCTAssertEqual(JobQueuePolicy.initialSelection(in: [jobs[0], jobs[1]]), jobs[0].id)
        XCTAssertNil(JobQueuePolicy.initialSelection(in: []))
    }

    func testResumeAndCancelRules() {
        XCTAssertTrue(JobQueuePolicy.resumable.contains(.partial))
        XCTAssertFalse(JobQueuePolicy.resumable.contains(.running))
        XCTAssertTrue(JobQueuePolicy.cancellable.contains(.running))
        XCTAssertFalse(JobQueuePolicy.cancellable.contains(.completed))
        XCTAssertFalse(JobQueuePolicy.mayStillRunOnServer.contains(.completed))
    }

    func testPageProgressNeverMovesBackwardsDuringProcessing() {
        let previous = ConversionProgress(current: 7, total: 20, stage: .processing, detail: "a", succeeded: 6, failed: 1)
        let late = ConversionProgress(current: 5, total: 20, stage: .processing, detail: nil, succeeded: 4, failed: 0)
        let merged = JobQueuePolicy.merged(previous: previous, update: late)
        XCTAssertEqual(merged.current, 7)
        XCTAssertEqual(merged.detail, "a")
        XCTAssertEqual(merged.succeeded, 6)
        XCTAssertEqual(merged.failed, 1)
        let forward = ConversionProgress(current: 9, total: 20, stage: .processing, detail: nil)
        XCTAssertEqual(JobQueuePolicy.merged(previous: previous, update: forward).current, 9)
        let download = ConversionProgress(current: 0, total: 0, stage: .downloading, detail: nil)
        XCTAssertEqual(JobQueuePolicy.merged(previous: previous, update: download).stage, .downloading)
    }

    func testRetryDelaysGrowAndStayBounded() {
        XCTAssertEqual((1...6).map(JobQueuePolicy.reconnectDelay), [1, 2, 4, 8, 8, 8])
        XCTAssertEqual(JobQueuePolicy.cancellationRetryDelay(attempt: 1), 4)
        XCTAssertEqual(JobQueuePolicy.cancellationRetryDelay(attempt: 50), 60)
    }

    func testProgressIsAnnouncedAtTheEdgesAndEveryFifthItem() {
        XCTAssertEqual((1...11).filter { JobQueuePolicy.shouldAnnounce(current: $0, total: 11) }, [1, 5, 10, 11])
        XCTAssertFalse(JobQueuePolicy.shouldAnnounce(current: 5, total: 0))
    }

    func testRemainingTimeComesFromTheSmoothedRate() {
        var estimator = ProgressRateEstimator()
        let id = UUID()
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertNil(estimator.remaining(jobID: id, current: 0, total: 10))
        estimator.record(jobID: id, current: 1, at: start)
        estimator.record(jobID: id, current: 3, at: start.addingTimeInterval(2))   // 1 page/s
        XCTAssertEqual(estimator.remaining(jobID: id, current: 3, total: 13) ?? 0, 10, accuracy: 0.001)
        // Time offline after a reconnect is not counted as slow processing.
        estimator.restart(jobID: id, current: 3, at: start.addingTimeInterval(600))
        estimator.record(jobID: id, current: 4, at: start.addingTimeInterval(601))
        XCTAssertEqual(estimator.rates[id] ?? 0, 1, accuracy: 0.001)
        XCTAssertNil(estimator.remaining(jobID: id, current: 13, total: 13))
    }
}

@MainActor
final class ErrorLocalizerTests: XCTestCase {
    func testNetworkWaitErrorsAreNotFailures() {
        XCTAssertTrue(ErrorLocalizer.isNetworkWait(URLError(.notConnectedToInternet)))
        XCTAssertTrue(ErrorLocalizer.isNetworkWait(BasirError.wifiRequired))
        XCTAssertFalse(ErrorLocalizer.isNetworkWait(BasirError.emptyDocument))
    }

    func testMessagesSpeakThePersonsLanguage() {
        let l10n = L10n()
        let original = l10n.language
        defer { l10n.language = original }
        l10n.language = .english
        XCTAssertEqual(ErrorLocalizer.message(for: BasirError.emptyDocument, l10n: l10n),
                       "The file contains no readable content.")
        XCTAssertTrue(ErrorLocalizer.message(for: BasirError.tooManyImages(1200, 1000), l10n: l10n)
            .contains("1200"))
        l10n.language = .arabic
        XCTAssertEqual(ErrorLocalizer.message(for: BasirError.emptyDocument, l10n: l10n),
                       "لا يحتوي الملف على محتوى قابل للقراءة.")
        XCTAssertEqual(AppViewModel.localized(BasirError.emptyDocument, l10n: l10n),
                       ErrorLocalizer.message(for: BasirError.emptyDocument, l10n: l10n))
    }
}
