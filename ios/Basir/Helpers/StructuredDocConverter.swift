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
                           onStatus: ((String) -> Void)? = nil,
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

        // Detect page orientation ONCE. Scanned transcripts are often
        // stored rotated 90° (sideways) with no /Rotate flag; sending such
        // a page as-is makes even Pro misread and FABRICATE. If it is
        // rotated, the Files API can't help (it would send the sideways
        // PDF), so we render the pages upright via the image path instead.
        onStatus?(L10n.t("جارٍ تحليل اتجاه الصفحات…", "Checking page orientation…"))
        let rotation = await detectRotation(doc: doc)
        onStatus?("")
        if rotation != 0 {
            return try await convertPdfViaImages(
                doc: doc, total: total, options: options, rotation: rotation,
                shouldCancel: shouldCancel, onStatus: onStatus,
                onProgress: onProgress, onPartial: onPartial)
        }

        // Upright document → PRIMARY (Android parity): upload the actual
        // PDF once via the Files API and reference it by URI per batch, so
        // Gemini reads the real document at full fidelity. If that path
        // fails, fall back to rendering pages as images.
        onStatus?(L10n.t("جارٍ تجهيز الملف ورفعه…", "Preparing and uploading the file…"))
        let key = KeychainStore.geminiKey()
        guard let bytes = try? Data(contentsOf: url) else {
            throw NSError(domain: "BasirConvert", code: 4, userInfo: [
                NSLocalizedDescriptionKey: L10n.t("تعذّر قراءة الملف.",
                                                  "The file could not be read.")])
        }

        let uploaded: GeminiClient.UploadedFile
        do {
            uploaded = try await withRetry {
                try await GeminiClient.uploadFile(apiKey: key, data: bytes,
                                                  mimeType: "application/pdf")
            }
            try await GeminiClient.waitForFileActive(apiKey: key, name: uploaded.name,
                                                     maxWaitSeconds: 120)
        } catch {
            // Upload/activation failed → image fallback for the whole doc.
            onStatus?("")
            return try await convertPdfViaImages(
                doc: doc, total: total, options: options,
                shouldCancel: shouldCancel, onStatus: onStatus,
                onProgress: onProgress, onPartial: onPartial)
        }
        onStatus?("")

        let batchSize = 4
        var result = Result()
        var start = 1
        while start <= total {
            if shouldCancel() { break }   // keep batches converted so far
            let end = min(start + batchSize - 1, total)
            do {
                let json = try await withRetry {
                    try await requestFileBatch(fileUri: uploaded.uri,
                                               fileMime: uploaded.mimeType,
                                               startPage: start, endPage: end,
                                               totalPages: total,
                                               isFirst: result.blocks.isEmpty,
                                               options: options)
                }
                merge(json, into: &result, isFirst: result.blocks.isEmpty, defaultPage: start)
            } catch {
                // If the VERY FIRST batch fails, the file path is unusable
                // here — switch the whole document to the image fallback.
                if result.blocks.isEmpty {
                    return try await convertPdfViaImages(
                        doc: doc, total: total, options: options,
                        shouldCancel: shouldCancel, onStatus: onStatus,
                        onProgress: onProgress, onPartial: onPartial)
                }
                // A later batch failing only loses that range; note + go on.
                result.blocks.append(.pageMarker(start))
                result.blocks.append(.paragraph(L10n.t(
                    "(تعذّرت معالجة الصفحات \(start)–\(end). يمكنك إعادة المحاولة لاحقًا.)",
                    "(Could not process pages \(start)–\(end). You can try again later.)")))
            }
            onProgress?(end, total)
            onPartial?(displayText(result))
            start = end + 1
        }
        validateGrades(&result.blocks)
        return result
    }

    /// Fallback / rotated-scan converter: render each page to an image
    /// (rotated upright by `rotation` degrees when the scan was stored
    /// sideways) and send page batches inline. Used when the Files API
    /// can't help — either it failed, or the scan is rotated (the Files
    /// API would send the sideways PDF and the model would fabricate).
    @MainActor
    private static func convertPdfViaImages(
        doc: PDFDocument, total: Int, options: DocConvertOptions,
        rotation: Int = 0,
        shouldCancel: () -> Bool,
        onStatus: ((String) -> Void)?,
        onProgress: ((Int, Int) -> Void)?,
        onPartial: ((String) -> Void)?) async throws -> Result {
        let batchSize = 4
        var result = Result()
        var start = 1
        while start <= total {
            if shouldCancel() { break }
            let end = min(start + batchSize - 1, total)
            var images: [Data] = []
            for p in start...end {
                if let page = doc.page(at: p - 1),
                   let img = PdfReader.jpegData(for: page, longEdge: 2400,
                                                rotationDegrees: rotation) {
                    images.append(img)
                }
            }
            if !images.isEmpty {
                do {
                    let json = try await withRetry {
                        try await requestBatch(images: images,
                                               startPage: start, endPage: end,
                                               totalPages: total,
                                               isFirst: result.blocks.isEmpty,
                                               options: options)
                    }
                    merge(json, into: &result, isFirst: result.blocks.isEmpty, defaultPage: start)
                } catch {
                    // If even the first fallback batch fails, surface the
                    // real error rather than a silent empty document.
                    if result.blocks.isEmpty { throw error }
                    result.blocks.append(.pageMarker(start))
                    result.blocks.append(.paragraph(L10n.t(
                        "(تعذّرت معالجة الصفحات \(start)–\(end). يمكنك إعادة المحاولة لاحقًا.)",
                        "(Could not process pages \(start)–\(end). You can try again later.)")))
                }
            }
            onProgress?(end, total)
            onPartial?(displayText(result))
            start = end + 1
        }
        validateGrades(&result.blocks)
        return result
    }

    /// Retry an async operation on transient API errors with exponential
    /// backoff (network drop, request timeout, HTTP 429 / 5xx).
    @MainActor
    private static func withRetry<T>(_ op: () async throws -> T) async throws -> T {
        var delay: UInt64 = 1_500_000_000   // 1.5s
        var lastError: Error?
        for attempt in 0..<4 {
            do { return try await op() }
            catch {
                lastError = error
                if attempt == 3 || !isTransient(error) { throw error }
                try? await Task.sleep(nanoseconds: delay)
                delay = min(delay * 2, 12_000_000_000)
            }
        }
        throw lastError ?? GeminiError.decode("retry failed")
    }

    private static func isTransient(_ error: Error) -> Bool {
        switch error {
        case GeminiError.network: return true
        case let GeminiError.http(status, _):
            return status == 429 || (500...599).contains(status)
        default: return false
        }
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
        validateGrades(&result.blocks)
        onProgress?(1, 1)
        return result
    }

    /// Ask Gemini once how far the first page must be rotated CLOCKWISE to
    /// be upright (0/90/180/270). A tiny, cheap text call; defaults to 0 on
    /// any uncertainty so an upright document is never needlessly rotated.
    @MainActor
    private static func detectRotation(doc: PDFDocument) async -> Int {
        guard let page = doc.page(at: 0),
              let img = PdfReader.jpegData(for: page, longEdge: 1100) else { return 0 }
        let key = KeychainStore.geminiKey()
        let model = BasirSettings.shared.modelFor(task: .convert)
        let prompt = "This image is ONE page of a scanned document. Looking at how the "
            + "text lines run, what CLOCKWISE rotation in degrees is needed to make the "
            + "text upright and normally readable? If it is already upright answer 0. "
            + "Answer with ONLY one number: 0, 90, 180, or 270."
        let resp = (try? await GeminiClient.generateWithImage(
            apiKey: key, model: model,
            systemText: "You detect the reading orientation of scanned pages.",
            userMessage: prompt, imageData: img, mimeType: "image/jpeg")) ?? "0"
        let digits = resp.drop { !$0.isNumber }.prefix { $0.isNumber }
        let value = Int(digits) ?? 0
        return [0, 90, 180, 270].contains(value) ? value : 0
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
            // A dense batch (several terms per page) needs plenty of room
            // so the JSON isn't truncated mid-document — losing or
            // reordering content. Gemini 2.5 models allow large outputs;
            // the API clamps to the model's max if it is lower.
            maxOutputTokens: 32768)

        return parseObject(raw)
    }

    /// Same as requestBatch but references an uploaded PDF by URI (Android
    /// parity) instead of sending rendered page images.
    @MainActor
    private static func requestFileBatch(fileUri: String, fileMime: String,
                                         startPage: Int, endPage: Int,
                                         totalPages: Int,
                                         isFirst: Bool,
                                         options: DocConvertOptions) async throws -> [String: Any] {
        let key = KeychainStore.geminiKey()
        let settings = BasirSettings.shared
        let model = settings.modelFor(task: .convert)
        let arabic = settings.language == .arabic
        let langName = options.translateTo.isEmpty
            ? (arabic ? "Arabic" : "English")
            : GeminiPrompts.bcp47Name(options.translateTo)
        let prompt = GeminiPrompts.documentPageInstruction(
            langName: langName,
            startPage: startPage,
            endPage: endPage,
            totalPages: totalPages,
            isFirst: isFirst,
            includeImages: options.describeImages,
            translateToName: options.translateTo.isEmpty ? nil : langName,
            math: options.math)

        let raw = try await GeminiClient.generateJsonStringWithFile(
            apiKey: key,
            model: model,
            systemText: "You are Basir, an assistant for blind and low-vision users.",
            userMessage: prompt,
            fileUri: fileUri,
            fileMimeType: fileMime,
            maxOutputTokens: 32768)

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

    // MARK: - Transcript validation engine (university-agnostic)

    /// Deterministic cross-check for academic-transcript tables of ANY
    /// university / grading system. It does NOT assume a fixed scale:
    /// instead it LEARNS the document's own scale (grade → points-per-hour)
    /// from the rows that are internally consistent, then fixes the rows
    /// whose printed grade contradicts that learned scale. Because the
    /// numeric columns (hours, points) are far less ambiguous to read than a
    /// single grade glyph, a row whose points ÷ hours lands on a learned
    /// value but whose printed grade differs almost certainly has a misread
    /// grade — so we correct the GRADE only. Numbers are never altered, and
    /// the table must expose grade + hours + points columns, so receipts,
    /// invoices, and other documents are never touched.
    @discardableResult
    static func validateGrades(_ blocks: inout [DocBlock]) -> Int {
        // Pass 1 — learn grade → value from this document's own rows.
        // value = points / hours, keyed by the grade text the doc uses.
        var samples: [String: [Double]] = [:]
        forEachGradeRow(blocks) { grade, ratio in
            samples[grade, default: []].append((ratio * 100).rounded() / 100)
        }
        guard !samples.isEmpty else { return 0 }

        // The representative value for a grade = the most common ratio,
        // and we only trust a grade backed by at least two consistent rows.
        var gradeToValue: [String: Double] = [:]
        for (grade, ratios) in samples {
            let counts = Dictionary(ratios.map { ($0, 1) }, uniquingKeysWith: +)
            if let (value, n) = counts.max(by: { $0.value < $1.value }), n >= 2 {
                gradeToValue[grade] = value
            }
        }
        // Invert to value → grade, dropping any value claimed by two grades.
        var valueToGrade: [Int: String] = [:]
        var ambiguous = Set<Int>()
        for (grade, value) in gradeToValue {
            let key = Int((value * 100).rounded())
            if let existing = valueToGrade[key], existing != grade { ambiguous.insert(key) }
            else { valueToGrade[key] = grade }
        }
        for k in ambiguous { valueToGrade[k] = nil }
        guard !valueToGrade.isEmpty else { return 0 }

        // Pass 2 — correct rows whose printed grade contradicts the learned
        // scale (numbers are clean, grade glyph was misread).
        var corrections = 0
        for i in blocks.indices {
            guard case let .table(caption, cells, rowHeader) = blocks[i],
                  let header = cells.first, cells.count > 1,
                  let gc = header.firstIndex(where: isGradeHeader),
                  let hc = header.firstIndex(where: isHoursHeader),
                  let pc = header.firstIndex(where: isPointsHeader) else { continue }
            var newCells = cells
            var changed = false
            for r in 1..<newCells.count {
                let row = newCells[r]
                guard gc < row.count, hc < row.count, pc < row.count,
                      looksLikeGrade(row[gc]),
                      let hours = number(row[hc]), hours >= 1, hours <= 12,
                      let points = number(row[pc]), points > 0 else { continue }
                let key = Int(((points / hours) * 100).rounded())
                guard let learned = valueToGrade[key] else { continue }
                if normalizedGrade(row[gc]) != normalizedGrade(learned) {
                    newCells[r][gc] = learned
                    changed = true
                    corrections += 1
                }
            }
            if changed {
                blocks[i] = .table(caption: caption, cells: newCells, rowHeader: rowHeader)
            }
        }
        return corrections
    }

    /// Visit every (grade, points/hours) sample across transcript-shaped
    /// tables — used to learn the document's own grading scale.
    private static func forEachGradeRow(_ blocks: [DocBlock],
                                        _ body: (_ grade: String, _ ratio: Double) -> Void) {
        for block in blocks {
            guard case let .table(_, cells, _) = block,
                  let header = cells.first, cells.count > 1,
                  let gc = header.firstIndex(where: isGradeHeader),
                  let hc = header.firstIndex(where: isHoursHeader),
                  let pc = header.firstIndex(where: isPointsHeader) else { continue }
            for row in cells.dropFirst() {
                guard gc < row.count, hc < row.count, pc < row.count,
                      looksLikeGrade(row[gc]),
                      let hours = number(row[hc]), hours >= 1, hours <= 12,
                      let points = number(row[pc]), points > 0 else { continue }
                body(normalizedGrade(row[gc]), points / hours)
            }
        }
    }

    private static func isGradeHeader(_ s: String) -> Bool {
        let t = s.lowercased()
        return s.contains("تقدير") || t.contains("grade")
    }
    private static func isHoursHeader(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        let l = t.lowercased()
        return t == "س" || t.contains("ساع") || t.contains("وحدات")
            || l.contains("hour") || l.contains("credit") || l == "ch"
    }
    private static func isPointsHeader(_ s: String) -> Bool {
        let l = s.lowercased()
        return s.contains("نقاط") || s.contains("نقطة") || l.contains("point")
    }
    /// A grade cell is a short token of grade letters (Arabic أبجده or Latin A–F)
    /// possibly with a +/-; never a long word or a number.
    private static func looksLikeGrade(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.count <= 3, number(t) == nil else { return false }
        return t.contains(where: { "أابجدهـ".contains($0) })
            || t.uppercased().contains(where: { "ABCDF".contains($0) })
    }
    private static func normalizedGrade(_ s: String) -> String {
        s.replacingOccurrences(of: " ", with: "")
    }
    /// Parse a number, tolerating Arabic-Indic digits and stray characters.
    private static func number(_ s: String) -> Double? {
        let map: [Character: Character] = [
            "٠":"0","١":"1","٢":"2","٣":"3","٤":"4",
            "٥":"5","٦":"6","٧":"7","٨":"8","٩":"9","٫":".",
        ]
        var out = ""
        for ch in s {
            if let m = map[ch] { out.append(m) }
            else if ch.isNumber || ch == "." { out.append(ch) }
        }
        return Double(out)
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
