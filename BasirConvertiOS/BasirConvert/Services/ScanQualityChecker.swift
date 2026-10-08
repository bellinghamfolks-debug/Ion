import Foundation
import UIKit
import PDFKit
import Vision

/// One problem found in a scanned page before it is sent.
struct ScanIssue: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case blurry, dark, blank, upsideDown, duplicate, missingPages
    }

    let kind: Kind
    /// 1-based page numbers this issue concerns.
    let pages: [Int]
    /// For duplicates: the earlier page this one repeats.
    var duplicateOf: Int?
    /// For missing pages: the printed page numbers that seem to be absent.
    var missingNumbers: [Int] = []

    var id: String { "\(kind.rawValue)-\(pages.map(String.init).joined(separator: ","))" }

    @MainActor
    func sentence(_ l10n: L10n) -> String {
        let list = pages.map(String.init).joined(separator: l10n.isArabic ? "، " : ", ")
        switch kind {
        case .blurry:
            return l10n.t("الصفحة \(list) ضبابية وقد لا تُقرأ جيدًا.", "Page \(list) is blurry and may not read well.")
        case .dark:
            return l10n.t("الصفحة \(list) معتمة. أعد التصوير بإضاءة أفضل.", "Page \(list) is too dark. Retake it with more light.")
        case .blank:
            return l10n.t("الصفحة \(list) تبدو فارغة.", "Page \(list) looks blank.")
        case .upsideDown:
            return l10n.t("الصفحة \(list) تبدو مقلوبة. سيُصححها بصير تلقائيًا.",
                          "Page \(list) looks upside down. Basir will turn it the right way.")
        case .duplicate:
            return l10n.t("الصفحة \(list) تكرار للصفحة \(duplicateOf ?? 0).",
                          "Page \(list) repeats page \(duplicateOf ?? 0).")
        case .missingPages:
            let numbers = missingNumbers.map(String.init).joined(separator: l10n.isArabic ? "، " : ", ")
            return l10n.t("قد تكون صفحات ناقصة: لم أجد الصفحات المرقّمة \(numbers).",
                          "Pages may be missing: printed page numbers \(numbers) were not found.")
        }
    }
}

struct ScanQualityReport: Equatable, Sendable {
    let pageCount: Int
    let issues: [ScanIssue]
    /// Pages that look upside down; Basir turns them before sending.
    var upsideDownPages: [Int] { issues.filter { $0.kind == .upsideDown }.flatMap(\.pages) }
    var isClean: Bool { issues.isEmpty }
}

/// Checks a scan on the device, before anything is sent: blur, darkness,
/// blank pages, upside-down pages, repeated pages and gaps in the printed
/// page numbers. Nothing here leaves the iPhone.
enum ScanQualityChecker {
    /// Images up to this long edge are analysed (enough for these checks).
    static let analysisEdge: CGFloat = 900

    static func check(url: URL, maximumPages: Int = 120) -> ScanQualityReport {
        let images = pageImages(url: url, maximumPages: maximumPages)
        var issues: [ScanIssue] = []
        var hashes: [(page: Int, hash: UInt64)] = []
        var printedNumbers: [(page: Int, number: Int)] = []
        for (index, image) in images.enumerated() {
            let page = index + 1
            guard let gray = GrayImage(image: image, maximumEdge: 400) else { continue }
            let stats = gray.statistics()
            if stats.inkRatio < 0.003 {
                issues.append(ScanIssue(kind: .blank, pages: [page]))
                continue
            }
            if stats.mean < 60 { issues.append(ScanIssue(kind: .dark, pages: [page])) }
            if gray.laplacianVariance() < blurThreshold(for: stats) {
                issues.append(ScanIssue(kind: .blurry, pages: [page]))
            }
            let hash = gray.differenceHash()
            if let earlier = hashes.first(where: { ($0.hash ^ hash).nonzeroBitCount <= 4 }) {
                var issue = ScanIssue(kind: .duplicate, pages: [page])
                issue.duplicateOf = earlier.page
                issues.append(issue)
            }
            hashes.append((page, hash))
            let reading = TextProbe.read(image)
            if reading.upsideDownScore > reading.uprightScore * 2, reading.upsideDownScore >= 20 {
                issues.append(ScanIssue(kind: .upsideDown, pages: [page]))
            }
            if let number = reading.pageNumber { printedNumbers.append((page, number)) }
        }
        if let gap = missingNumbers(printedNumbers), !gap.isEmpty {
            var issue = ScanIssue(kind: .missingPages, pages: [])
            issue.missingNumbers = gap
            issues.append(issue)
        }
        return ScanQualityReport(pageCount: images.count, issues: merge(issues))
    }

