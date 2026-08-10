import XCTest
@testable import TrueFrame

final class AutoCaptureGateTests: XCTestCase {

    private func readyFrame(roll: Double = 0,
                            sharpness: Sharpness = .sharp,
                            motion: Bool = false,
                            exposure: ExposureState = .good,
                            visualHorizon: Double? = nil,
                            horizonConfidence: Double = 0) -> FrameAnalysis {
        FrameAnalysis(
            level: LevelReading(rollDegrees: roll, pitchDegrees: 0),
            sharpness: sharpness,
            motionHigh: motion,
            exposure: exposure,
            visualHorizonDegrees: visualHorizon,
            visualHorizonConfidence: horizonConfidence
        )
    }

    private func feedReady(_ gate: inout AutoCaptureGate, start: Double) -> Bool {
        XCTAssertFalse(gate.shouldCapture(readyFrame(), now: start, cameraReady: true))
        XCTAssertFalse(gate.shouldCapture(readyFrame(), now: start + 0.2, cameraReady: true))
        XCTAssertFalse(gate.shouldCapture(readyFrame(), now: start + 0.4, cameraReady: true))
        XCTAssertFalse(gate.shouldCapture(readyFrame(), now: start + 0.6, cameraReady: true))
        return gate.shouldCapture(readyFrame(), now: start + 0.81, cameraReady: true)
    }

    func testOneGoodFrameDoesNotCapture() {
        var gate = AutoCaptureGate()
        XCTAssertFalse(gate.shouldCapture(readyFrame(), now: 100, cameraReady: true))
    }

    func testStableDurationAndSampleCountTriggerExactlyOnce() {
        var gate = AutoCaptureGate()
        XCTAssertTrue(feedReady(&gate, start: 100))
        XCTAssertFalse(gate.shouldCapture(readyFrame(), now: 101.8, cameraReady: true))
    }

    func testGateRearamsOnlyAfterSceneBecomesNotReady() {
        var gate = AutoCaptureGate()
        XCTAssertTrue(feedReady(&gate, start: 100))

        XCTAssertFalse(gate.shouldCapture(readyFrame(motion: true), now: 101.0, cameraReady: true))
        XCTAssertFalse(gate.shouldCapture(readyFrame(motion: true), now: 101.7, cameraReady: true))

        XCTAssertTrue(feedReady(&gate, start: 103.4))
    }

    func testBadTechnicalQualityBlocksCapture() {
        XCTAssertFalse(AutoCaptureGate.isTechnicallyReady(readyFrame(roll: 4)))
        XCTAssertFalse(AutoCaptureGate.isTechnicallyReady(readyFrame(sharpness: .blurry)))
        XCTAssertFalse(AutoCaptureGate.isTechnicallyReady(readyFrame(motion: true)))
        XCTAssertFalse(AutoCaptureGate.isTechnicallyReady(readyFrame(exposure: .veryDark)))
        XCTAssertFalse(AutoCaptureGate.isTechnicallyReady(readyFrame(exposure: .overexposed)))
        XCTAssertTrue(AutoCaptureGate.isTechnicallyReady(readyFrame(exposure: .dark)))
    }

    func testConfidentVisualHorizonCanBlockCapture() {
        XCTAssertFalse(AutoCaptureGate.isTechnicallyReady(
            readyFrame(visualHorizon: 5, horizonConfidence: 0.9)
        ))
        XCTAssertTrue(AutoCaptureGate.isTechnicallyReady(
            readyFrame(visualHorizon: 5, horizonConfidence: 0.2)
        ))
    }
}
