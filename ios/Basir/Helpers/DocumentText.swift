// DocumentText.swift
// One place to pull plain text out of a user-picked document, reusing the
// same on-device extractors the conversion flow uses. Lets text tools and
// Translate accept a document instead of only pasted text.

import Foundation
import UniformTypeIdentifiers
import PDFKit

enum DocumentText {

    /// Content types broad enough that documents aren't greyed out in the
    /// Files picker (validated by extension after picking).
    static var importTypes: [UTType] {
        var types: [UTType] = [.pdf, .plainText, .commaSeparatedText,
                               .text, .rtf, .content]
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
    @MainActor
    static func ocrPdf(from url: URL, maxPages: Int = 500,
                       onProgress: ((Int, Int) -> Void)? = nil) async -> String? {
        guard let doc = PDFDocument(url: url) else { return nil }
        let total = min(doc.pageCount, maxPages)
        guard total > 0 else { return nil }
        // Show the progress bar from the very first page (the previous
        // build rendered every page before any OCR began, so the bar
        // never appeared and memory spiked).
        onProgress?(0, total)
        let lang = BasirSettings.shared.language
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
                instruction: "Transcribe ALL text in this scanned document page EXACTLY as written, "
                    + "preserving reading order, line breaks, numbers, and table layout as plain text. "
                    + "Output only the transcribed text with no commentary.",
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
