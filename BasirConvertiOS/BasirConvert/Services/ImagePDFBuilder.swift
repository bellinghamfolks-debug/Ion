import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Builds one PDF from many images without holding them in memory: each
/// image is read from disk at the size it needs, drawn as one page and
/// released before the next, so hundreds of photos work on any iPhone.
/// The result stays within the server's upload limit: when the first pass is
/// too large, the pages are rebuilt one quality step lower.
enum ImagePDFBuilder {
    /// Pages in one PDF.
    static let maximumImages = 1_000

    enum PageSize: String, CaseIterable, Identifiable, Sendable {
        /// Each page takes the shape of its image.
        case fit
        case a4
        case letter
        var id: String { rawValue }

        /// Portrait size in points; nil for `.fit`.
        var portrait: CGSize? {
            switch self {
            case .fit: return nil
            case .a4: return CGSize(width: 595.28, height: 841.89)
            case .letter: return CGSize(width: 612, height: 792)
            }
        }
    }

    enum Quality: Int, CaseIterable, Identifiable, Comparable, Sendable {
        case compact = 0, standard, high
        var id: Int { rawValue }
        /// Long edge in pixels: high keeps small print and Arabic dots sharp.
        var maxPixel: CGFloat {
            switch self {
            case .high: return 3_000
            case .standard: return 2_200
            case .compact: return 1_600
            }
        }
        var jpegQuality: CGFloat {
            switch self {
            case .high: return 0.85
            case .standard: return 0.75
            case .compact: return 0.65
            }
        }
        var lower: Quality? { Quality(rawValue: rawValue - 1) }
        static func < (a: Quality, b: Quality) -> Bool { a.rawValue < b.rawValue }
    }

    struct Options: Sendable {
        var pageSize: PageSize = .fit
        var quality: Quality = .high
    }

    struct Outcome: Sendable {
        let url: URL
        let pages: Int
        /// Images that could not be read and were left out.
        let skipped: [Int]
        let bytes: Int64
        /// The quality actually used (lower than asked when the file had to shrink).
        let quality: Quality
    }

    /// Long edge of a page in points when the page follows its image.
    static let fitLongEdge: CGFloat = 842
    /// White border on A4 and Letter pages.
    static let margin: CGFloat = 18

    /// Builds the PDF, stepping the quality down until it fits the upload limit.
    static func build(
        _ images: [URL],
        name: String,
        options: Options = .init(),
        maximumBytes: Int64 = FileAccess.maximumSourceBytes,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws -> Outcome {
        guard !images.isEmpty else { throw BasirError.emptyDocument }
        guard images.count <= maximumImages else { throw BasirError.tooManyImages(images.count, maximumImages) }
        let container = try FileAccess.incomingDirectory().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let destination = container.appendingPathComponent(pdfName(name))
        var quality = options.quality
        while true {
            let skipped = try render(images, to: destination, pageSize: options.pageSize, quality: quality, progress: progress)
            guard skipped.count < images.count else {
                try? FileManager.default.removeItem(at: container)
                throw BasirError.invalidFileContent
            }
            let bytes = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
            if bytes <= maximumBytes {
                try? (destination as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
                return Outcome(url: destination, pages: images.count - skipped.count, skipped: skipped, bytes: bytes, quality: quality)
            }
            guard let lower = quality.lower else {
                try? FileManager.default.removeItem(at: container)
                throw BasirError.fileTooLarge(bytes)
            }
            quality = lower
        }
    }

    /// Writes one page per image; returns the 1-based numbers of images skipped.
    static func render(
        _ images: [URL],
        to destination: URL,
        pageSize: PageSize,
        quality: Quality,
        progress: (@Sendable (Int, Int) -> Void)?
    ) throws -> [Int] {
        var skipped: [Int] = []
        var cancelled = false
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: PageSize.a4.portrait!),
                                             format: UIGraphicsPDFRendererFormat())
        try renderer.writePDF(to: destination) { context in
            for (index, url) in images.enumerated() {
                if Task.isCancelled { cancelled = true; break }
                autoreleasepool {
                    defer { progress?(index + 1, images.count) }
                    guard let image = pageImage(url, quality: quality) else {
                        skipped.append(index + 1)
                        return
                    }
                    let imageSize = CGSize(width: image.width, height: image.height)
                    let page = pageRect(for: imageSize, pageSize: pageSize)
                    context.beginPage(withBounds: page, pageInfo: [:])
                    let inset = pageSize == .fit ? page : page.insetBy(dx: margin, dy: margin)
                    UIImage(cgImage: image).draw(in: aspectFit(imageSize, in: inset))
                }
            }
        }
        if cancelled {
            try? FileManager.default.removeItem(at: destination)
            throw CancellationError()
        }
        return skipped
    }

    /// The page for an image: its own shape, or A4/Letter turned to match it.
    static func pageRect(for image: CGSize, pageSize: PageSize) -> CGRect {
        let landscape = image.width > image.height
        if let portrait = pageSize.portrait {
            let size = landscape ? CGSize(width: portrait.height, height: portrait.width) : portrait
            return CGRect(origin: .zero, size: size)
        }
        let longSide = max(image.width, image.height, 1)
        let scale = fitLongEdge / longSide
        return CGRect(x: 0, y: 0, width: (image.width * scale).rounded(), height: (image.height * scale).rounded())
    }

    static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2,
                      width: fitted.width, height: fitted.height)
    }

    /// The image upright, on white, at most `maxPixel` on its long edge, kept
    /// as JPEG data so the PDF embeds it compressed.
    static func pageImage(_ url: URL, quality: Quality) -> CGImage? {
        guard let scaled = downsample(url, maxPixel: quality.maxPixel),
              let flat = flattenedOnWhite(scaled) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, flat, [kCGImageDestinationLossyCompressionQuality: quality.jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination), let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Reads an image from disk at a reduced size, turned the right way up,
    /// without decoding the full-size picture first.
    static func downsample(_ url: URL, maxPixel: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Transparent areas (PNG screenshots, stickers) become white, not black.
    private static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// A safe file name that ends in .pdf.
    static func pdfName(_ name: String) -> String {
        var stem = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if stem.lowercased().hasSuffix(".pdf") { stem = String(stem.dropLast(4)) }
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters).union(.newlines)
        stem = stem.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespaces))
        if stem.isEmpty { stem = "صور" }
        return String(stem.prefix(120)) + ".pdf"
    }
}
