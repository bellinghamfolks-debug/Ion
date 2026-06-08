// DocumentText.swift
// One place to pull plain text out of a user-picked document, reusing the
// same on-device extractors the conversion flow uses. Lets text tools and
// Translate accept a document instead of only pasted text.

import Foundation
import UniformTypeIdentifiers
import PDFKit
import UIKit

enum DocumentText {

    /// Content types broad enough that documents aren't greyed out in the
    /// Files picker (validated by extension after picking). Includes image
    /// types so a photo/scan saved in Files can be picked and read via OCR
    /// — matching Android, which lets you insert image files too.
    static var importTypes: [UTType] {
        var types: [UTType] = [.pdf, .plainText, .commaSeparatedText,
                               .text, .rtf, .content,
                               .image, .jpeg, .png, .heic]
        if let docx = UTType(mimeType:
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document") {
            types.append(docx)
        }
        if let pptx = UTType(mimeType:
            "application/vnd.openxmlformats-officedocument.presentationml.presentation") {
            types.append(pptx)
        }
        return types
    }

    /// File extensions we treat as a single image to OCR / describe.
    static let imageExtensions: Set<String> =
        ["jpg", "jpeg", "png", "heic", "heif", "gif", "bmp", "tiff", "tif", "webp"]

    /// True when a picked URL points at an image file (vs. a document).
    static func isImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    /// Read an image file (picked via the Files picker, already copied
    /// into our sandbox by asCopy:true) and re-encode it as a ≤1600px
    /// JPEG — the same envelope the camera/photo paths use for Gemini.
    static func imageData(from url: URL) -> Data? {
        guard let raw = try? Data(contentsOf: url),
              let img = UIImage(data: raw) else { return nil }
        let maxLongEdge: CGFloat = 1600
        let longEdge = max(img.size.width, img.size.height)
        guard longEdge > 0 else { return raw }
        let scale = min(1.0, maxLongEdge / longEdge)
        let newSize = CGSize(width: img.size.width * scale,
                             height: img.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            img.draw(in: CGRect(origin: .zero, size: newSize))
        }.jpegData(compressionQuality: 0.85) ?? raw
    }

    /// OCR a single image file through Gemini vision, following the
    /// user-selected document model (docQuality), with the same progress
    /// callback shape as ocrPdf so the convert screen can show a bar.
    @MainActor
    static func ocrImage(from url: URL,
                         describeImages: Bool = false,
                         onProgress: ((Int, Int) -> Void)? = nil) async -> String? {
        guard let jpeg = imageData(from: url) else { return nil }
        onProgress?(0, 1)
        let lang = BasirSettings.shared.language
        let text = (try? await AiProviderFactory.current().ask(
            task: .convert,
            input: "",
            instruction: visionInstruction(describeImages: describeImages,
                                            arabic: lang == .arabic),
            language: lang,
            imageData: jpeg,
            mimeType: "image/jpeg")) ?? ""
        onProgress?(1, 1)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Extract text from a picked document URL. Handles iCloud files that
    /// aren't downloaded yet (the ☁️ ones) by triggering a download and
    /// reading through NSFileCoordinator, then copying into our sandbox
    /// before extracting. Returns nil only if it truly can't be read.
    static func extract(from url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        // Ask iCloud to materialize the file if it lives only in the cloud.
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        var copied = false

        // A coordinated read blocks until iCloud has the bytes locally.
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.copyItem(at: readURL, to: dest)
                copied = true
            } catch {
                // Fall back to reading bytes directly into the temp file.
                if let data = try? Data(contentsOf: readURL) {
                    copied = (try? data.write(to: dest)) != nil
                }
            }
        }

        let working = copied ? dest : url
        defer { try? FileManager.default.removeItem(at: dest) }

