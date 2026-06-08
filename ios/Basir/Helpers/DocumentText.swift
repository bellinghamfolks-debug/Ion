// DocumentText.swift
// One place to pull plain text out of a user-picked document, reusing the
// same on-device extractors the conversion flow uses. Lets text tools and
// Translate accept a document instead of only pasted text.

import Foundation
import UniformTypeIdentifiers

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

    /// Extract text from a picked document URL. Copies the security-scoped
    /// file into our sandbox first (reading PDFs/Office files straight from
    /// a scoped URL is unreliable), then extracts by extension. Returns nil
    /// only if the file genuinely can't be read.
    static func extract(from url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        // Work from a local copy so subsequent reads need no scope.
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        let working: URL
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            working = dest
        } catch {
            working = url   // fall back to the original URL
        }
        defer { try? FileManager.default.removeItem(at: dest) }

        let ext = working.pathExtension.lowercased()
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
}
