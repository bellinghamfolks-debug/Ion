import Foundation
import PDFKit
import UIKit
import Vision
import CoreImage

final class PDFPageExtractor: @unchecked Sendable {
    let document: PDFDocument
    let sourceURL: URL

    init(url: URL) throws {
        sourceURL = url
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PDFExtractionError.fileMissing
        }
        guard let document = PDFDocument(url: url) else {
            throw PDFExtractionError.cannotOpen
        }
        if document.isEncrypted && document.isLocked {
            throw PDFExtractionError.passwordProtected
        }
        self.document = document
    }

    var pageCount: Int { document.pageCount }

    func pageData(at index: Int) throws -> Data {
        guard (0..<document.pageCount).contains(index),
              let page = document.page(at: index) else {
            throw PDFExtractionError.missingPage(index + 1)
        }
        let single = PDFDocument()
        if let copy = page.copy() as? PDFPage {
            single.insert(copy, at: 0)
        } else {
            single.insert(page, at: 0)
        }
        guard let data = single.dataRepresentation(), !data.isEmpty else {
            throw PDFExtractionError.cannotSerialize(index + 1)
        }
        return data
    }

    func nativeText(at index: Int) -> String {
        guard (0..<document.pageCount).contains(index) else { return "" }
        return document.page(at: index)?.string?
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func pageSize(at index: Int) -> CGSize {
        guard (0..<document.pageCount).contains(index),
              let page = document.page(at: index) else {
            return CGSize(width: 595.3, height: 841.9)
        }
        let bounds = page.bounds(for: .mediaBox)
        let rotation = ((page.rotation % 360) + 360) % 360
        if rotation == 90 || rotation == 270 {
            return CGSize(width: abs(bounds.height), height: abs(bounds.width))
        }
        return CGSize(width: abs(bounds.width), height: abs(bounds.height))
    }


    /// Uses a small raster preview to distinguish a genuinely blank page from a scanned/image-only page.
    /// The threshold is intentionally strict: uncertain pages are sent to Gemini rather than treated as blank.
    func isProbablyBlank(at index: Int) -> Bool {
        guard (0..<document.pageCount).contains(index),
              let page = document.page(at: index) else { return false }

        let displayedSize = pageSize(at: index)
        let width = 96
        let height = max(24, min(160, Int((CGFloat(width) * displayedSize.height / max(1, displayedSize.width)).rounded())))
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 255, count: height * bytesPerRow)

        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return true }
        let rendered = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }

            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.saveGState()
            let scale = min(CGFloat(width) / bounds.width, CGFloat(height) / bounds.height)
            let drawWidth = bounds.width * scale
            let drawHeight = bounds.height * scale
            context.translateBy(x: (CGFloat(width) - drawWidth) / 2, y: (CGFloat(height) - drawHeight) / 2)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -bounds.minX, y: -bounds.minY)
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
            return true
        }
        guard rendered else { return false }

        var sampled = 0
        var darkPixels = 0
        var totalDarkness = 0.0
        for y in stride(from: 1, to: height, by: 3) {
            for x in stride(from: 1, to: width, by: 3) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let red = Double(pixels[offset])
                let green = Double(pixels[offset + 1])
                let blue = Double(pixels[offset + 2])
                let alpha = Double(pixels[offset + 3]) / 255.0
                let luminance = (0.2126 * red + 0.7152 * green + 0.0722 * blue) * alpha + 255.0 * (1 - alpha)
                let darkness = max(0, 255.0 - luminance)
                totalDarkness += darkness
                sampled += 1
                if darkness > 18 { darkPixels += 1 }
            }
        }

        guard sampled > 0 else { return false }
        let darkFraction = Double(darkPixels) / Double(sampled)
        let meanDarkness = totalDarkness / Double(sampled)
        return darkFraction < 0.0015 && meanDarkness < 0.8
    }

    /// Renders the displayed page as a high-resolution PNG. Gemini receives both
    /// the original single-page PDF and this raster view so faint print and handwriting
    /// are not limited by the PDF renderer's default document resolution.
    func highResolutionPageImage(at index: Int, longEdge: CGFloat = 2800) throws -> Data {
        guard (0..<document.pageCount).contains(index),
              let page = document.page(at: index) else {
            throw PDFExtractionError.missingPage(index + 1)
        }
        let displayed = pageSize(at: index)
        guard displayed.width > 0, displayed.height > 0 else {
            throw PDFExtractionError.cannotRenderImage(index + 1)
        }
        let scale = longEdge / max(displayed.width, displayed.height)
        let target = CGSize(
            width: max(1, (displayed.width * scale).rounded()),
            height: max(1, (displayed.height * scale).rounded())
        )
        let image = page.thumbnail(of: target, for: .mediaBox)
        guard image.size.width >= 2,
              image.size.height >= 2,
              let data = image.pngData(),
              !data.isEmpty else {
            throw PDFExtractionError.cannotRenderImage(index + 1)
        }
        return data
    }

    /// Creates four overlapping high-resolution detail crops from the rendered page.
    /// The crops are sent only during adjudication for handwriting, scans or disputed
    /// readings so small strokes receive more effective visual resolution.
    func detailTiles(from pageImageData: Data, overlapFraction: CGFloat = 0.08) -> [Data] {
        guard let image = UIImage(data: pageImageData),
              let cgImage = image.cgImage,
              cgImage.width >= 200,
              cgImage.height >= 200 else { return [] }

        let fullWidth = CGFloat(cgImage.width)
        let fullHeight = CGFloat(cgImage.height)
        let baseWidth = fullWidth / 2
        let baseHeight = fullHeight / 2
        let padX = baseWidth * max(0, min(0.20, overlapFraction))
        let padY = baseHeight * max(0, min(0.20, overlapFraction))
        var results: [Data] = []
        results.reserveCapacity(4)

        for row in 0..<2 {
            for column in 0..<2 {
                let raw = CGRect(
                    x: CGFloat(column) * baseWidth - padX,
                    y: CGFloat(row) * baseHeight - padY,
                    width: baseWidth + padX * 2,
                    height: baseHeight + padY * 2
                )
                let rect = raw.integral.intersection(CGRect(x: 0, y: 0, width: fullWidth, height: fullHeight))
                guard rect.width >= 100,
                      rect.height >= 100,
                      let cropped = cgImage.cropping(to: rect),
                      let data = UIImage(cgImage: cropped).pngData(),
                      !data.isEmpty else { continue }
                results.append(data)
            }
        }
        return results
    }

    /// Produces an on-device OCR reference. It is never treated as ground truth;
    /// it is supplied to the independent Gemini passes as another piece of evidence.
    /// This is especially useful for scans, faint pages and handwriting where PDFKit
    /// exposes no native text layer.
    func localOCRReference(at index: Int, pageImageData: Data? = nil) -> LocalOCRReference {
        autoreleasepool {
            let imageData: Data
            do {
                imageData = try pageImageData ?? highResolutionPageImage(at: index, longEdge: 3_200)
            } catch {
                return .empty
            }
            guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
                return .empty
            }

            var candidates = [recognizeText(in: cgImage)]
            if let enhanced = enhancedOCRImage(from: cgImage) {
                candidates.append(recognizeText(in: enhanced))
            }
            // A photographed or skewed sheet often occupies a rotated quadrilateral
            // inside the PDF page. Rectify that sheet before OCR so page T15-style
            // scans are read rather than guessed.
            if let corrected = perspectiveCorrectedOCRImage(from: cgImage) {
                candidates.append(recognizeText(in: corrected))
                if let correctedEnhanced = enhancedOCRImage(from: corrected) {
                    candidates.append(recognizeText(in: correctedEnhanced))
                }
            }
            return candidates.max { lhs, rhs in
                ocrUtility(lhs) < ocrUtility(rhs)
            } ?? .empty
        }
    }

    private func recognizeText(in cgImage: CGImage) -> LocalOCRReference {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.0025
        request.recognitionLanguages = ["ar-SA", "en-US"]
        if #available(iOS 16.0, *) {
            request.automaticallyDetectsLanguage = true
        }

        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } catch {
            // Some OS builds may not expose Arabic to Vision on a specific device.
            // Retry with automatic language detection rather than losing the OCR reference.
            request.recognitionLanguages = []
            do {
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            } catch {
                return .empty
            }
        }

        let observations = request.results ?? []
        let lines: [(text: String, confidence: Double, box: CGRect)] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let value = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            return (value, Double(candidate.confidence), observation.boundingBox)
        }.sorted { lhs, rhs in
            let verticalGap = abs(lhs.box.midY - rhs.box.midY)
            if verticalGap > 0.010 { return lhs.box.midY > rhs.box.midY }
            let containsArabic = XML.containsArabic(lhs.text + rhs.text)
            return containsArabic ? lhs.box.maxX > rhs.box.maxX : lhs.box.minX < rhs.box.minX
        }

        guard !lines.isEmpty else { return .empty }
        let text = lines.map(\.text).joined(separator: "\n")
        let average = lines.reduce(0.0) { $0 + $1.confidence } / Double(lines.count)
        return LocalOCRReference(text: text, averageConfidence: average)
    }


    private func perspectiveCorrectedOCRImage(from image: CGImage) -> CGImage? {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 4
        request.minimumSize = 0.22
        request.minimumAspectRatio = 0.35
        request.maximumAspectRatio = 1.0
        request.quadratureTolerance = 35
        request.minimumConfidence = 0.45

        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return nil
        }
        guard let rectangle = (request.results ?? []).max(by: { lhs, rhs in
            lhs.boundingBox.width * lhs.boundingBox.height < rhs.boundingBox.width * rhs.boundingBox.height
        }) else { return nil }

        // Ignore a rectangle that is effectively the full raster; it adds no useful
        // correction and can soften native digital pages.
        let area = rectangle.boundingBox.width * rectangle.boundingBox.height
        guard area >= 0.22, area <= 0.96 else { return nil }

        let input = CIImage(cgImage: image)
        let width = input.extent.width
        let height = input.extent.height
        func point(_ normalized: CGPoint) -> CIVector {
            CIVector(x: normalized.x * width, y: normalized.y * height)
        }

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(point(rectangle.topLeft), forKey: "inputTopLeft")
        filter.setValue(point(rectangle.topRight), forKey: "inputTopRight")
        filter.setValue(point(rectangle.bottomLeft), forKey: "inputBottomLeft")
        filter.setValue(point(rectangle.bottomRight), forKey: "inputBottomRight")
        guard let output = filter.outputImage, !output.extent.isEmpty else { return nil }
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(output, from: output.extent)
    }

    private func enhancedOCRImage(from image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let controls = CIFilter(name: "CIColorControls") else { return nil }
        controls.setValue(input, forKey: kCIInputImageKey)
        controls.setValue(0.0, forKey: kCIInputSaturationKey)
        controls.setValue(1.35, forKey: kCIInputContrastKey)
        controls.setValue(0.04, forKey: kCIInputBrightnessKey)
        guard let contrasted = controls.outputImage,
              let sharpen = CIFilter(name: "CISharpenLuminance") else { return nil }
        sharpen.setValue(contrasted, forKey: kCIInputImageKey)
        sharpen.setValue(0.45, forKey: kCIInputSharpnessKey)
        guard let output = sharpen.outputImage else { return nil }
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(output, from: output.extent)
    }

    private func ocrUtility(_ reference: LocalOCRReference) -> Double {
        let lengthBonus = min(1, Double(reference.text.count) / 1_500)
        return 0.8 * reference.averageConfidence + 0.2 * lengthBonus
    }

    func cropImage(pageIndex: Int, normalizedBox: [Double], maxRenderWidth: CGFloat = 3200) -> Data? {
        guard normalizedBox.count == 4,
              normalizedBox.allSatisfy(\.isFinite),
              let page = document.page(at: pageIndex),
              normalizedBox[2] > 0.01,
              normalizedBox[3] > 0.01 else { return nil }

        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let displayedSize = pageSize(at: pageIndex)
        let ratio = displayedSize.height / max(1, displayedSize.width)
        let target = CGSize(width: maxRenderWidth, height: maxRenderWidth * ratio)
        let image = page.thumbnail(of: target, for: .mediaBox)
        guard let cgImage = image.cgImage else { return nil }

        let padding: CGFloat = 0.006
        let rawX = CGFloat(normalizedBox[0])
        let rawY = CGFloat(normalizedBox[1])
        let rawWidth = CGFloat(normalizedBox[2])
        let rawHeight = CGFloat(normalizedBox[3])
        let x = max(0, min(1, rawX - padding))
        let y = max(0, min(1, rawY - padding))
        let width = min(1 - x, max(0, rawWidth + padding * 2))
        let height = min(1 - y, max(0, rawHeight + padding * 2))

        let cropRect = CGRect(
            x: x * CGFloat(cgImage.width),
            y: y * CGFloat(cgImage.height),
            width: width * CGFloat(cgImage.width),
            height: height * CGFloat(cgImage.height)
        ).integral.intersection(CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))

        guard cropRect.width >= 20,
              cropRect.height >= 20,
              !cropRect.isNull,
              let cropped = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: cropped).pngData()
    }
}

enum PDFExtractionError: LocalizedError {
    case fileMissing
    case cannotOpen
    case passwordProtected
    case missingPage(Int)
    case cannotSerialize(Int)
    case cannotRenderImage(Int)

    var errorDescription: String? {
        switch self {
        case .fileMissing: return L10n.text("ملف PDF المحدد لم يعد موجودًا في موقعه.")
        case .cannotOpen: return L10n.text("تعذر فتح ملف PDF. قد يكون تالفًا أو غير مدعوم.")
        case .passwordProtected: return L10n.text("ملف PDF محمي بكلمة مرور. افتحه وأزل الحماية أولًا.")
        case .missingPage(let page): return L10n.format("تعذر الوصول إلى الصفحة %d.", page)
        case .cannotSerialize(let page): return L10n.format("تعذر تجهيز الصفحة %d للإرسال.", page)
        case .cannotRenderImage(let page): return L10n.format("تعذر إنشاء صورة عالية الدقة للصفحة %d.", page)
        }
    }
}
