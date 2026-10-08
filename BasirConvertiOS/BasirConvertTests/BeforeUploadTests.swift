import XCTest
import CoreGraphics
@testable import BasirConvert

/// Guided capture, scan check and estimate: the pure decisions behind them.
final class BeforeUploadTests: XCTestCase {
    private func quad(_ minX: CGFloat, _ minY: CGFloat, _ maxX: CGFloat, _ maxY: CGFloat) -> DocumentQuad {
        DocumentQuad(topLeft: CGPoint(x: minX, y: minY), topRight: CGPoint(x: maxX, y: minY),
                     bottomRight: CGPoint(x: maxX, y: maxY), bottomLeft: CGPoint(x: minX, y: maxY))
    }

    // MARK: Guided capture

    func testNoPageMeansSearching() {
        XCTAssertEqual(CaptureGuidance.instruction(for: nil), .searching)
    }

    func testCentredLargePageIsReady() {
        XCTAssertEqual(CaptureGuidance.instruction(for: quad(0.1, 0.1, 0.9, 0.9)), .ready)
    }

    func testPageCutOffOnBothSidesAsksToLift() {
        XCTAssertEqual(CaptureGuidance.instruction(for: quad(0, 0.2, 1, 0.8)), .farther)
        XCTAssertEqual(CaptureGuidance.instruction(for: quad(0.2, 0, 0.8, 1)), .farther)
    }

    func testPageCutOffOnOneSideMovesTowardThatSide() {
        XCTAssertEqual(CaptureGuidance.instruction(for: quad(0, 0.2, 0.7, 0.8)), .moveLeft)
        XCTAssertEqual(CaptureGuidance.instruction(for: quad(0.3, 0.2, 1, 0.8)), .moveRight)
        XCTAssertEqual(CaptureGuidance.instruction(for: quad(0.2, 0, 0.8, 0.7)), .moveUp)
        XCTAssertEqual(CaptureGuidance.instruction(for: quad(0.2, 0.3, 0.8, 1)), .moveDown)
    }

    func testSmallCentredPageAsksToComeCloser() {
        XCTAssertEqual(CaptureGuidance.instruction(for: quad(0.35, 0.35, 0.65, 0.65)), .closer)
    }

    func testSmallOffCentrePageRecentresFirst() {
        XCTAssertEqual(CaptureGuidance.instruction(for: quad(0.05, 0.4, 0.3, 0.6)), .moveLeft)
        XCTAssertEqual(CaptureGuidance.instruction(for: quad(0.4, 0.7, 0.6, 0.95)), .moveDown)
    }

    func testAreaIsTheShareOfTheFrame() {
        XCTAssertEqual(quad(0, 0, 0.5, 0.5).area, 0.25, accuracy: 0.0001)
    }

    func testStabilizerCapturesOnlyAfterTheHandIsStill() {
        var stabilizer = CaptureStabilizer()
        let page = quad(0.1, 0.1, 0.9, 0.9)
        let start = Date()
        XCTAssertEqual(stabilizer.update(quad: page, now: start), .speak(.holdSteady))
        var outputs: [CaptureStabilizer.Output] = []
        for frame in 1...stabilizer.requiredStableFrames {
            outputs.append(stabilizer.update(quad: page, now: start.addingTimeInterval(Double(frame) * 0.15)))
        }
        XCTAssertEqual(outputs.last, .capture)
        XCTAssertFalse(outputs.dropLast().contains(.capture))
    }

    func testStabilizerRestartsWhenThePageMoves() {
        var stabilizer = CaptureStabilizer()
        let start = Date()
        for frame in 0..<4 {
            _ = stabilizer.update(quad: quad(0.1, 0.1, 0.9, 0.9), now: start.addingTimeInterval(Double(frame) * 0.15))
        }
        XCTAssertGreaterThan(stabilizer.stableFrames, 0)
        _ = stabilizer.update(quad: quad(0.15, 0.15, 0.95, 0.95), now: start.addingTimeInterval(1))
        XCTAssertEqual(stabilizer.stableFrames, 0)
    }

    func testStabilizerDoesNotRepeatTheSameDirectionImmediately() {
        var stabilizer = CaptureStabilizer()
        let start = Date()
        XCTAssertEqual(stabilizer.update(quad: nil, now: start), .speak(.searching))
        XCTAssertEqual(stabilizer.update(quad: nil, now: start.addingTimeInterval(1)), .none)
        XCTAssertEqual(stabilizer.update(quad: nil, now: start.addingTimeInterval(3.5)), .speak(.searching))
    }

    // MARK: Scan check

    func testMissingPrintedPageNumberIsReported() {
        XCTAssertEqual(ScanQualityChecker.missingNumbers([(1, 1), (2, 2), (3, 4)]), [3])
    }

    func testPagesWithoutReadableNumbersAreNotMissing() {
        XCTAssertEqual(ScanQualityChecker.missingNumbers([(1, 1), (3, 3), (5, 5)]), [])
    }

    func testUnorderedOrTooFewNumbersAreNotTrusted() {
        XCTAssertNil(ScanQualityChecker.missingNumbers([(1, 5), (2, 3), (3, 9)]))
        XCTAssertNil(ScanQualityChecker.missingNumbers([(1, 1), (2, 3)]))
    }

    // MARK: Estimate

    func testOneRoundOfTextPagesIsAboutAMinute() {
        let range = TaskEstimator.seconds(units: 8, content: .textPDF, operation: .convert)
        XCTAssertEqual(range, 51...59)
    }

    func testTranslationTakesLongerThanConversion() {
        let convert = TaskEstimator.seconds(units: 100, content: .scannedPDF, operation: .convert)
        let translate = TaskEstimator.seconds(units: 100, content: .scannedPDF, operation: .translate)
        XCTAssertGreaterThan(translate.upperBound, convert.upperBound)
    }

    func testScannedPagesTakeLongerThanTextPages() {
        let text = TaskEstimator.seconds(units: 200, content: .textPDF, operation: .convert)
        let scanned = TaskEstimator.seconds(units: 200, content: .scannedPDF, operation: .convert)
        XCTAssertGreaterThan(scanned.lowerBound, text.lowerBound)
    }

    func testLongPDFSuggestsChoosingPages() {
        XCTAssertTrue(TaskEstimate(content: .textPDF, units: 200, seconds: 1...2).suggestsPageSelection)
        XCTAssertFalse(TaskEstimate(content: .textPDF, units: 12, seconds: 1...2).suggestsPageSelection)
        XCTAssertFalse(TaskEstimate(content: .audio, units: 90, seconds: 1...2).suggestsPageSelection)
    }
}