    /// Sharp text pages have strong edges; a page with little ink needs a
    /// lower bar so that a short letter is not called blurry.
    static func blurThreshold(for stats: GrayImage.Statistics) -> Double {
        stats.inkRatio < 0.03 ? 35 : 70
    }

    /// Printed page numbers that should be present between the first and last
    /// found, when the found numbers otherwise follow the scan order.
    static func missingNumbers(_ found: [(page: Int, number: Int)]) -> [Int]? {
        guard found.count >= 3 else { return nil }
        let numbers = found.map(\.number)
        // Only trust numbering that increases with the scan order.
        guard zip(numbers, numbers.dropFirst()).allSatisfy({ $0 < $1 }) else { return nil }
        let present = Set(numbers)
        let missing = (numbers.first!...numbers.last!).filter { !present.contains($0) }
        // Scanned pages without a readable number are not "missing".
        let scannedBetween = (found.last!.page - found.first!.page + 1)
        let expected = numbers.last! - numbers.first! + 1
        return expected > scannedBetween ? Array(missing.prefix(10)) : []
    }

    private static func merge(_ issues: [ScanIssue]) -> [ScanIssue] {
        var merged: [ScanIssue] = []
        for issue in issues {
            if issue.kind != .duplicate, issue.kind != .missingPages,
               let index = merged.firstIndex(where: { $0.kind == issue.kind }) {
                merged[index] = ScanIssue(kind: issue.kind, pages: merged[index].pages + issue.pages)
            } else {
                merged.append(issue)
            }
        }
        return merged
    }

    static func pageImages(url: URL, maximumPages: Int) -> [UIImage] {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        if url.pathExtension.lowercased() == "pdf" {
            guard let pdf = PDFDocument(url: url) else { return [] }
            return (0..<min(pdf.pageCount, maximumPages)).compactMap { index in
                guard let page = pdf.page(at: index) else { return nil }
                let bounds = page.bounds(for: .mediaBox)
                let scale = analysisEdge / max(bounds.width, bounds.height, 1)
                return page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
            }
        }
        guard let image = UIImage(contentsOfFile: url.path) else { return [] }
        return [image]
    }

    /// A copy with the given pages turned the right way up. PDFs keep their
    /// pages (only the rotation changes); a single image is redrawn.
    static func correctingOrientation(of url: URL, upsideDownPages pages: [Int]) throws -> URL {
        guard !pages.isEmpty else { return url }
        if url.pathExtension.lowercased() == "pdf" {
            guard let pdf = PDFDocument(url: url) else { throw BasirError.invalidFileContent }
            for number in pages {
                guard let page = pdf.page(at: number - 1) else { continue }
                page.rotation = (page.rotation + 180) % 360
            }
            guard let data = pdf.dataRepresentation() else { throw BasirError.invalidFileContent }
            let name = url.deletingPathExtension().lastPathComponent + ".pdf"
            return try FileAccess.persistImportedData(data, preferredName: name)
        }
        guard let image = UIImage(contentsOfFile: url.path), let cg = image.cgImage else { return url }
        let turned = UIImage(cgImage: cg, scale: image.scale, orientation: .down)
        let renderer = UIGraphicsImageRenderer(size: turned.size)
        let upright = renderer.image { _ in turned.draw(at: .zero) }
        guard let data = upright.jpegData(compressionQuality: 0.94) else { return url }
        return try FileAccess.persistImportedData(data, preferredName: url.lastPathComponent)
    }

    /// True when a PDF's pages carry no text layer, i.e. it is a scan or
    /// photos, so the checks above are meaningful.
    static func looksScanned(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if SupportedInput.imageExtensions.contains(ext) { return true }
        guard ext == "pdf", let pdf = PDFDocument(url: url) else { return false }
        let sample = (0..<min(pdf.pageCount, 6)).compactMap { pdf.page(at: $0)?.string }
        let characters = sample.reduce(0) { $0 + $1.trimmingCharacters(in: .whitespacesAndNewlines).count }
        return characters < 40 * max(1, sample.count)
    }
}

