import Foundation
import Vision
import CoreVideo
import CoreGraphics

/// Composition-only human/face framing via Vision. No identity is computed and
/// no biometric identification is performed — boxes are used purely to describe
/// where subjects are and whether they are cut off.
public struct SubjectFramingEngine {

    private let edgeThreshold: CGFloat = 0.02   // within 2% of an edge = clipped

    public func analyze(_ buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .up) -> FramingResult {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation, options: [:])

        let humanReq = VNDetectHumanRectanglesRequest()
        if #available(iOS 15.0, *) { humanReq.upperBodyOnly = false }
        let faceReq = VNDetectFaceRectanglesRequest()

        try? handler.perform([humanReq, faceReq])

        // Vision boxes are normalized with origin BOTTOM-left; convert to top-left.
        func topLeft(_ b: CGRect) -> CGRect { CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height) }

        let people = (humanReq.results ?? []).map { topLeft($0.boundingBox) }
        let faces = (faceReq.results ?? []).map { topLeft($0.boundingBox) }

        // Primary subject = largest person box, else largest face.
        let primary = (people + faces).max(by: { $0.width * $0.height < $1.width * $1.height })

        var result = FramingResult(personCount: people.count, faceCount: faces.count, primarySubject: primary)
        if let s = primary {
            result.clippedTop = s.minY <= edgeThreshold
            result.clippedBottom = s.maxY >= 1 - edgeThreshold
            result.clippedLeft = s.minX <= edgeThreshold
            result.clippedRight = s.maxX >= 1 - edgeThreshold
        }
        return result
    }
}
