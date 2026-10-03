import XCTest
@testable import BasirConvert

final class JobPresentationTests: XCTestCase {
    func testStagesMapToTheFiveNamedSteps() {
        XCTAssertEqual(JobStep.current(for: .init(current: 0, total: 0, stage: .preparing, detail: nil)), .upload)
        XCTAssertEqual(JobStep.current(for: .init(current: 0, total: 0, stage: .uploading, detail: nil)), .upload)
        XCTAssertEqual(JobStep.current(for: .init(current: 3, total: 10, stage: .processing, detail: nil)), .read)
        XCTAssertEqual(JobStep.current(for: .init(current: 10, total: 10, stage: .processing, detail: nil)), .verify)
        XCTAssertEqual(JobStep.current(for: .init(current: 0, total: 0, stage: .finalising, detail: nil)), .writeWord)
        XCTAssertEqual(JobStep.current(for: .init(current: 0, total: 0, stage: .downloading, detail: nil)), .download)
        XCTAssertNil(JobStep.current(for: .init(current: 1, total: 1, stage: .done, detail: nil)))
    }

    func testOverallPercentNeverMovesBackwardsAcrossSteps() {
        let sequence: [ConversionProgress] = [
            .init(current: 0, total: 0, stage: .uploading, detail: nil, transferredBytes: 50, totalBytes: 100),
            .init(current: 0, total: 0, stage: .uploading, detail: nil, transferredBytes: 100, totalBytes: 100),
            .init(current: 1, total: 10, stage: .processing, detail: nil),
            .init(current: 9, total: 10, stage: .processing, detail: nil),
            .init(current: 10, total: 10, stage: .processing, detail: nil),
            .init(current: 0, total: 0, stage: .downloading, detail: nil, transferredBytes: 10, totalBytes: 100),
            .init(current: 0, total: 0, stage: .downloading, detail: nil, transferredBytes: 100, totalBytes: 100)
        ]
        var previous = -1
        for progress in sequence {
            let percent = JobStep.overallPercent(for: progress)
            XCTAssertGreaterThanOrEqual(percent, previous, "\(progress)")
            XCTAssertLessThanOrEqual(percent, 99)
            previous = percent
        }
        XCTAssertEqual(JobStep.overallPercent(for: .init(current: 1, total: 1, stage: .done, detail: nil)), 100)
    }

    func testQualityScoreAcceptsFractionAndPercentScales() {
        var report = QualityReport(score: 0.934, warnings: [], sourcePages: 10, retainedPages: 10,
                                   skippedBlankPages: 0, fallbackPages: 0, tables: 2, images: 3,
                                   imagesMissingDescription: 0, textCharacters: 1_200,
                                   wordPackageVerified: true)
        XCTAssertEqual(report.percentScore, 93)
        XCTAssertFalse(report.hasConcerns)
        report.score = 88
        XCTAssertEqual(report.percentScore, 88)
        report.fallbackPages = 1
        XCTAssertTrue(report.hasConcerns)
    }

    func testJobsSavedByVersion3Decode() throws {
        // A 3.0 job record has no quality report; it must still load.
        let json = """
        {"id":"7B1C7A58-6D2C-4E3A-9E54-0F3B7B0B3A11","sourcePath":"/tmp/a.pdf","sourceName":"a.pdf",
         "options":{"operation":"convert","outputMode":"full","embedVisuals":true,"includeMath":false,
         "preserveSymbols":true,"interfaceLanguage":"ar","pdfQuality":"balanced","pageSelection":"",
         "includeSpeakerNotes":true,"includeHiddenSlides":false,"preserveLinks":true,"skipBlankPages":true,
         "preferPDFText":true,"concurrentPages":3,"rotationCorrection":0,"preferredModel":"auto"},
         "status":"completed",
         "progress":{"current":1,"total":1,"stage":"done","transferredBytes":0,"totalBytes":0,"succeeded":1,"failed":0},
         "failedItems":[],"skippedBlankItems":[],"requestID":"request-123456",
         "createdAt":0,"updatedAt":0}
        """
        let job = try JSONDecoder().decode(BasirJob.self, from: Data(json.utf8))
        XCTAssertNil(job.qualityReport)
        XCTAssertEqual(job.status, .completed)
    }
}

final class ProgressNotificationTests: XCTestCase {
    func testEachTenPercentStepIsReportedOnceAndBannersAtMilestones() {
        var bucket = 0
        var banners: [Int] = []
        var reported: [Int] = []
        for percent in [3, 9, 10, 14, 19, 20, 35, 49, 50, 51, 66, 79, 80, 95, 99, 100] {
            guard let decision = OperationFeedback.progressDecision(previousBucket: bucket, percent: percent) else { continue }
            bucket = decision.bucket
            reported.append(decision.bucket)
            if decision.showsBanner { banners.append(decision.bucket) }
        }
        XCTAssertEqual(reported, [10, 20, 30, 40, 50, 60, 70, 80, 90])
        XCTAssertEqual(banners, [20, 50, 80])
    }

    func testJumpOverMilestoneStillShowsBanner() {
        let decision = OperationFeedback.progressDecision(previousBucket: 10, percent: 63)
        XCTAssertEqual(decision?.bucket, 60)
        XCTAssertEqual(decision?.showsBanner, true)
        XCTAssertNil(OperationFeedback.progressDecision(previousBucket: 60, percent: 65))
    }
}

final class PublicLinkTests: XCTestCase {
    func testLegalPagesOpenOnTheSecureWebsiteInTheInterfaceLanguage() throws {
        let terms = try XCTUnwrap(BasirPublicLinks.url("/legal/terms", isArabic: true))
        XCTAssertEqual(terms.scheme, "https")
        XCTAssertEqual(terms.path, "/legal/terms")
        XCTAssertEqual(terms.query, "lang=ar")
        let privacy = try XCTUnwrap(BasirPublicLinks.url("/legal/privacy", isArabic: false))
        XCTAssertEqual(privacy.query, "lang=en")
    }
}
