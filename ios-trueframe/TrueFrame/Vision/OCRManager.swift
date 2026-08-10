import Foundation
import Vision
import CoreGraphics

/// On-device text recognition for Arabic and English, in natural reading order.
/// Read-only: OCR NEVER modifies the photograph.
public struct OCRManager {

    public struct Line: Sendable {
        public let text: String
        public let box: CGRect        // normalized, top-left origin
        public let confidence: Float
    }

    public func recognize(_ cgImage: CGImage,
                          completion: @escaping (_ text: String, _ lines: [Line]) -> Void) {
        let request = VNRecognizeTextRequest { request, _ in
            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            var lines: [Line] = []
            for obs in observations {
                guard let top = obs.topCandidates(1).first else { continue }
                let b = obs.boundingBox
                let box = CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
                lines.append(Line(text: top.string, box: box, confidence: top.confidence))
            }
            // Reading order: top-to-bottom, then leading edge. Vision already
            // returns per-line strings with correct in-line direction (incl. RTL).
            lines.sort { a, b in
                if abs(a.box.minY - b.box.minY) > 0.02 { return a.box.minY < b.box.minY }
                return a.box.minX < b.box.minX
            }
            let joined = lines.map { $0.text }.joined(separator: "\n")
            completion(joined, lines)
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["ar", "en-US"]
        if #available(iOS 16.0, *) { request.automaticallyDetectsLanguage = true }

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do { try handler.perform([request]) }
            catch { DispatchQueue.main.async { completion("", []) } }
        }
    }
}
