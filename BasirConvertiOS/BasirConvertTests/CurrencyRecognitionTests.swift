import XCTest
@testable import BasirConvert

/// The rules that decide when the currency reader speaks. A wrong value is
/// worse than silence, so every case that should stay quiet is pinned here.
final class CurrencyRecognitionTests: XCTestCase {
    private func frame(_ note: RiyalNote?, _ confidence: Double, at time: TimeInterval,
                       printed: Set<RiyalNote> = []) -> CurrencyObservation {
        CurrencyObservation(note: note, confidence: confidence, printed: printed, time: time)
    }

    func testThreeConfidentAgreeingFramesNameTheNoteOnce() {
        var voter = CurrencyVoter()
        XCTAssertNil(voter.add(frame(.hundred, 0.95, at: 0)))
        XCTAssertNil(voter.add(frame(.hundred, 0.97, at: 0.1)))
        XCTAssertEqual(voter.add(frame(.hundred, 0.96, at: 0.2)), .note(.hundred))
        // Still in view: not repeated.
        XCTAssertNil(voter.add(frame(.hundred, 0.96, at: 0.3)))
        XCTAssertNil(voter.add(frame(.hundred, 0.96, at: 1.5)))
    }

    func testDisagreeingFramesStayUncertain() {
        var voter = CurrencyVoter()
        _ = voter.add(frame(.hundred, 0.95, at: 0))
        _ = voter.add(frame(.fiveHundred, 0.95, at: 0.1))
        XCTAssertEqual(voter.add(frame(.hundred, 0.95, at: 0.2)), .uncertain)
    }

    func testLowConfidenceIsNeverSpoken() {
        var voter = CurrencyVoter()
        for index in 0..<6 { XCTAssertNotEqual(voter.add(frame(.fifty, 0.7, at: Double(index) / 10)), .note(.fifty)) }
    }

    func testThePrintedNumberVetoesAContradictingModel() {
        var voter = CurrencyVoter()
        _ = voter.add(frame(.ten, 0.99, at: 0, printed: [.hundred]))
        _ = voter.add(frame(.ten, 0.99, at: 0.1))
        XCTAssertEqual(voter.add(frame(.ten, 0.99, at: 0.2)), .uncertain)
    }

    func testThePrintedNumberConfirmsASlightlyLessConfidentModel() {
        var voter = CurrencyVoter()
        _ = voter.add(frame(.twoHundred, 0.75, at: 0, printed: [.twoHundred]))
        _ = voter.add(frame(.twoHundred, 0.78, at: 0.1))
        XCTAssertEqual(voter.add(frame(.twoHundred, 0.8, at: 0.2)), .note(.twoHundred))
    }

    func testANoteTakenAwayAndShownAgainIsNamedAgain() {
        var voter = CurrencyVoter()
        for time in [0.0, 0.1, 0.2] { _ = voter.add(frame(.five, 0.95, at: time)) }
        for time in [0.5, 1.0, 1.6] { _ = voter.add(frame(nil, 0, at: time)) }
        _ = voter.add(frame(.five, 0.95, at: 1.7))
        _ = voter.add(frame(.five, 0.95, at: 1.8))
        XCTAssertEqual(voter.add(frame(.five, 0.95, at: 1.9)), .note(.five))
    }

    func testWhileAddingUpTurningANoteOverDoesNotCountItTwice() {
        var voter = CurrencyVoter()
        voter.reshowGap = 2
        for time in [0.0, 0.1, 0.2] { _ = voter.add(frame(.fifty, 0.95, at: time)) }
        // Turned over: the back is not recognised for a second and a half.
        for time in [0.5, 1.0, 1.7] { _ = voter.add(frame(nil, 0, at: time)) }
        _ = voter.add(frame(.fifty, 0.95, at: 1.8))
        _ = voter.add(frame(.fifty, 0.95, at: 1.9))
        XCTAssertNil(voter.add(frame(.fifty, 0.95, at: 2.0)))
    }

    func testTotalsAgreeWithTheirNumber() {
        XCTAssertEqual(RiyalAmount.arabic(8), "8 ريالات")
        XCTAssertEqual(RiyalAmount.arabic(70), "70 ريالًا")
        XCTAssertEqual(RiyalAmount.arabic(100), "100 ريال")
        XCTAssertEqual(RiyalAmount.arabic(105), "105 ريالات")
        XCTAssertEqual(RiyalAmount.arabic(150), "150 ريالًا")
        XCTAssertEqual(RiyalAmount.english(1), "1 riyal")
        XCTAssertEqual(RiyalAmount.english(70), "70 riyals")
    }

    func testPrintedValuesIgnoreSerialNumbersAndReadArabicDigitsAndWords() {
        XCTAssertEqual(PrintedValue.notes(in: ["123456789", "SAMA"]), [])
        XCTAssertEqual(PrintedValue.notes(in: ["١٠٠"]), [.hundred])
        XCTAssertEqual(PrintedValue.notes(in: ["خمسمائة ريال"]), [.fiveHundred])
        XCTAssertEqual(PrintedValue.notes(in: ["مائتا ريال", "200"]), [.twoHundred])
        XCTAssertEqual(PrintedValue.notes(in: ["FIFTY RIYALS", "50"]), [.fifty])
    }

    func testEachNoteHasItsOwnHapticCount() {
        XCTAssertEqual(Set(RiyalNote.allCases.map(\.hapticTaps)).count, RiyalNote.allCases.count)
        XCTAssertEqual(RiyalNote(label: "200"), .twoHundred)
        XCTAssertNil(RiyalNote(label: "none"))
    }
}
