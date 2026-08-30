import Foundation
import UIKit

struct PreparedImage {
    let data: Data
    let mimeType: String
    let pixelWidth: Int
    let pixelHeight: Int
}

enum VisualProcessor {
    private static let pdfCropMaximumEdge: CGFloat = 1_800
    private static let fallbackMaximumEdge: CGFloat = 1_400
    private static let presentationMaximumEdge: CGFloat = 2_400
    private static let maximumOriginalBytes = 8 * 1024 * 1024

    static func crop(page: RasterizedPage, visual: VisualSpec) -> PreparedImage? {
        guard let cgImage = page.image.cgImage else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        var left = normalizedPixel(visual.xMin, size: width)
        var top = normalizedPixel(visual.yMin, size: height)
        var right = normalizedPixel(visual.xMax, size: width)
        var bottom = normalizedPixel(visual.yMax, size: height)
        let rawWidth = right - left
        let rawHeight = bottom - top
        guard rawWidth >= 8, rawHeight >= 8 else { return nil }

        let padX = max(3, rawWidth * 0.025)
        let padY = max(3, rawHeight * 0.025)
        left = max(0, left - padX)
        top = max(0, top - padY)
        right = min(width, right + padX)
        bottom = min(height, bottom + padY)
        let rect = CGRect(x: floor(left), y: floor(top),
                          width: floor(right - left), height: floor(bottom - top))
        guard let cropped = cgImage.cropping(to: rect) else { return nil }
        let image = scaleDown(UIImage(cgImage: cropped), maximumEdge: pdfCropMaximumEdge)
        let crispKinds = ["logo", "شعار", "stamp", "ختم", "signature", "توقيع", "barcode", "qr"]
        let crisp = crispKinds.contains { visual.kind.localizedCaseInsensitiveContains($0) }
        let data = crisp ? image.pngData() : image.jpegData(compressionQuality: 0.90)
        guard let data else { return nil }
        return PreparedImage(data: data,
                             mimeType: crisp ? "image/png" : "image/jpeg",
                             pixelWidth: Int(image.size.width * image.scale),
                             pixelHeight: Int(image.size.height * image.scale))
    }

    static func fallback(page: RasterizedPage) -> PreparedImage? {
        let image = scaleDown(page.image, maximumEdge: fallbackMaximumEdge)
        guard let data = image.jpegData(compressionQuality: 0.76) else { return nil }
        return PreparedImage(data: data, mimeType: "image/jpeg",
                             pixelWidth: Int(image.size.width * image.scale),
                             pixelHeight: Int(image.size.height * image.scale))
    }

    static func presentationImage(url: URL, mimeType: String) throws -> PreparedImage? {
        let original = try Data(contentsOf: url, options: .mappedIfSafe)
        guard !original.isEmpty, let source = UIImage(data: original) else { return nil }
        let width = Int(source.size.width * source.scale)
        let height = Int(source.size.height * source.scale)
        let normalizedMime = mimeType.lowercased()
        let directlySupported = normalizedMime == "image/jpeg" || normalizedMime == "image/png"
        if directlySupported, original.count <= maximumOriginalBytes,
           max(width, height) <= Int(presentationMaximumEdge) {
            return PreparedImage(data: original, mimeType: normalizedMime,
                                 pixelWidth: width, pixelHeight: height)
        }

        let scaled = scaleDown(source, maximumEdge: presentationMaximumEdge)
        if sourceContainsAlpha(scaled), let png = scaled.pngData() {
            return PreparedImage(data: png, mimeType: "image/png",
                                 pixelWidth: Int(scaled.size.width * scaled.scale),
                                 pixelHeight: Int(scaled.size.height * scaled.scale))
        }
        guard let jpeg = scaled.jpegData(compressionQuality: 0.90) else { return nil }
        return PreparedImage(data: jpeg, mimeType: "image/jpeg",
                             pixelWidth: Int(scaled.size.width * scaled.scale),
                             pixelHeight: Int(scaled.size.height * scaled.scale))
    }

    static func prepareImportedImage(url: URL) throws -> PreparedImage {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let image = UIImage(data: data) else {
            throw BasirError.unsupportedFile(url.pathExtension)
        }
        let scaled = scaleDown(image, maximumEdge: 3_000)
        if sourceContainsAlpha(scaled), let png = scaled.pngData() {
            return PreparedImage(data: png, mimeType: "image/png",
                                 pixelWidth: Int(scaled.size.width * scaled.scale),
                                 pixelHeight: Int(scaled.size.height * scaled.scale))
        }
        guard let jpeg = scaled.jpegData(compressionQuality: 0.88) else {
            throw BasirError.conversionFailed("The image could not be encoded.")
        }
        return PreparedImage(data: jpeg, mimeType: "image/jpeg",
                             pixelWidth: Int(scaled.size.width * scaled.scale),
                             pixelHeight: Int(scaled.size.height * scaled.scale))
    }

    private static func normalizedPixel(_ value: Int, size: CGFloat) -> CGFloat {
        CGFloat(max(0, min(1_000, value))) * size / 1_000
    }

    private static func scaleDown(_ image: UIImage, maximumEdge: CGFloat) -> UIImage {
        let longEdge = max(image.size.width, image.size.height)
        guard longEdge > maximumEdge else { return image }
        let scale = maximumEdge / longEdge
        let target = CGSize(width: max(1, image.size.width * scale),
                            height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = !sourceContainsAlpha(image)
        return UIGraphicsImageRenderer(size: target, format: format).image { context in
            if format.opaque {
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: target))
            }
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    private static func sourceContainsAlpha(_ image: UIImage) -> Bool {
        guard let alpha = image.cgImage?.alphaInfo else { return false }
        return alpha == .first || alpha == .last
            || alpha == .premultipliedFirst || alpha == .premultipliedLast
    }
}

