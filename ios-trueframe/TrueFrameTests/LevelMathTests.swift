import XCTest
@testable import TrueFrame

final class LevelMathTests: XCTestCase {
    func testPortraitLevel() {
        XCTAssertEqual(LevelMath.cardinalRelativeRoll(rawScreenAngleDegrees: 0), 0, accuracy: 0.001)
    }

    func testLandscapeLeftLevel() {
        XCTAssertEqual(LevelMath.cardinalRelativeRoll(rawScreenAngleDegrees: 90), 0, accuracy: 0.001)
    }

    func testLandscapeRightLevel() {
        XCTAssertEqual(LevelMath.cardinalRelativeRoll(rawScreenAngleDegrees: -90), 0, accuracy: 0.001)
    }

    func testUpsideDownLevel() {
        XCTAssertEqual(LevelMath.cardinalRelativeRoll(rawScreenAngleDegrees: 180), 0, accuracy: 0.001)
    }

    func testLandscapeKeepsSmallRealTilt() {
        XCTAssertEqual(LevelMath.cardinalRelativeRoll(rawScreenAngleDegrees: 92), 2, accuracy: 0.001)
        XCTAssertEqual(LevelMath.cardinalRelativeRoll(rawScreenAngleDegrees: -87), 3, accuracy: 0.001)
    }
}
