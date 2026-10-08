import Foundation
import PDFKit
import UIKit
import Vision

/// Reads a photo or a PDF on the phone, with no internet: the PDF's own text
/// where it has one, Apple's on-device text recognition otherwise. Faster and
/// fully private, though less faithful than a Basir conversion.
enum InstantReader {
    static let maximumPages = 30

    /// On-device recognition supports Arabic only on some iOS versions.
    static var supportsArabic: Bool {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let languages = (try? request.supportedRecognitionLanguages()) ?? []
        return languages.contains { $0.lowercased().hasPrefix("ar") }
    }

    struct Outcome: Sendable {
        var blocks: [ReaderBlock]
        var pagesRead: Int
        var pagesSkipped: Int
    }

    static func read(_ urls: [URL], isArabic: Bool) throws -> Outcome {
        var pages: [[String]] = []
        var skipped = 0
        for url in urls {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            if url.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(url: url) {
                for index in 0..<pdf.pageCount {
                    guard pages.count < maximumPages else { skipped += 1; continue }
                    guard let page = pdf.page(at: index) else { continue }
                    let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if text.count >= 40 {
                        pages.append(paragraphs(fromPlainText: text))
                    } else {
                        let image = page.thumbnail(of: CGSize(width: 2_000, height: 2_000), for: .mediaBox)
                        pages.append(try recognize(image))
                    }
                }
            } else if let image = UIImage(contentsOfFile: url.path) {
                guard pages.count < maximumPages else { skipped += 1; continue }
                pages.append(try recognize(image))
            }
        }
        var blocks: [ReaderBlock] = []
        for (index, paragraphs) in pages.enumerated() {
            if pages.count > 1 {
                let marker = isArabic ? "الصفحة \(index + 1)" : "Page \(index + 1)"
                blocks.append(ReaderBlock(id: blocks.count, kind: .heading(2), text: marker, pageNumber: index + 1))
            }
            for paragraph in paragraphs {
                blocks.append(ReaderBlock(id: blocks.count, kind: .paragraph, text: paragraph))
            }
        }
        return Outcome(blocks: blocks, pagesRead: pages.count, pagesSkipped: skipped)
    }

    static func paragraphs(fromPlainText text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .map { $0.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func recognize(_ image: UIImage) throws -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = supportsArabic ? ["ar-SA", "en-US"] : ["en-US"]
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: cgImage, orientation: orientation(of: image)).perform([request])
        let lines = (request.results ?? []).compactMap { observation -> Line? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return Line(text: text, box: observation.boundingBox)
        }
        return group(lines)
    }

    struct Line: Equatable {
        var text: String
        /// Normalized, origin bottom-left (Vision).
        var box: CGRect
    }

    /// Lines top to bottom, joined into paragraphs where the gap is small.
    static func group(_ lines: [Line]) -> [String] {
        let sorted = lines.sorted { $0.box.maxY > $1.box.maxY }
        guard !sorted.isEmpty else { return [] }
        let averageHeight = sorted.map(\.box.height).reduce(0, +) / CGFloat(sorted.count)
        var paragraphs: [String] = []
        var current: [String] = []
        var previous: Line?
        for line in sorted {
            if let previous, previous.box.minY - line.box.maxY > averageHeight * 0.9 {
                paragraphs.append(current.joined(separator: " "))
                current = []
            }
            current.append(line.text)
            previous = line
        }
        if !current.isEmpty { paragraphs.append(current.joined(separator: " ")) }
        return paragraphs
    }

    private static func orientation(of image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
