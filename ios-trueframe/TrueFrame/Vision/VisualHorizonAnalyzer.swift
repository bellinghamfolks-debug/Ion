import Foundation
import Vision
import CoreVideo
import CoreGraphics
import ImageIO

public struct VisualHorizonReading: Sendable {
    public var degrees: Double
    public var confidence: Double

    public init(degrees: Double, confidence: Double) {
        self.degrees = degrees
        self.confidence = confidence
    }
}

/// Scene-based horizon detection. CoreMotion tells us how the phone is rotated;
/// Vision provides an independent cue from the photographed scene. The app uses
/// this only when Vision reports useful confidence.
public struct VisualHorizonAnalyzer {
    public func analyze(_ buffer: CVPixelBuffer,
                        orientation: CGImagePropertyOrientation = .up) -> VisualHorizonReading? {
        let request = VNDetectHorizonRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer,
                                            orientation: orientation,
                                            options: [:])
        return perform(request, handler: handler)
    }

    public func analyze(_ image: CGImage,
                        orientation: CGImagePropertyOrientation = .up) -> VisualHorizonReading? {
        let request = VNDetectHorizonRequest()
        let handler = VNImageRequestHandler(cgImage: image,
                                            orientation: orientation,
                                            options: [:])
        return perform(request, handler: handler)
    }

    private func perform(_ request: VNDetectHorizonRequest,
                         handler: VNImageRequestHandler) -> VisualHorizonReading? {
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first else { return nil }
        let degrees = Double(observation.angle) * 180 / .pi
        return VisualHorizonReading(degrees: degrees,
                                    confidence: Double(observation.confidence))
    }
}
