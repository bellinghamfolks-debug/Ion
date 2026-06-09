// StructuredDocConverter.swift
// Android-parity document conversion.
//
// The problem this fixes
// ──────────────────────
//   The old iOS convert flow extracted only the PDF's TEXT LAYER on the
//   device and sent that flat text to Gemini. Tables collapsed into
//   meaningless runs of words, image content vanished, and even the most
//   expensive model produced garbage because it never SAW the page.
//
//   Android instead lets Gemini see the real document and return a
//   STRUCTURED JSON object — ordered sections where every table is real
//   2-D cell data — then builds a Word file with genuine tables. This is
//   that mechanism, ported: we render each page to an image, ask Gemini
//   (JSON mode) for the structured page, parse it into blocks, show a
//   clean readable result, and build a DOCX with actual tables.
//
//   Economical: pages run on the model the user picked (default Flash via
//   the convert screen), one page at a time, peak memory of a single page.

import Foundation
import PDFKit
import UIKit

/// One rendered element of a converted document.
enum DocBlock {
    case pageMarker(Int)
    case heading(level: Int, text: String)
    case paragraph(String)
    case imageDescription(page: Int, text: String)
    case table(caption: String?, cells: [[String]], rowHeader: Bool)
}

struct DocConvertOptions {
    /// BCP-47 code to translate into, or "" for no translation.
    var translateTo: String = ""
    /// Include image descriptions (full mode) vs. text/tables only.
    var describeImages: Bool = false
    /// Render mathematics as spoken form + LaTeX.
    var math: Bool = false
}

enum StructuredDocConverter {

    /// True when we can run the structured (JSON) pipeline. It needs a
    /// direct Gemini key because it uses JSON-mode image calls; proxy /
    /// keyless setups fall back to the legacy text path in the caller.
    @MainActor static var isAvailable: Bool { !KeychainStore.geminiKey().isEmpty }

    struct Result {
        var blocks: [DocBlock] = []
        var title: String = ""
        var summary: String = ""
    }

    /// Convert every page of a PDF. `onProgress(done, total)` and
    /// `onPartial(displayText)` are called on the main actor so the view
    /// can show a live progress bar and a growing result.
    @MainActor
    static func convertPdf(url: URL,
                           options: DocConvertOptions,
                           maxPages: Int = 500,
                           shouldCancel: () -> Bool = { false },
                           onProgress: ((Int, Int) -> Void)? = nil,
                           onPartial: ((String) -> Void)? = nil) async throws -> Result {
        guard let doc = PDFDocument(url: url) else {
            throw NSError(domain: "BasirConvert", code: 1, userInfo: [
                NSLocalizedDescriptionKey: L10n.t("تعذّر فتح ملف PDF.",
                                                  "The PDF could not be opened.")])
        }
        let total = min(doc.pageCount, maxPages)
        guard total > 0 else {
            throw NSError(domain: "BasirConvert", code: 2, userInfo: [
                NSLocalizedDescriptionKey: L10n.t("الملف لا يحتوي على صفحات.",
                                                  "The file has no pages.")])
        }
        onProgress?(0, total)

        var result = Result()
        for i in 0..<total {
            if shouldCancel() { break }   // keep pages converted so far
            guard let page = doc.page(at: i),
                  let image = PdfReader.jpegData(for: page) else {
                onProgress?(i + 1, total); continue
            }
            let json = try await requestPage(image: image,
                                              pageNumber: i + 1,
                                              totalPages: total,
                                              isFirst: result.blocks.isEmpty,
                                              options: options)
            merge(json, into: &result, isFirst: i == 0, page: i + 1)
            onProgress?(i + 1, total)
            onPartial?(displayText(result))
        }
        return result
    }

    /// Convert a single image file (photo / scan) the same way.
    @MainActor
    static func convertImage(url: URL,
                             options: DocConvertOptions,
                             onProgress: ((Int, Int) -> Void)? = nil) async throws -> Result {
        guard let jpeg = DocumentText.imageData(from: url) else {
            throw NSError(domain: "BasirConvert", code: 3, userInfo: [
                NSLocalizedDescriptionKey: L10n.t("تعذّر قراءة الصورة.",
                                                  "The image could not be read.")])
        }
        onProgress?(0, 1)
        let json = try await requestPage(image: jpeg, pageNumber: 1,
                                         totalPages: 1, isFirst: true,
                                         options: options)
        var result = Result()
        merge(json, into: &result, isFirst: true, page: 1)
        onProgress?(1, 1)
        return result
    }

    // MARK: - Networking

    @MainActor
    private static func requestPage(image: Data,
                                    pageNumber: Int,
                                    totalPages: Int,
                                    isFirst: Bool,
                                    options: DocConvertOptions) async throws -> [String: Any] {
        let key = KeychainStore.geminiKey()
        let settings = BasirSettings.shared
        let model = settings.modelFor(task: .convert)
        let arabic = settings.language == .arabic
        let langName: String
        if options.translateTo.isEmpty {
            langName = arabic ? "Arabic" : "English"
        } else {
            langName = GeminiPrompts.bcp47Name(options.translateTo)
        }
        let prompt = GeminiPrompts.documentPageInstruction(
            langName: langName,
            pageNumber: pageNumber,
            totalPages: totalPages,
            isFirst: isFirst,
            includeImages: options.describeImages,
            translateToName: options.translateTo.isEmpty ? nil : langName,
            math: options.math)

        let raw = try await GeminiClient.generateJsonStringWithImage(
            apiKey: key,
            model: model,
            systemText: "You are Basir, an assistant for blind and low-vision users.",
            userMessage: prompt,
            imageData: image,
            mimeType: "image/jpeg",
            maxOutputTokens: 8192)

        return parseObject(raw)
    }

