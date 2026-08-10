import XCTest
@testable import TrueFrame

final class FeedbackPriorityTests: XCTestCase {

    private func frame(roll: Double = 0,
                       sharp: Sharpness = .sharp,
                       motion: Bool = false,
                       exposure: ExposureState = .good,
                       obstruction: ObstructionResult = .init(),
                       framing: FramingResult = .init(),
                       sky: Double = 0, ground: Double = 0) -> FrameAnalysis {
        FrameAnalysis(level: LevelReading(rollDegrees: roll, pitchDegrees: 0),
                      sharpness: sharp, motionHigh: motion, exposure: exposure,
                      obstruction: obstruction, framing: framing, skyFraction: sky, groundFraction: ground)
    }

    func testLevelSceneReportsOk() {
        let m = GuidanceRules.topMessage(frame(roll: 0.2))
        XCTAssertEqual(m.priority, .status)
        XCTAssertEqual(m.key, "ok")
    }

    func testSevereTiltIsTiltKey() {
        let m = GuidanceRules.topMessage(frame(roll: 14))
        XCTAssertEqual(m.priority, .severeTilt)
        XCTAssertEqual(m.key, "tilt")
        XCTAssertTrue(m.text.lowercased().contains("left")) // clockwise -> rotate left
    }

    func testObstructionIsHighestPriority() {
        // Even with a big tilt, a covered lens wins.
        let m = GuidanceRules.topMessage(frame(roll: 20,
            obstruction: ObstructionResult(isObstructed: true, region: .lowerLeft, confidence: 0.9)))
        XCTAssertEqual(m.priority, .safety)
        XCTAssertEqual(m.key, "obstruction")
    }

    func testMostlySkyGuidance() {
        let m = GuidanceRules.topMessage(frame(sky: 0.9))
        XCTAssertEqual(m.priority, .majorFraming)
        XCTAssertEqual(m.key, "mostlySky")
    }

    func testThrottleSuppressesRepeat() {
        var t = GuidanceThrottle()
        let msg = GuidanceMessage(.severeTilt, "Rotate left.", key: "tilt", level: 1)
        XCTAssertNotNil(t.admit(msg, now: 100))          // first time speaks
        XCTAssertNil(t.admit(msg, now: 101.5))            // same key+level -> silent
    }

    func testThrottleReannouncesOnSeverityChange() {
        var t = GuidanceThrottle()
        _ = t.admit(GuidanceMessage(.severeTilt, "a", key: "tilt", level: 1), now: 100)
        let changed = t.admit(GuidanceMessage(.severeTilt, "b", key: "tilt", level: 3), now: 102)
        XCTAssertNotNil(changed)                          // severity changed -> speaks
    }

    func testThrottleRespectsMinInterval() {
        var t = GuidanceThrottle()
        _ = t.admit(GuidanceMessage(.exposure, "x", key: "exposure", level: 2), now: 100)
        XCTAssertNil(t.admit(GuidanceMessage(.blur, "y", key: "blur"), now: 100.5)) // too soon
    }
}