        let ext = url.pathExtension.lowercased()
        do {
            switch ext {
            case "pdf":  return try PdfReader.extractText(from: working)
            case "docx": return try DocxReader.extractText(from: working)
            case "pptx": return try PptxReader.extractText(from: working)
            default:
                if let s = try? String(contentsOf: working, encoding: .utf8) { return s }
                return try String(contentsOf: working, encoding: .isoLatin1)
            }
        } catch {
            return (try? String(contentsOf: working, encoding: .utf8))
        }
    }

    /// Async extraction that adds an OCR fallback for scanned PDFs (no
    /// text layer): renders pages to images and transcribes them with
    /// Gemini vision, like the Android PdfRenderer → Gemini path.
    @MainActor
    static func extractTextAsync(from url: URL) async -> String? {
        // Image file picked from Files → OCR it like a one-page scan.
        if isImage(url) {
            return await ocrImage(from: url)
        }
        if url.pathExtension.lowercased() == "pdf" {
            // A PDF with a real text layer extracts instantly and free.
            if let t = try? PdfReader.extractText(from: url),
               !t.replacingOccurrences(of: "[Page", with: "")
                  .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return t
            }
            // Scanned PDF → OCR via Gemini vision.
            return await ocrPdf(from: url)
        }
        return extract(from: url)
    }

    /// OCR every rendered page of a scanned PDF through Gemini vision and
    /// join the transcriptions. Uses the cheap (Flash) screenshot task.
    ///
    /// `onProgress(done, total)` is invoked on the main actor — first
    /// with (0, pageCount) once the pages are rendered, then after each
    /// page is transcribed — so the convert screen can show a real OCR
    /// progress bar instead of an indeterminate spinner.
    /// Vision instruction for a page/image. When `describeImages` is on we
    /// additionally ask the model to describe any photos, figures, charts,
    /// or diagrams inline — the iOS equivalent of Android's "full" convert
    /// mode (which can see images because it uploads the whole PDF). Off by
    /// default to stay economical (text-only is far cheaper).
    private static func visionInstruction(describeImages: Bool, arabic: Bool) -> String {
        let base = "Transcribe ALL text on this page EXACTLY as written, "
            + "preserving reading order, line breaks, numbers, and table layout as plain text. "
        if !describeImages {
            return base + "Output only the transcribed text with no commentary."
        }
        let tag = arabic ? "[صورة: …]" : "[Image: …]"
        return base
            + "ALSO, wherever the page contains a photo, figure, chart, diagram, logo, "
            + "or illustration, insert a concise, useful description of it — written for a "
            + "blind reader — at the position where it appears, wrapped like \(tag). "
            + "For charts and diagrams, describe what they show (trend, axes, key values). "
            + "Do NOT invent images that are not present. No other commentary."
    }

    @MainActor
    static func ocrPdf(from url: URL, maxPages: Int = 500,
                       describeImages: Bool = false,
                       onProgress: ((Int, Int) -> Void)? = nil) async -> String? {
        guard let doc = PDFDocument(url: url) else { return nil }
        let total = min(doc.pageCount, maxPages)
        guard total > 0 else { return nil }
        // Show the progress bar from the very first page (the previous
        // build rendered every page before any OCR began, so the bar
        // never appeared and memory spiked).
        onProgress?(0, total)
        let lang = BasirSettings.shared.language
        let instruction = visionInstruction(describeImages: describeImages,
                                             arabic: lang == .arabic)
        var sb = ""
        for i in 0..<total {
            // Render ONE page, transcribe it, then let it deallocate
            // before moving on — peak memory stays at a single page.
            guard let page = doc.page(at: i),
                  let image = PdfReader.jpegData(for: page) else {
                onProgress?(i + 1, total)
                continue
            }
            // Use the .convert task so OCR follows the user-selected
            // document-processing model (docQuality) — the file model
            // picker / Settings genuinely control which Gemini model
            // does the scan.
            let text = (try? await AiProviderFactory.current().ask(
                task: .convert,
                input: "",
                instruction: instruction,
                language: lang,
                imageData: image,
                mimeType: "image/jpeg")) ?? ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { sb += "\n[Page \(i + 1)]\n" + trimmed + "\n" }
            onProgress?(i + 1, total)
        }
        return sb.isEmpty ? nil : sb
    }
}