/// A small grayscale copy of a page for fast pixel statistics.
struct GrayImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    struct Statistics: Equatable {
        let mean: Double
        let inkRatio: Double
    }

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    init?(image: UIImage, maximumEdge: CGFloat) {
        guard let cg = image.cgImage else { return nil }
        let scale = min(1, maximumEdge / CGFloat(max(cg.width, cg.height)))
        let width = max(8, Int(CGFloat(cg.width) * scale))
        let height = max(8, Int(CGFloat(cg.height) * scale))
        var buffer = [UInt8](repeating: 0, count: width * height)
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(width: width, height: height, pixels: buffer)
    }

    func statistics() -> Statistics {
        var histogram = [Int](repeating: 0, count: 256)
        var sum = 0
        for value in pixels { histogram[Int(value)] += 1; sum += Int(value) }
        // Background: the most common brightness band (works for dark pages too).
        var bestBand = 0, bestCount = -1
        for band in 0..<32 {
            let count = histogram[band * 8..<(band * 8 + 8)].reduce(0, +)
            if count > bestCount { bestCount = count; bestBand = band }
        }
        let background = bestBand * 8 + 4
        var ink = 0
        for (value, count) in histogram.enumerated() where abs(value - background) > 40 { ink += count }
        let total = max(1, pixels.count)
        return Statistics(mean: Double(sum) / Double(total), inkRatio: Double(ink) / Double(total))
    }

    /// Variance of the Laplacian: low values mean soft, blurry edges.
    func laplacianVariance() -> Double {
        guard width > 2, height > 2 else { return 0 }
        var values: [Double] = []
        values.reserveCapacity((width - 2) * (height - 2))
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = Int(pixels[y * width + x]) * 4
                let around = Int(pixels[(y - 1) * width + x]) + Int(pixels[(y + 1) * width + x])
                    + Int(pixels[y * width + x - 1]) + Int(pixels[y * width + x + 1])
                values.append(Double(around - center))
            }
        }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }

    /// 64-bit difference hash: near-identical pages differ in very few bits.
    func differenceHash() -> UInt64 {
        var hash: UInt64 = 0
        var bit: UInt64 = 1
        for row in 0..<8 {
            for column in 0..<8 {
                let left = sample(column: column, row: row, columns: 9, rows: 8)
                let right = sample(column: column + 1, row: row, columns: 9, rows: 8)
                if left > right { hash |= bit }
                bit <<= 1
            }
        }
        return hash
    }

    private func sample(column: Int, row: Int, columns: Int, rows: Int) -> Int {
        let x0 = column * width / columns, x1 = max(x0 + 1, (column + 1) * width / columns)
        let y0 = row * height / rows, y1 = max(y0 + 1, (row + 1) * height / rows)
        var sum = 0, count = 0
        for y in y0..<min(y1, height) {
            for x in x0..<min(x1, width) { sum += Int(pixels[y * width + x]); count += 1 }
        }
        return count == 0 ? 0 : sum / count
    }
}

/// Fast on-device text reading used only to judge orientation and to find a
/// printed page number near the top or bottom edge.
enum TextProbe {
    struct Reading {
        let uprightScore: Int
        let upsideDownScore: Int
        let pageNumber: Int?
    }

    static func read(_ image: UIImage) -> Reading {
        guard let cg = image.cgImage else { return Reading(uprightScore: 0, upsideDownScore: 0, pageNumber: nil) }
        let upright = recognize(cg, orientation: .up)
        let flipped = recognize(cg, orientation: .down)
        return Reading(uprightScore: score(upright), upsideDownScore: score(flipped),
                       pageNumber: pageNumber(in: upright))
    }

    private static func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation) -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:]).perform([request])
        return request.results ?? []
    }

    private static func score(_ observations: [VNRecognizedTextObservation]) -> Int {
        observations.reduce(0) { total, observation in
            guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.5 else { return total }
            return total + candidate.string.filter { $0.isLetter || $0.isNumber }.count
        }
    }

    /// A lone 1-4 digit number in the top or bottom 10% of the page.
    static func pageNumber(in observations: [VNRecognizedTextObservation]) -> Int? {
        for observation in observations {
            let y = observation.boundingBox.midY
            guard y < 0.10 || y > 0.90,
                  let text = observation.topCandidates(1).first?.string else { continue }
            let digits = text.trimmingCharacters(in: CharacterSet(charactersIn: " -–—.|"))
            if (1...4).contains(digits.count), let value = Int(digits) { return value }
        }
        return nil
    }
}
