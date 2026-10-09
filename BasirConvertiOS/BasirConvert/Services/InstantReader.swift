import Foundation
import PDFKit
import UIKit
import Vision

/// Reads a photo or a PDF on the phone, with no internet: the PDF's own text
/// where it is trustworthy, Apple's on-device text recognition otherwise.
/// Faster and fully private, though less faithful than a Basir conversion.
enum InstantReader {
    static let maximumPages = 30
    /// Pages recognised at the same time.
    static let parallelPages = 3

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

    /// One page to read: the PDF's text when it can be trusted, else an image.
    private enum PageSource {
        case text(String)
        case image(UIImage)
    }

    static func read(_ urls: [URL], isArabic: Bool, progress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> Outcome {
        var sources: [PageSource] = []
        var skipped = 0
        for url in urls {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            if url.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(url: url) {
                for index in 0..<pdf.pageCount {
                    guard sources.count < maximumPages else { skipped += 1; continue }
                    guard let page = pdf.page(at: index) else { continue }
                    let raw = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if let usable = TextLayerCheck.usableText(raw) {
                        sources.append(.text(usable))
                    } else {
                        sources.append(.image(render(page)))
                    }
                }
            } else if let image = UIImage(contentsOfFile: url.path) {
                guard sources.count < maximumPages else { skipped += 1; continue }
                sources.append(.image(image))
            }
        }

        let total = sources.count
        var pages = Array(repeating: [String](), count: total)
        var done = 0
        try await withThrowingTaskGroup(of: (Int, [String]).self) { group in
            var next = 0
            func addNext() {
                guard next < total else { return }
                let index = next
                let source = sources[index]
                next += 1
                group.addTask {
                    switch source {
                    case .text(let text): return (index, paragraphs(fromPlainText: text))
                    case .image(let image): return (index, try recognize(image, preferArabic: isArabic))
                    }
                }
            }
            for _ in 0..<min(parallelPages, total) { addNext() }
            while let (index, paragraphs) = try await group.next() {
                pages[index] = paragraphs
                done += 1
                progress?(done, total)
                addNext()
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

    /// Sharp enough for Arabic dots and small print: about 2,800 pixels on
    /// the long side, whatever the page size.
    private static func render(_ page: PDFPage) -> UIImage {
        let bounds = page.bounds(for: .mediaBox)
        let longSide = max(bounds.width, bounds.height, 1)
        let scale = min(6, max(2, 2_800 / longSide))
        return page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
    }

    static func paragraphs(fromPlainText text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .map { $0.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Arabic first when the page may be Arabic (it also reads English
    /// words well); a page that turns out to be English is read again with
    /// English only, which is more accurate for English.
    private static func recognize(_ image: UIImage, preferArabic: Bool) throws -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = orientation(of: image)
        let arabicAvailable = supportsArabic
        if arabicAvailable {
            let lines = try recognizeLines(cgImage, orientation: orientation, languages: ["ar-SA", "en-US"])
            let joined = lines.map(\.text).joined(separator: " ")
            if ScriptMix.arabicShare(joined) >= 0.05 || ScriptMix.letters(joined) < 20 {
                return group(lines)
            }
            // Barely any Arabic: an English page.
            return group(try recognizeLines(cgImage, orientation: orientation, languages: ["en-US"]))
        }
        return group(try recognizeLines(cgImage, orientation: orientation, languages: ["en-US"], autoDetect: !preferArabic))
    }

    private static func recognizeLines(_ image: CGImage, orientation: CGImagePropertyOrientation, languages: [String],
                                       autoDetect: Bool = false) throws -> [Line] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Automatic detection ignores the language list and often picks
        // English for Arabic pages, so the order given here is used instead.
        request.automaticallyDetectsLanguage = autoDetect
        request.recognitionLanguages = languages
        request.minimumTextHeight = 0.008
        try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
        return (request.results ?? []).compactMap { observation -> Line? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return Line(text: text, box: observation.boundingBox)
        }
    }

    struct Line: Equatable {
        var text: String
        /// Normalized, origin bottom-left (Vision).
        var box: CGRect
    }

    /// Lines top to bottom, joined into paragraphs where the gap is small.
    /// Pieces on the same row are put in reading order: right to left for
    /// Arabic, left to right otherwise.
    static func group(_ lines: [Line]) -> [String] {
        let rows = self.rows(lines)
        guard !rows.isEmpty else { return [] }
        let averageHeight = rows.map(\.box.height).reduce(0, +) / CGFloat(rows.count)
        var paragraphs: [String] = []
        var current: [String] = []
        var previous: Line?
        for line in rows {
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

    /// Merges observations that share a row (they overlap vertically by more
    /// than half the smaller height) into one line.
    static func rows(_ lines: [Line]) -> [Line] {
        let sorted = lines.sorted { $0.box.midY > $1.box.midY }
        var rows: [[Line]] = []
        for line in sorted {
            if let last = rows.last?.last, overlap(last.box, line.box) > 0.5 * min(last.box.height, line.box.height) {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { pieces in
            guard pieces.count > 1 else { return pieces[0] }
            let text = pieces.map(\.text).joined(separator: " ")
            let rightToLeft = ScriptMix.arabicShare(text) >= 0.5
            let ordered = pieces.sorted { rightToLeft ? $0.box.maxX > $1.box.maxX : $0.box.minX < $1.box.minX }
            let box = pieces.dropFirst().reduce(pieces[0].box) { $0.union($1.box) }
            return Line(text: ordered.map(\.text).joined(separator: " "), box: box)
        }
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
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

/// How much of a text is Arabic.
enum ScriptMix {
    static func arabicShare(_ text: String) -> Double {
        var arabic = 0, latin = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF: arabic += 1
            case 0x41...0x5A, 0x61...0x7A: latin += 1
            default: break
            }
        }
        let total = arabic + latin
        return total == 0 ? 0 : Double(arabic) / Double(total)
    }

    static func letters(_ text: String) -> Int {
        text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
    }
}

/// Many Arabic PDFs carry a broken text layer: letters in their "shaped"
/// presentation forms, or each line stored backwards. Shaped forms are
/// normalised; a backwards layer is not used, and the page is recognised
/// from its image instead.
enum TextLayerCheck {
    static let minimumCharacters = 40

    /// Common words, and how they look when stored backwards.
    private static let commonWords = ["في", "من", "على", "إلى", "الى", "عن", "أن", "التي", "الذي", "هذا", "هذه", "مع", "كان", "ما", "لا"]
    private static let reversedWords = Set(commonWords.map { String($0.reversed()) })
    private static let forwardWords = Set(commonWords)

    static func usableText(_ raw: String) -> String? {
        guard raw.count >= minimumCharacters else { return nil }
        // Presentation forms (ﻣﺮﺣﺒﺎ) back to ordinary letters (مرحبا).
        let text = raw.precomposedStringWithCompatibilityMapping
        guard ScriptMix.arabicShare(text) >= 0.2 else { return text }
        return isBackwards(text) ? nil : text
    }

    /// True when the Arabic words read backwards: "ال" at the end of words
    /// instead of the start, and common words reversed.
    static func isBackwards(_ text: String) -> Bool {
        let words = text.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .filter { ScriptMix.arabicShare($0) > 0.9 }
        guard words.count >= 6 else { return false }
        var forward = 0, backward = 0
        for word in words {
            if forwardWords.contains(word) { forward += 2 }
            if reversedWords.contains(word) { backward += 2 }
            if word.count > 3, word.hasPrefix("ال") { forward += 1 }
            if word.count > 3, word.hasSuffix("لا") { backward += 1 }
        }
        return backward > forward
    }
}
