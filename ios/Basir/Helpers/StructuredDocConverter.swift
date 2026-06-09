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

        // Process several pages per call (like Android's 4-page batches)
        // so Gemini sees them together and produces a CONSISTENT table
        // schema across them — and so a 3-page doc is one call, matching
        // Android exactly. Also fewer, cheaper calls.
        let batchSize = 4
        var result = Result()
        var start = 1
        while start <= total {
            if shouldCancel() { break }   // keep batches converted so far
            let end = min(start + batchSize - 1, total)
            var images: [Data] = []
            for p in start...end {
                if let page = doc.page(at: p - 1),
                   let img = PdfReader.jpegData(for: page) {
                    images.append(img)
                }
            }
            if !images.isEmpty {
                let json = try await requestBatch(images: images,
                                                  startPage: start, endPage: end,
                                                  totalPages: total,
                                                  isFirst: result.blocks.isEmpty,
                                                  options: options)
                merge(json, into: &result, isFirst: start == 1, defaultPage: start)
            }
            onProgress?(end, total)
            onPartial?(displayText(result))
            start = end + 1
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
        let json = try await requestBatch(images: [jpeg], startPage: 1, endPage: 1,
                                          totalPages: 1, isFirst: true,
                                          options: options)
        var result = Result()
        merge(json, into: &result, isFirst: true, defaultPage: 1)
        onProgress?(1, 1)
        return result
    }

    // MARK: - Networking

    @MainActor
    private static func requestBatch(images: [Data],
                                     startPage: Int, endPage: Int,
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
            startPage: startPage,
            endPage: endPage,
            totalPages: totalPages,
            isFirst: isFirst,
            includeImages: options.describeImages,
            translateToName: options.translateTo.isEmpty ? nil : langName,
            math: options.math)

        let raw = try await GeminiClient.generateJsonStringWithImages(
            apiKey: key,
            model: model,
            systemText: "You are Basir, an assistant for blind and low-vision users.",
            userMessage: prompt,
            images: images,
            mimeType: "image/jpeg",
            maxOutputTokens: GeminiClient.maxOutputTokens)

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
                              isFirst: Bool, defaultPage: Int) {
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
        guard let sections = json["sections"] as? [[String: Any]] else {
            result.blocks.append(.pageMarker(defaultPage)); return
        }
        var currentPage = defaultPage
        var sawMarker = false
        for sec in sections {
            let type = (sec["type"] as? String ?? "").lowercased()
            switch type {
            case "page_marker":
                if let n = firstInt(sec["label"] as? String) { currentPage = n }
                result.blocks.append(.pageMarker(currentPage))
                sawMarker = true
            case "heading":
                if !sawMarker { result.blocks.append(.pageMarker(currentPage)); sawMarker = true }
                let level = (sec["level"] as? Int) ?? Int((sec["level"] as? String) ?? "") ?? 2
                let text = (sec["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { result.blocks.append(.heading(level: min(max(level, 1), 3), text: text)) }
            case "paragraph":
                if !sawMarker { result.blocks.append(.pageMarker(currentPage)); sawMarker = true }
                let text = (sec["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { result.blocks.append(.paragraph(text)) }
            case "image_description", "image":
                if !sawMarker { result.blocks.append(.pageMarker(currentPage)); sawMarker = true }
                let d = (sec["description"] as? String ?? sec["text"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !d.isEmpty { result.blocks.append(.imageDescription(page: currentPage, text: d)) }
            case "table":
                if !sawMarker { result.blocks.append(.pageMarker(currentPage)); sawMarker = true }
                let caption = (sec["caption"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let rowHeader = (sec["row_header"] as? Bool) ?? false
                let cells = parseCells(sec["cells"])
                if !cells.isEmpty {
                    result.blocks.append(.table(caption: (caption?.isEmpty == false) ? caption : nil,
                                                cells: cells, rowHeader: rowHeader))
                }
            default:
                let text = (sec["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { result.blocks.append(.paragraph(text)) }
            }
        }
    }

    /// First integer found in a string like "Page 3" → 3.
    private static func firstInt(_ s: String?) -> Int? {
        guard let s else { return nil }
        let digits = s.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits)
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