    // MARK: - JSON parsing

    /// Tolerant JSON-object parse: strips ```json fences and any prose
    /// around the outermost { … } before decoding.
    private static func parseObject(_ s: String) -> [String: Any] {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = t.firstIndex(of: "{"), let close = t.lastIndex(of: "}"), open < close {
            t = String(t[open...close])     // trim ```json fences / stray prose
        }
        guard let data = t.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    private static func merge(_ json: [String: Any], into result: inout Result,
                              isFirst: Bool, page: Int) {
        if isFirst {
            if let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty {
                result.title = title
                result.blocks.append(.heading(level: 1, text: title))
            }
            if let summary = (json["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !summary.isEmpty {
                result.summary = summary
                result.blocks.append(.paragraph(summary))
            }
        }
        // A page marker before each page's content — mirrors Android and
        // gives a blind reader a clear "Page N" landmark to navigate by.
        result.blocks.append(.pageMarker(page))
        guard let sections = json["sections"] as? [[String: Any]] else { return }
        for sec in sections {
            let type = (sec["type"] as? String ?? "").lowercased()
            switch type {
            case "heading":
                let level = (sec["level"] as? Int) ?? Int((sec["level"] as? String) ?? "") ?? 2
                let text = (sec["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { result.blocks.append(.heading(level: min(max(level, 1), 3), text: text)) }
            case "paragraph":
                let text = (sec["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { result.blocks.append(.paragraph(text)) }
            case "image_description", "image":
                let d = (sec["description"] as? String ?? sec["text"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !d.isEmpty { result.blocks.append(.imageDescription(page: page, text: d)) }
            case "table":
                let caption = (sec["caption"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let rowHeader = (sec["row_header"] as? Bool) ?? false
                let cells = parseCells(sec["cells"])
                if !cells.isEmpty {
                    result.blocks.append(.table(caption: (caption?.isEmpty == false) ? caption : nil,
                                                cells: cells, rowHeader: rowHeader))
                }
            case "page_marker":
                break   // page markers are internal bookkeeping; not shown
            default:
                if let text = (sec["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty { result.blocks.append(.paragraph(text)) }
            }
        }
    }

    private static func parseCells(_ raw: Any?) -> [[String]] {
        guard let rows = raw as? [[Any]] else { return [] }
        return rows.map { row in
            row.map { cell in
                if let s = cell as? String { return s }
                if let n = cell as? NSNumber { return n.stringValue }
                return String(describing: cell)
            }
        }
    }

    // MARK: - Rendering

    /// A clean, screen-reader-friendly plain-text rendering of the blocks
    /// for on-screen display, Copy, and Share. Tables become aligned rows
    /// ("Header: value" per cell) so they read sensibly aloud.
    static func displayText(_ result: Result) -> String {
        var out = ""
        for block in result.blocks {
            switch block {
            case .pageMarker(let n):
                out += "\n" + L10n.t("صفحة \(n)", "Page \(n)") + "\n"
            case .heading(_, let text):
                out += "\n" + text + "\n"
            case .paragraph(let text):
                out += text + "\n\n"
            case .imageDescription(let page, let text):
                out += L10n.t("وصف الصورة (صفحة \(page)): ",
                              "Image description (Page \(page)): ") + text + "\n\n"
            case .table(let caption, let cells, _):
                if let caption { out += caption + "\n" }
                out += renderTableText(cells) + "\n\n"
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Read a table row-by-row with each value labelled by its column
    /// header — far clearer with a screen reader than a raw grid.
    private static func renderTableText(_ cells: [[String]]) -> String {
        guard let header = cells.first else { return "" }
        if cells.count == 1 { return header.joined(separator: " | ") }
        var lines: [String] = []
        for (idx, row) in cells.dropFirst().enumerated() {
            var parts: [String] = []
            for (c, value) in row.enumerated() {
                let label = c < header.count ? header[c] : ""
                if value.isEmpty { continue }
                parts.append(label.isEmpty ? value : "\(label): \(value)")
            }
            lines.append(L10n.t("صف \(idx + 1): ", "Row \(idx + 1): ")
                         + parts.joined(separator: "، "))
        }
        return lines.joined(separator: "\n")
    }

    /// Build a Word (.docx) file with REAL tables from the blocks.
    static func buildDocx(_ result: Result, rtl: Bool, to url: URL) throws {
        var writer = DocxWriter(rtl: rtl)
        for block in result.blocks {
            switch block {
            case .pageMarker(let n):
                writer.append(.heading(level: 3, text: L10n.t("صفحة \(n)", "Page \(n)")))
            case .heading(let level, let text):
                writer.append(.heading(level: level, text: text))
            case .paragraph(let text):
                writer.append(.paragraph(text: text))
            case .imageDescription(let page, let text):
                writer.append(.paragraph(text:
                    L10n.t("وصف الصورة (صفحة \(page)): ",
                           "Image description (Page \(page)): ") + text))
            case .table(let caption, let cells, _):
                if let caption { writer.append(.paragraph(text: caption)) }
                writer.append(.table(rows: cells))
            }
        }
        try writer.write(to: url)
    }
}
