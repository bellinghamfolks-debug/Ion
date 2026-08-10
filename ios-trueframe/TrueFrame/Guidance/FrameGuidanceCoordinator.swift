import Foundation
import CoreVideo
import Combine
import UIKit

/// The real-time guidance loop. It fuses device motion (fast) with sampled
/// vision analysis (blur / exposure / obstruction / framing), turns them into a
/// single prioritized instruction, throttles it, and speaks/haptics it. This is
/// what a blind user actually hears while aiming.
public final class FrameGuidanceCoordinator: ObservableObject {

    // Published for the UI (all values are also available via speech/haptics).
    @Published public private(set) var guidanceText: String = "Point the camera at your subject."
    @Published public private(set) var level = LevelReading(rollDegrees: 0, pitchDegrees: 0)
    @Published public private(set) var latestAnalysis: FrameAnalysis?
    @Published public var verbosity: Verbosity = .normal
    @Published public var autoCaptureEnabled = false

    public let camera = CameraManager()
    public let motion = MotionLevelManager()
    public let feedback = AccessibleFeedbackManager()

    private let frameAnalyzer = FrameAnalyzer()
    private let framingEngine = SubjectFramingEngine()
    private var throttle = GuidanceThrottle()

    private var cancellables = Set<AnyCancellable>()
    private var lastFramingRun: TimeInterval = 0
    private var lastFraming = FramingResult()
    private var readyStreak = 0

    /// Callback the UI sets to auto-trigger capture when the scene is "Ready".
    public var onAutoCapture: (() -> Void)?

    public init() {
        motion.$reading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.level = $0 }
            .store(in: &cancellables)

        camera.onFrame = { [weak self] buffer in self?.handleFrame(buffer) }
    }

    public func start() {
        motion.start()
        if camera.authorized { camera.start() } else { camera.requestAccessAndConfigure() }
    }
    public func stop() { motion.stop(); camera.stop() }

    private func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func handleFrame(_ buffer: CVPixelBuffer) {
        let fast = frameAnalyzer.analyze(buffer)

        // Vision human/face is heavier — run it at ~2 Hz.
        let t = now()
        if t - lastFramingRun > 0.5 {
            lastFramingRun = t
            lastFraming = framingEngine.analyze(buffer)
        }

        let reading = motion.reading
        let analysis = FrameAnalysis(
            level: reading,
            sharpness: fast.sharpness,
            motionHigh: motion.isShaking,
            exposure: fast.exposure,
            obstruction: fast.obstruction,
            framing: lastFraming,
            skyFraction: fast.skyFraction,
            groundFraction: fast.groundFraction)

        let message = GuidanceRules.topMessage(analysis, verbosity: verbosity)
        let sceneReady = message.priority == .status && !motion.isShaking && fast.sharpness == .sharp
        readyStreak = sceneReady ? readyStreak + 1 : 0

        DispatchQueue.main.async {
            self.latestAnalysis = analysis
            if let spoken = self.throttle.admit(message, now: t) {
                self.guidanceText = spoken.text
                if !(self.feedback.hapticFirst && spoken.priority == .status) {
                    self.feedback.speak(spoken.text, interrupt: spoken.priority.rawValue <= GuidancePriority.severeTilt.rawValue)
                }
                // Directional haptic mirrors leveling cues.
                if spoken.key == "tilt" {
                    self.feedback.play(reading.rollDegrees > 0 ? .rotateLeft : .rotateRight)
                } else if spoken.key == "ok" {
                    self.feedback.play(.level)
                }
            }
            if self.autoCaptureEnabled && self.readyStreak >= 6 {   // ~3 s stable & ready
                self.readyStreak = 0
                self.feedback.speak("Ready.", interrupt: true)
                self.feedback.play(.shutterReady)
                self.onAutoCapture?()
            }
        }
    }

    /// One-shot spoken status when the user asks "is it level?".
    public func announceStatus() {
        let a = latestAnalysis ?? FrameAnalysis(level: level)
        feedback.speak(GuidanceRules.topMessage(a, verbosity: .detailed).text, interrupt: true)
    }
}
