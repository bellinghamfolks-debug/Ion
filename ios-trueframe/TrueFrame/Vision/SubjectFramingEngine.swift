import Foundation
import Vision
import CoreVideo
import CoreGraphics

/// Composition analysis for people, faces, and visually salient non-human
/// subjects. No identity or biometric recognition is performed.
public struct SubjectFramingEngine {

    private let edgeThreshold: CGFloat = 0.025

    public func analyze(_ buffer: CVPixelBuffer,
                        orientation: CGImagePropertyOrientation = .up) -> FramingResult {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer,
                                            orientation: orientation,
                                            options: [:])

        let humanRequest = VNDetectHumanRectanglesRequest()
        if #available(iOS 15.0, *) {
            humanRequest.upperBodyOnly = false
        }

        let faceRequest = VNDetectFaceRectanglesRequest()
        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()

        do {
            try handler.perform([humanRequest, faceRequest, saliencyRequest])
        } catch {
            return FramingResult()
        }

        func topLeft(_ box: CGRect) -> CGRect {
            CGRect(x: box.minX,
                   y: 1 - box.maxY,
                   width: box.width,
                   height: box.height)
        }

        let people = (humanRequest.results ?? []).map { topLeft($0.boundingBox) }
        let faces = (faceRequest.results ?? []).map { topLeft($0.boundingBox) }
        let salient = saliencyRequest.results?
            .first?
            .salientObjects?
            .map { topLeft($0.boundingBox) } ?? []

        // Prefer a detected person/face because its semantics are more reliable.
        // If there is no person, use Vision saliency so objects, pets, food,
        // documents, and other common photo subjects can still receive centering
        // guidance.
        let humanPrimary = largestBox(in: people + faces)
        let salientPrimary = largestBox(in: salient)
        let primary = humanPrimary ?? salientPrimary

        var result = FramingResult(personCount: people.count,
                                   faceCount: faces.count,
                                   primarySubject: primary)

        guard let subject = primary else { return result }

        result.clippedLeft = subject.minX <= edgeThreshold
        result.clippedRight = subject.maxX >= 1 - edgeThreshold

        // Top/bottom clipping warnings are only semantically strong for people.
        // Saliency boxes can legitimately touch an image edge, so do not call
        // that a clipped head or feet when no person was detected.
        if humanPrimary != nil {
            result.clippedTop = subject.minY <= edgeThreshold
            result.clippedBottom = subject.maxY >= 1 - edgeThreshold
        }

        return result
    }

    private func largestBox(in boxes: [CGRect]) -> CGRect? {
        boxes.max { lhs, rhs in
            lhs.width * lhs.height < rhs.width * rhs.height
        }
    }
}
