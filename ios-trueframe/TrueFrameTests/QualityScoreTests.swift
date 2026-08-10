import XCTest
@testable import TrueFrame

final class QualityScoreTests: XCTestCase {

    func testGoodFrameScoresHigh() {
        let a = FrameAnalysis(level: LevelReading(rollDegrees: 0.3, pitchDegrees: 0),
                              sharpness: .sharp, motionHigh: false, exposure: .good)
        let s = QualityScore.from(a)
        XCTAssertGreaterThan(s.total, 88)
        XCTAssertEqual(s.obstruction, 100)
    }

    func testTiltLowersLevelness() {
        let level = QualityScore.from(FrameAnalysis(level: LevelReading(rollDegrees: 0, pitchDegrees: 0)))
        let tilted = QualityScore.from(FrameAnalysis(level: LevelReading(rollDegrees: 10, pitchDegrees: 0)))
        XCTAssertGreaterThan(level.levelness, tilted.levelness)
    }

    func testBlurDominatesScore() {
        // A severely blurry but otherwise-perfect frame must drop well below a
        // sharp one (sharp ~92): blur is the heaviest-weighted component.
        let sharp = QualityScore.from(FrameAnalysis(level: LevelReading(rollDegrees: 0, pitchDegrees: 0), sharpness: .sharp)).total
        let blurry = QualityScore.from(FrameAnalysis(level: LevelReading(rollDegrees: 0, pitchDegrees: 0), sharpness: .severelyBlurry)).total
        XCTAssertLessThan(blurry, 75)
        XCTAssertLessThan(blurry, sharp - 15)
    }

    func testClippingLowersFraming() {
        let clipped = FramingResult(personCount: 1, primarySubject: CGRect(x: 0.3, y: -0.01, width: 0.4, height: 0.9), clippedTop: true)
        let a = FrameAnalysis(level: LevelReading(rollDegrees: 0, pitchDegrees: 0), framing: clipped)
        XCTAssertLessThan(QualityScore.from(a).framing, 90)
    }

    func testObstructionZeroesOutObstructionComponent() {
        let a = FrameAnalysis(level: LevelReading(rollDegrees: 0, pitchDegrees: 0),
                              obstruction: ObstructionResult(isObstructed: true, region: .lowerLeft, confidence: 0.95))
        XCTAssertLessThanOrEqual(QualityScore.from(a).obstruction, 10)
    }
}
