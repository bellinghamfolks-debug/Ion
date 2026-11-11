import Foundation
import PDFKit
import UIKit
import Vision

/// All recognition, selection and flattening occur locally. The output is
/// rasterized: drawing a black rectangle never leaves the original PDF text underneath.
enum PrivateDocumentRedactor {
    struct Finding: Identifiable, Sendable {
        let id: UUID
        let page: Int
        let text: String
        let region: CGRect
    }
    static func isSensitive(_ text: String, phrases: [String]) -> Bool {
        if phrases.contains(where: { !$0.isEmpty && text.localizedCaseInsensitiveContains($0) }) { return true }
        let normalized = text.unicodeScalars.map { scalar -> String in
            if let digit = scalar.properties.numericValue, digit >= 0, digit <= 9 { return String(Int(digit)) }
            return String(scalar)
        }.joined()
        return normalized.range(of: #"(?i)([A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}|\bSA\s*(?:\d\s*){22}\b|(?:\+?\d[\s().-]*){9,})"#, options: .regularExpression) != nil
    }
    static func image(_ source: URL, page index: Int) throws -> UIImage {
        if source.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: source), let page = document.page(at: index) else { throw BasirError.invalidResponse("Unreadable PDF page") }
            let bounds = page.bounds(for: .mediaBox)
            let scale = min(2, 2000 / max(bounds.width, bounds.height))
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            return UIGraphicsImageRenderer(size: size).image { context in
                UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
                context.cgContext.translateBy(x: 0, y: size.height)
                context.cgContext.scaleBy(x: scale, y: -scale)
                context.cgContext.translateBy(x: -bounds.minX, y: -bounds.minY)
                page.draw(with: .mediaBox, to: context.cgContext)
            }
        }
        guard let image = UIImage(contentsOfFile: source.path) else { throw BasirError.invalidResponse("Unreadable image") }
        return image
    }
    static func count(_ source: URL) throws -> Int {
        if source.pathExtension.lowercased() == "pdf" {
            guard let pdf = PDFDocument(url: source), !pdf.isLocked, pdf.pageCount > 0 else { throw BasirError.invalidResponse("Unreadable or locked PDF") }
            return pdf.pageCount
        }
        return 1
    }
    static func scan(_ source: URL, phrases: [String], progress: @Sendable (Int, Int) -> Void) throws -> [Finding] {
        let total = try count(source)
        var found: [Finding] = []
        for page in 0..<total {
            try Task.checkCancellation()
            try autoreleasepool {
                let rendered = try image(source, page: page)
                guard let cg = rendered.cgImage else { throw BasirError.invalidResponse("Unreadable image") }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                let languages = (try? request.supportedRecognitionLanguages()) ?? []
                request.recognitionLanguages = ["ar-SA", "en-US"].filter { languages.contains($0) }
                try VNImageRequestHandler(cgImage: cg).perform([request])
                for observation in request.results ?? [] {
                    guard let line = observation.topCandidates(1).first?.string,
                          isSensitive(line, phrases: phrases) else { continue }
                    found.append(Finding(id: UUID(), page: page + 1, text: line, region: observation.boundingBox))
                }
            }
            progress(page + 1, total)
        }
        return found
    }
    static func export(_ source: URL, findings: [Finding]) throws -> URL {
        let total = try count(source)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("Basir-redacted-\(UUID().uuidString).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        var renderingFailed = false
        do {
            try renderer.writePDF(to: output) { context in
                for page in 0..<total {
                    // Keep render failures fatal: never silently omit a page from a private copy.
                    context.beginPage()
                    guard let image = try? image(source, page: page) else { renderingFailed = true; continue }
                    let area = CGRect(x: 0, y: 0, width: 595, height: 842)
                    image.draw(in: area)
                    UIColor.black.setFill()
                    for finding in findings where finding.page == page + 1 {
                        let box = finding.region
                        context.cgContext.fill(CGRect(x: box.minX * area.width - 3,
                                            y: (1 - box.maxY) * area.height - 3,
                                            width: box.width * area.width + 6, height: box.height * area.height + 6))
                    }
                }
            }
            // Verify all source pages survived export.
            guard !renderingFailed, PDFDocument(url: output)?.pageCount == total else { throw BasirError.invalidResponse("Incomplete private copy") }
            return output
        } catch { try? FileManager.default.removeItem(at: output); throw error }
    }
}
