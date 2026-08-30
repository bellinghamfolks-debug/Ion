import Foundation
import PDFKit
import UIKit

struct RasterizedPage: @unchecked Sendable {
    let pageNumber: Int
    let image: UIImage
    let jpegData: Data
    let width: Int
    let height: Int
    let rotationDegrees: Int
    let visuallyBlank: Bool
    let inkRatio: Double
}

final class PDFRasterizer {
    private let document: PDFDocument
    private let maximumLongEdge: CGFloat

    init(url: URL, maximumLongEdge: CGFloat = 3_000) throws {
        guard let document = PDFDocument(url: url) else {
            throw BasirError.conversionFailed("The PDF could not be opened.")
        }
        if document.isEncrypted && document.isLocked {
            throw BasirError.passwordProtectedPDF
        }
        self.document = document
        self.maximumLongEdge = maximumLongEdge
    }

    var pageCount: Int { document.pageCount }

    func text(pageNumber: Int) -> String? {
        guard pageNumber >= 1, pageNumber <= pageCount else { return nil }
        return document.page(at: pageNumber - 1)?.string?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func outline() -> [(title: String, pageNumber: Int)] {
        guard let root = document.outlineRoot else { return [] }
        var result: [(String, Int)] = []
        func visit(_ node: PDFOutline) {
            if let label = node.label?.trimmingCharacters(in: .whitespacesAndNewlines),
               !label.isEmpty,
               let destination = node.destination,
               let page = destination.page {
                let index = document.index(for: page)
                if index != NSNotFound { result.append((label, index + 1)) }
            }
            for index in 0..<node.numberOfChildren {
                if let child = node.child(at: index) { visit(child) }
            }
        }
        for index in 0..<root.numberOfChildren {
            if let child = root.child(at: index) { visit(child) }
        }
        return result
    }

    func render(pageNumber: Int, additionalRotation: Int = 0) throws -> RasterizedPage {
        try Task.checkCancellation()
        guard pageNumber >= 1, pageNumber <= pageCount,
              let page = document.page(at: pageNumber - 1) else {
            throw BasirError.conversionFailed("PDF page \(pageNumber) is unavailable.")
        }

        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else {
            throw BasirError.conversionFailed("PDF page \(pageNumber) has invalid dimensions.")
        }
        let scale = min(3.2, maximumLongEdge / max(bounds.width, bounds.height))
        let size = CGSize(width: max(1, floor(bounds.width * scale)),
                          height: max(1, floor(bounds.height * scale)))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let cg = context.cgContext
            cg.saveGState()
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: scale, y: -scale)
            cg.translateBy(x: -bounds.minX, y: -bounds.minY)
            page.draw(with: .mediaBox, to: cg)
            cg.restoreGState()
        }

        let autoRotation = ImageOrientationDetector.bestRotation(for: rendered)
        let finalRotation = (autoRotation + additionalRotation) % 360
        let finalImage = finalRotation == 0 ? rendered : rendered.rotatedClockwise(degrees: finalRotation)
        let ink = ImageOrientationDetector.inkRatio(of: finalImage)
        guard let jpeg = finalImage.jpegData(compressionQuality: 0.88) else {
            throw BasirError.conversionFailed("PDF page \(pageNumber) could not be encoded.")
        }
        return RasterizedPage(
            pageNumber: pageNumber,
            image: finalImage,
            jpegData: jpeg,
            width: Int(finalImage.size.width * finalImage.scale),
            height: Int(finalImage.size.height * finalImage.scale),
            rotationDegrees: (page.rotation + finalRotation) % 360,
            visuallyBlank: ink < 0.0025,
            inkRatio: ink
        )
    }
}

private enum ImageOrientationDetector {
    private struct Score {
        let value: Double
        let ink: Double
    }

    static func bestRotation(for image: UIImage) -> Int {
        let candidates = [0, 90, 180, 270]
        var scored: [(Int, Score)] = []
        for degrees in candidates {
            let candidate = degrees == 0 ? image : image.rotatedClockwise(degrees: degrees)
            scored.append((degrees, score(candidate)))
        }
        guard let base = scored.first?.1,
              let best = scored.max(by: { $0.1.value < $1.1.value }) else { return 0 }
        if base.ink < 0.0025 || best.1.value < base.value + 0.15 { return 0 }
        return best.0
    }

    static func inkRatio(of image: UIImage) -> Double {
        score(image).ink
    }

    private static func score(_ image: UIImage) -> Score {
        guard let sample = rgbaSample(image, maximumEdge: 320) else {
            return Score(value: 0, ink: 0)
        }
        var rows = [Double](repeating: 0, count: sample.height)
        var columns = [Double](repeating: 0, count: sample.width)
        var total = 0.0
        var top = 0.0
        var bottom = 0.0
        let topLimit = max(1, Int(Double(sample.height) * 0.35))
        let bottomStart = min(sample.height - 1, Int(Double(sample.height) * 0.65))

        for y in 0..<sample.height {
            for x in 0..<sample.width {
                let offset = (y * sample.width + x) * 4
                let r = Double(sample.bytes[offset])
                let g = Double(sample.bytes[offset + 1])
                let b = Double(sample.bytes[offset + 2])
                var darkness = 255 - (0.2126 * r + 0.7152 * g + 0.0722 * b)
                if darkness < 18 { darkness = 0 }
                darkness /= 255
                rows[y] += darkness
                columns[x] += darkness
                total += darkness
                if y < topLimit { top += darkness }
                if y >= bottomStart { bottom += darkness }
            }
        }
        rows = rows.map { $0 / Double(sample.width) }
        columns = columns.map { $0 / Double(sample.height) }
        let rowVariance = normalizedVariance(rows)
        let columnVariance = normalizedVariance(columns)
        let lineScore = (rowVariance - columnVariance) / (rowVariance + columnVariance + 1e-9)
        let mean = total / Double(max(1, sample.width * sample.height))
        let topMean = top / Double(max(1, topLimit * sample.width))
        let bottomMean = bottom / Double(max(1, (sample.height - bottomStart) * sample.width))
        let topBias = max(-1, min(1, (topMean - bottomMean) / (mean + 1e-9)))
        return Score(value: 3.0 * lineScore + 0.55 * topBias, ink: mean)
    }

    private static func normalizedVariance(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance / (mean * mean + 1e-9)
    }

    private struct Sample {
        let bytes: [UInt8]
        let width: Int
        let height: Int
    }

    private static func rgbaSample(_ image: UIImage, maximumEdge: CGFloat) -> Sample? {
        let sourceSize = image.size
        let scale = min(1, maximumEdge / max(sourceSize.width, sourceSize.height))
        let width = max(1, Int(sourceSize.width * scale))
        let height = max(1, Int(sourceSize.height * scale))
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &bytes,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ), let cgImage = image.cgImage else { return nil }
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Sample(bytes: bytes, width: width, height: height)
    }
}

private extension UIImage {
    func rotatedClockwise(degrees: Int) -> UIImage {
        let normalized = ((degrees % 360) + 360) % 360
        guard normalized != 0 else { return self }
        let radians = CGFloat(normalized) * .pi / 180
        let swapsSides = normalized == 90 || normalized == 270
        let target = swapsSides
            ? CGSize(width: size.height, height: size.width)
            : size
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            let cg = context.cgContext
            cg.translateBy(x: target.width / 2, y: target.height / 2)
            cg.rotate(by: radians)
            draw(in: CGRect(x: -size.width / 2, y: -size.height / 2,
                            width: size.width, height: size.height))
        }
    }
}

