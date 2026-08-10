import Foundation
import CoreVideo
import Combine
import UIKit
import ImageIO

/// Real-time guidance loop. Heavy image work stays off the main thread; UI,
/// speech, haptics, and auto-capture state are updated on the main queue.
public final class FrameGuidanceCoordinator: ObservableObject {

    @Published public private(set) var guidanceText: String = "Point the camera at your subject."
    @Published public private(set) var level = LevelReading(rollDegrees: 0, pitchDegrees: 0)
    @Published public private(set) var latestAnalysis: FrameAnalysis?
    @Published public private(set) var cameraReady = false
    @Published public private(set) var cameraError: String?
    @Published public var verbosity: Verbosity = .normal
    @Published public var autoCaptureEnabled = false

    public var language: String = "en"

    public let camera = CameraManager()
    public let motion = MotionLevelManager()
    public let feedback = AccessibleFeedbackManager()

    private let frameAnalyzer = FrameAnalyzer()
    private let framingEngine = SubjectFramingEngine()
    private let horizonAnalyzer = VisualHorizonAnalyzer()
    private var throttle = GuidanceThrottle()
    private var autoCaptureGate = AutoCaptureGate()

    private var cancellables = Set<AnyCancellable>()
    private var lastFramingRun: TimeInterval = 0
    private var lastFraming = FramingResult()
    private var lastHorizonRun: TimeInterval = 0
    private var horizonSamples: [VisualHorizonReading] = []
    private var stableHorizon: VisualHorizonReading?

    public var onAutoCapture: (() -> Void)?

    public init() {
        motion.$reading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reading in
                self?.level = reading
            }
            .store(in: &cancellables)

        camera.$isCaptureReady
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ready in
                self?.cameraReady = ready
            }
            .store(in: &cancellables)

        camera.$lastErrorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.cameraError = message
            }
            .store(in: &cancellables)

        camera.onFrame = { [weak self] buffer, orientation in
            self?.handleFrame(buffer, orientation: orientation)
        }
    }

    public func start() {
        guidanceText = language == "ar" ? "وجّه الكاميرا نحو ما تريد تصويره." : "Point the camera at your subject."
        throttle.reset()
        autoCaptureGate.reset()
        horizonSamples.removeAll(keepingCapacity: true)
        stableHorizon = nil
        motion.start()
        camera.startCamera()
    }

    public func stop() {
        autoCaptureGate.reset()
        horizonSamples.removeAll(keepingCapacity: true)
        stableHorizon = nil
        motion.stop()
        camera.stop()
    }

    private func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    private func handleFrame(_ buffer: CVPixelBuffer,
                             orientation: CGImagePropertyOrientation) {
        let fast = frameAnalyzer.analyze(buffer)
        let timestamp = now()

        // People/face/saliency Vision requests are heavier than luminance
        // analysis, so reuse their latest result between runs.
        if timestamp - lastFramingRun >= 0.35 {
            lastFramingRun = timestamp
            lastFraming = framingEngine.analyze(buffer, orientation: orientation)
        }

        if timestamp - lastHorizonRun >= 0.8 {
            lastHorizonRun = timestamp
            updateVisualHorizon(with: horizonAnalyzer.analyze(buffer, orientation: orientation))
        }

        let motionSnapshot = motion.snapshot()
        let motionReading = motionSnapshot.reading
        let analysis = FrameAnalysis(
            level: motionReading,
            sharpness: fast.sharpness,
            motionHigh: motionSnapshot.isShaking,
            exposure: fast.exposure,
            obstruction: fast.obstruction,
            framing: lastFraming,
            skyFraction: fast.skyFraction,
            groundFraction: fast.groundFraction,
            visualHorizonDegrees: stableHorizon?.degrees,
            visualHorizonConfidence: stableHorizon?.confidence ?? 0
        )

        let message = GuidanceRules.topMessage(analysis, verbosity: verbosity)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.latestAnalysis = analysis

            if let admitted = self.throttle.admit(message, now: timestamp) {
                let line = self.language == "ar"
                    ? GuidanceArabic.text(for: admitted,
                                          analysis: analysis,
                                          verbosity: self.verbosity)
                    : admitted.text

                self.guidanceText = line

                let hapticOnlyLeveling = self.feedback.hapticFirst && admitted.key == "tilt"
                if !hapticOnlyLeveling {
                    self.feedback.speak(
                        line,
                        interrupt: admitted.priority.rawValue <= GuidancePriority.severeTilt.rawValue
                    )
                }

                if admitted.key == "tilt" {
                    self.feedback.play(motionReading.rollDegrees > 0 ? .rotateLeft : .rotateRight)
                } else if admitted.key == "ok" {
                    self.feedback.play(.level)
                }
            }

            guard self.autoCaptureEnabled else {
                self.autoCaptureGate.reset()
                return
            }

            if self.autoCaptureGate.shouldCapture(analysis,
                                                  now: timestamp,
                                                  cameraReady: self.cameraReady) {
                let readyText = self.language == "ar"
                    ? GuidanceArabic.captureReady
                    : "Ready. Hold still. Taking the photo now."
                self.guidanceText = readyText
                self.feedback.speak(readyText, interrupt: true)
                self.feedback.play(.shutterReady)
                self.onAutoCapture?()
            }
        }
    }

    private func updateVisualHorizon(with reading: VisualHorizonReading?) {
        guard let reading else {
            horizonSamples.removeAll(keepingCapacity: true)
            stableHorizon = nil
            return
        }

        horizonSamples.append(reading)
        if horizonSamples.count > 4 {
            horizonSamples.removeFirst(horizonSamples.count - 4)
        }
        guard horizonSamples.count >= 3 else {
            stableHorizon = nil
            return
        }

        let degrees = horizonSamples.map(\.degrees)
        guard let minimum = degrees.min(), let maximum = degrees.max(),
              maximum - minimum <= 2.5 else {
            stableHorizon = nil
            return
        }

        let average = degrees.reduce(0, +) / Double(degrees.count)
        let confidence = horizonSamples.map(\.confidence).min() ?? 0
        stableHorizon = VisualHorizonReading(degrees: average, confidence: confidence)
    }

    public func announceStatus() {
        let analysis = latestAnalysis ?? FrameAnalysis(level: level)
        let message = GuidanceRules.topMessage(analysis, verbosity: .detailed)
        let line = language == "ar"
            ? GuidanceArabic.text(for: message, analysis: analysis, verbosity: .detailed)
            : message.text
        feedback.speak(line, interrupt: true)
    }
}
