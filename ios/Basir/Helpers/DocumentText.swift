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

    /// Extract text from a picked document URL. Handles the security-scoped
    /// access the Files picker hands back. Returns nil if unreadable.
    static func extract(from url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased()
        do {
            switch ext {
            case "pdf":  return try PdfReader.extractText(from: url)
            case "docx": return try DocxReader.extractText(from: url)
            case "pptx": return try PptxReader.extractText(from: url)
            default:     return try String(contentsOf: url, encoding: .utf8)
            }
        } catch {
            // Last resort for odd text encodings.
            return (try? String(contentsOf: url, encoding: .utf8))
        }
    }
}
