// StructuredDocConverter.swift
// High-fidelity, page-isolated PDF/image to Word conversion.
//
// Design goals:
// 1. Never lose an entire multi-page batch because one page failed.
// 2. Never present a partial result as a complete conversion.
// 3. Preserve exact text, numbers, tables, reading order, and mixed RTL/LTR.
// 4. Use structured output with an explicit JSON Schema where supported.
// 5. Fall back to local text and, for scanned pages, an embedded page image.

import Foundation
import PDFKit
import UIKit

struct DocTextRun: Hashable, Sendable {
    enum Direction: String, Sendable {
        case auto, rtl, ltr
    }

    var text: String
    var bold: Bool = false
    var italic: Bool = false
    var underline: Bool = false
    var strike: Bool = false
    var highlight: Bool = false
    var superscript: Bool = false
    var isSubscript: Bool = false
    var fontSizePoints: Double? = nil
    var colorHex: String? = nil
    var url: String? = nil
    var direction: Direction = .auto
}

enum DocBlock: Sendable {
    case pageMarker(Int)
    case pageBreak
    case heading(level: Int, runs: [DocTextRun])
    case paragraph(runs: [DocTextRun])
    case listItem(level: Int, ordered: Bool, runs: [DocTextRun])
    case imageDescription(page: Int, text: String)
    case pageImage(page: Int, data: Data, altText: String)
    case table(caption: String?, cells: [[String]], rowHeader: Bool)
}

struct DocConvertOptions: Sendable {
    var translateTo: String = ""
    var describeImages: Bool = false
    var math: Bool = false
}

struct DocConversionDiagnostics: Sendable {
    var totalPages = 0
    var processedPages = 0
    var aiPages = 0
    var localFallbackPages = 0
    var imageFallbackPages = 0
    var warningPages: [Int] = []
    var failedPages: [Int] = []
    var wasCancelled = false

    var isComplete: Bool {
        !wasCancelled && processedPages == totalPages && failedPages.isEmpty
    }

    var summaryArabic: String {
        let state = wasCancelled ? "أُوقفت المعالجة قبل اكتمالها. " : ""
        return state + "عولجت \(processedPages) من \(totalPages) صفحة. "
        + "نجح التحليل المنظم في \(aiPages)، واستخدم الاستخراج المحلي في \(localFallbackPages)، "
        + "وحُفظت صورة الصفحة في \(imageFallbackPages)."
        + (failedPages.isEmpty ? "" : " الصفحات التي تعذّر حفظها: \(failedPages.map(String.init).joined(separator: ", ")).")
    }

    var summaryEnglish: String {
        let state = wasCancelled ? "Processing stopped before completion. " : ""
        return state + "Processed \(processedPages) of \(totalPages) pages. "
        + "Structured analysis succeeded for \(aiPages), local extraction was used for \(localFallbackPages), "
        + "and a page image was preserved for \(imageFallbackPages)."
        + (failedPages.isEmpty ? "" : " Pages that could not be preserved: \(failedPages.map(String.init).joined(separator: ", ")).")
    }
}

enum StructuredDocConverter {
    struct Result: Sendable {
        var blocks: [DocBlock] = []
        var title: String = ""
        var diagnostics = DocConversionDiagnostics()
    }

    @MainActor
    static var isAvailable: Bool { AiProviderFactory.isConfigured }

    // MARK: - Conversion entry points

    @MainActor
    static func convertPdf(
        url: URL,
        options: DocConvertOptions,
        maxPages: Int = 500,
        shouldCancel: () -> Bool = { false },
        onStatus: ((String) -> Void)? = nil,
        onProgress: ((Int, Int) -> Void)? = nil,
        onPartial: ((String) -> Void)? = nil
    ) async throws -> Result {
        let snapshotter = try await Task.detached(priority: .userInitiated) {
            try PdfPageSnapshotter(url: url, maxPages: maxPages)
        }.value
        let total = snapshotter.pageCount
        guard total > 0 else {
            throw conversionError(2, ar: "الملف لا يحتوي على صفحات.", en: "The file has no pages.")
        }

        var result = Result()
        result.diagnostics.totalPages = total
        onProgress?(0, total)

        for index in 0..<total {
            if shouldCancel() || Task.isCancelled {
                result.diagnostics.wasCancelled = true
                break
            }
            let pageNumber = index + 1
            onStatus?(L10n.t("جارٍ تحليل الصفحة \(pageNumber)…",
                             "Analyzing page \(pageNumber)…"))

            guard let snapshot = await snapshotter.snapshot(at: index) else {
                appendUnavailablePage(pageNumber, to: &result)
                if pageNumber < total { result.blocks.append(.pageBreak) }
                onProgress?(pageNumber, total)
                continue
            }

            let sourceText = snapshot.text
            let imageData = snapshot.jpegData

            result.blocks.append(.pageMarker(pageNumber))
            do {
                guard let imageData else { throw GeminiError.decode("page render failed") }
                let pageBlocks = try await convertPage(
                    imageData: imageData,
                    pageNumber: pageNumber,
                    totalPages: total,
                    sourceText: sourceText,
                    options: options)
                result.blocks.append(contentsOf: pageBlocks)
                if options.describeImages,
                   pageBlocks.contains(where: {
                       if case .imageDescription = $0 { return true }
                       return false
                   }) {
                    let descriptions = pageBlocks.compactMap { block -> String? in
                        if case let .imageDescription(_, text) = block { return text }
                        return nil
                    }.joined(separator: " ")
                    result.blocks.append(.pageImage(
                        page: pageNumber,
                        data: imageData,
                        altText: descriptions.isEmpty
                            ? L10n.t("مرجع بصري للصفحة \(pageNumber)", "Visual reference for page \(pageNumber)")
                            : descriptions))
                }
                result.diagnostics.aiPages += 1
            } catch {
                if Task.isCancelled || isCancellation(error) {
                    result.diagnostics.wasCancelled = true
                    break
                }
                AppLogger.documentError("Structured page conversion failed at page \(pageNumber)")
                appendFallback(pageImage: imageData,
                               pageNumber: pageNumber,
                               sourceText: sourceText,
                               to: &result)
            }

            if pageNumber < total { result.blocks.append(.pageBreak) }
            result.diagnostics.processedPages += 1
            onProgress?(pageNumber, total)
            onPartial?(displayText(result))
        }

        onStatus?("")
        if result.diagnostics.processedPages == 0 && result.diagnostics.wasCancelled {
            throw GeminiError.cancelled
        }
        result.title = firstHeading(in: result.blocks) ?? url.deletingPathExtension().lastPathComponent
        return result
    }

    @MainActor
    static func convertImage(
        url: URL,
        options: DocConvertOptions,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws -> Result {
        guard let imageData = await Task.detached(priority: .userInitiated, operation: {
            DocumentText.imageData(from: url)
        }).value else {
            throw conversionError(3, ar: "تعذّر قراءة الصورة.", en: "The image could not be read.")
        }
        onProgress?(0, 1)
        var result = Result()
        result.diagnostics.totalPages = 1
        result.blocks.append(.pageMarker(1))
        do {
            result.blocks.append(contentsOf: try await convertPage(
                imageData: imageData,
                pageNumber: 1,
                totalPages: 1,
                sourceText: "",
                options: options))
            result.diagnostics.aiPages = 1
            if options.describeImages {
                result.blocks.append(.pageImage(page: 1,
                                                data: imageData,
                                                altText: L10n.t("الصورة الأصلية مع النص المستخرج", "Original image with extracted text")))
            }
        } catch {
            if Task.isCancelled || isCancellation(error) { throw GeminiError.cancelled }
            result.blocks.append(.paragraph(runs: [DocTextRun(text: L10n.t(
                "تعذّر استخراج محتوى موثوق؛ أُدرجت الصورة الأصلية للمراجعة.",
                "Reliable extraction failed; the original image is included for review."))]))
            result.blocks.append(.pageImage(page: 1,
                                            data: imageData,
                                            altText: L10n.t("الصورة الأصلية", "Original image")))
            result.diagnostics.imageFallbackPages = 1
            result.diagnostics.failedPages.append(1)
        }
        result.diagnostics.processedPages = 1
        result.title = url.deletingPathExtension().lastPathComponent
        onProgress?(1, 1)
        return result
    }

    // MARK: - One-page structured analysis

    @MainActor
    private static func convertPage(
        imageData: Data,
        pageNumber: Int,
        totalPages: Int,
        sourceText: String,
        options: DocConvertOptions
    ) async throws -> [DocBlock] {
        var lastError: Error = GeminiError.decode("page conversion failed")
        for attempt in 1...2 {
            do {
                let raw = try await requestPage(
                    imageData: imageData,
                    pageNumber: pageNumber,
                    totalPages: totalPages,
                    sourceText: sourceText,
                    options: options,
                    strictRetry: attempt > 1)
                let object = try parseObject(raw)
                var blocks = try parseSections(object["sections"], page: pageNumber)
                blocks = collapseAdjacentDuplicates(blocks)
                try validate(blocks: blocks,
                             sourceText: sourceText,
                             translationMode: !options.translateTo.isEmpty)
                return blocks
            } catch {
                lastError = error
                if attempt == 1 { try await cancellableDelay(nanoseconds: 900_000_000) }
            }
        }
        throw lastError
    }

    @MainActor
    private static func requestPage(
        imageData: Data,
        pageNumber: Int,
        totalPages: Int,
        sourceText: String,
        options: DocConvertOptions,
        strictRetry: Bool
    ) async throws -> String {
        let settings = BasirSettings.shared
        let outputLanguage = options.translateTo.isEmpty
            ? (settings.language == .arabic ? "Arabic" : "English")
            : GeminiPrompts.bcp47Name(options.translateTo)
        let prompt = GeminiPrompts.documentPageInstruction(
            langName: outputLanguage,
            pageNumber: pageNumber,
            totalPages: totalPages,
            includeImages: options.describeImages,
            translateToName: options.translateTo.isEmpty ? nil : outputLanguage,
            math: options.math,
            strictRetry: strictRetry)

        return try await AiProviderFactory.current().ask(
            task: .convert,
            input: String(sourceText.prefix(24_000)),
            instruction: prompt,
            language: settings.language,
            imageData: imageData,
            mimeType: "image/jpeg")
    }

    // MARK: - Validation and fallback

    private static func validate(
        blocks: [DocBlock],
        sourceText: String,
        translationMode: Bool
    ) throws {
        guard !blocks.isEmpty || sourceText.isEmpty else {
            throw GeminiError.decode("structured page contained no sections")
        }
        let produced = blocks.map(blockText).joined(separator: " ")
        if !sourceText.isEmpty {
            let expectedCritical = AIResponseValidator.criticalTokens(in: sourceText)
            if !expectedCritical.isEmpty {
                let actualCritical = AIResponseValidator.criticalTokens(in: produced)
                let criticalRecall = Double(expectedCritical.intersection(actualCritical).count)
                    / Double(expectedCritical.count)
                guard criticalRecall >= 0.90 else {
                    throw GeminiError.decode("page changed critical numbers, links, or identifiers")
                }
            }
        }
        guard !translationMode, !sourceText.isEmpty else { return }
        let referenceTokens = tokenSet(sourceText)
        guard referenceTokens.count >= 8 else { return }
        let outputTokens = tokenSet(produced)
        let matched = referenceTokens.intersection(outputTokens).count
        let coverage = Double(matched) / Double(referenceTokens.count)
        if coverage < 0.55 {
            throw GeminiError.decode("page text coverage too low")
        }

        let sourceCount = sourceText.filter { !$0.isWhitespace }.count
        let outputCount = produced.filter { !$0.isWhitespace }.count
        if sourceCount >= 80 {
            let ratio = Double(outputCount) / Double(sourceCount)
            if ratio < 0.45 || ratio > 4.0 {
                throw GeminiError.decode("page output length was implausible")
            }
        }

        let critical = criticalTokens(in: sourceText)
        if !critical.isEmpty {
            let output = Set(criticalTokens(in: produced))
            let retained = critical.filter { output.contains($0) }.count
            let recall = Double(retained) / Double(critical.count)
            if recall < 0.85 {
                throw GeminiError.decode("critical identifiers or numbers changed")
            }
        }
    }

    private static func appendFallback(
        pageImage: Data?,
        pageNumber: Int,
        sourceText: String,
        to result: inout Result
    ) {
        if !sourceText.isEmpty {
            result.blocks.append(.paragraph(runs: [DocTextRun(text: L10n.t(
                "نص الصفحة المستخرج محليًا بعد تعذّر التحليل المنظم:",
                "Locally extracted page text after structured analysis failed:"),
                bold: true)]))
            for paragraph in paragraphs(from: sourceText) {
                result.blocks.append(.paragraph(runs: [DocTextRun(text: paragraph)]))
            }
            result.diagnostics.localFallbackPages += 1
            result.diagnostics.warningPages.append(pageNumber)
            return
        }

        let fallbackData = pageImage
        result.blocks.append(.paragraph(runs: [DocTextRun(text: L10n.t(
            "تعذّر استخراج نص موثوق من هذه الصفحة الممسوحة؛ حُفظت صورة الصفحة داخل Word بدل حذفها.",
            "Reliable text could not be extracted from this scanned page; its image was preserved in Word instead of being omitted."))]))
        if let fallbackData {
            result.blocks.append(.pageImage(
                page: pageNumber,
                data: fallbackData,
                altText: L10n.t("صورة الصفحة \(pageNumber)", "Image of page \(pageNumber)")))
            result.diagnostics.imageFallbackPages += 1
            result.diagnostics.warningPages.append(pageNumber)
        } else {
            result.diagnostics.failedPages.append(pageNumber)
        }
    }

    private static func appendUnavailablePage(_ page: Int, to result: inout Result) {
        result.blocks.append(.pageMarker(page))
        result.blocks.append(.paragraph(runs: [DocTextRun(text: L10n.t(
            "تعذّر فتح هذه الصفحة داخل ملف PDF.",
            "This PDF page could not be opened."))]))
        result.diagnostics.failedPages.append(page)
        result.diagnostics.processedPages += 1
    }

    // MARK: - JSON schema and parsing


    private static func parseObject(_ raw: String) throws -> [String: Any] {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = text.firstIndex(of: "{"),
           let last = text.lastIndex(of: "}"), first <= last {
            text = String(text[first...last])
        }
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw GeminiError.decode("malformed JSON") }
        return object
    }

    private static func parseSections(_ raw: Any?, page: Int) throws -> [DocBlock] {
        guard let sections = raw as? [[String: Any]] else {
            throw GeminiError.decode("missing sections")
        }
        guard sections.count <= 600 else {
            throw GeminiError.decode("implausible section count")
        }
        var blocks: [DocBlock] = []
        for section in sections {
            let type = (section["type"] as? String ?? "").lowercased()
            switch type {
            case "heading":
                let level = clamp(intValue(section["level"], fallback: 2), 1, 3)
                let runs = parseRuns(section)
                if !runsText(runs).isEmpty { blocks.append(.heading(level: level, runs: runs)) }
            case "paragraph":
                let runs = parseRuns(section)
                if !runsText(runs).isEmpty { blocks.append(.paragraph(runs: runs)) }
            case "list_item":
                let level = clamp(intValue(section["level"], fallback: 0), 0, 8)
                let ordered = section["ordered"] as? Bool ?? false
                let runs = parseRuns(section)
                if !runsText(runs).isEmpty {
                    blocks.append(.listItem(level: level, ordered: ordered, runs: runs))
                }
            case "table":
                let cells = normalizedCells(section["cells"])
                if !cells.isEmpty {
                    let caption = clean(section["caption"] as? String)
                    let rowHeader = section["row_header"] as? Bool ?? false
                    blocks.append(.table(caption: caption, cells: cells, rowHeader: rowHeader))
                }
            case "image_description":
                let text = clean(section["description"] as? String)
                    ?? clean(section["text"] as? String)
                if let text { blocks.append(.imageDescription(page: page, text: text)) }
            default:
                continue
            }
        }
        return blocks
    }

    private static func parseRuns(_ section: [String: Any]) -> [DocTextRun] {
        if let rawRuns = section["runs"] as? [[String: Any]] {
            let runs = rawRuns.compactMap { raw -> DocTextRun? in
                guard let text = clean(raw["text"] as? String) else { return nil }
                let direction = DocTextRun.Direction(rawValue: raw["direction"] as? String ?? "auto") ?? .auto
                return DocTextRun(
                    text: text,
                    bold: raw["bold"] as? Bool ?? false,
                    italic: raw["italic"] as? Bool ?? false,
                    underline: raw["underline"] as? Bool ?? false,
                    strike: raw["strike"] as? Bool ?? false,
                    highlight: raw["highlight"] as? Bool ?? false,
                    superscript: raw["superscript"] as? Bool ?? false,
                    isSubscript: raw["subscript"] as? Bool ?? false,
                    fontSizePoints: (raw["font_size_pt"] as? NSNumber)?.doubleValue,
                    colorHex: clean(raw["color_hex"] as? String),
                    url: clean(raw["url"] as? String),
                    direction: direction)
            }
            if !runs.isEmpty { return runs }
        }
        if let text = clean(section["text"] as? String) { return [DocTextRun(text: text)] }
        return []
    }

    private static func normalizedCells(_ raw: Any?) -> [[String]] {
        guard let rows = raw as? [[Any]], !rows.isEmpty, rows.count <= 500 else { return [] }
        var converted = rows.map { row in
            row.map { value -> String in
                if let string = value as? String { return string }
                if let number = value as? NSNumber { return number.stringValue }
                return ""
            }
        }
        let width = converted.map(\.count).max() ?? 0
        guard width > 0, width <= 50, width * converted.count <= 5_000 else { return [] }
        for index in converted.indices {
            if converted[index].count < width {
                converted[index].append(contentsOf: repeatElement("", count: width - converted[index].count))
            } else if converted[index].count > width {
                converted[index] = Array(converted[index].prefix(width))
            }
        }
        return converted
    }

    // MARK: - Retry, rotation, and helpers

    private static func isTransient(_ error: Error) -> Bool {
        switch error {
        case GeminiError.network:
            return true
        case let GeminiError.http(status, _):
            return status == 408 || status == 429 || (500...599).contains(status)
        default:
            return false
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if case GeminiError.cancelled = error { return true }
        return false
    }

    private static func cancellableDelay(nanoseconds: UInt64) async throws {
        try Task.checkCancellation()
        do { try await Task.sleep(nanoseconds: nanoseconds) }
        catch { throw GeminiError.cancelled }
    }

    /// Removes only accidental immediate duplicates. A global Set is unsafe
    /// because legitimate documents often repeat headings, disclaimers, or
    /// table rows on the same page.
    private static func collapseAdjacentDuplicates(_ blocks: [DocBlock]) -> [DocBlock] {
        var output: [DocBlock] = []
        for block in blocks {
            let fingerprint = normalized(blockText(block))
            let previous = output.last.map { normalized(blockText($0)) }
            if !fingerprint.isEmpty, fingerprint == previous { continue }
            output.append(block)
        }
        return output
    }

    private static func tokenSet(_ text: String) -> Set<String> {
        Set(text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 })
    }

    private static func criticalTokens(in text: String) -> [String] {
        let pattern = #"https?://[^\s<>]+|[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}|\+?\d[\d\s.,:/\-]{2,}\d|[A-Za-z]+[A-Za-z0-9._/\-]*\d[A-Za-z0-9._/\-]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return text[swiftRange]
                .trimmingCharacters(in: CharacterSet(charactersIn: ".،؛;:!?؟)]}"))
                .replacingOccurrences(of: " ", with: "")
                .lowercased()
        }
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func paragraphs(from text: String) -> [String] {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func conversionError(_ code: Int, ar: String, en: String) -> NSError {
        NSError(domain: "BasirConvert", code: code,
                userInfo: [NSLocalizedDescriptionKey: L10n.t(ar, en)])
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    private static func intValue(_ value: Any?, fallback: Int) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String, let number = Int(string) { return number }
        return fallback
    }

    private static func clamp(_ value: Int, _ lower: Int, _ upper: Int) -> Int {
        min(max(value, lower), upper)
    }

    private static func runsText(_ runs: [DocTextRun]) -> String {
        runs.map(\.text).joined()
    }

    private static func blockText(_ block: DocBlock) -> String {
        switch block {
        case .pageMarker(let page): return "Page \(page)"
        case .pageBreak: return ""
        case .heading(_, let runs), .paragraph(let runs), .listItem(_, _, let runs):
            return runsText(runs)
        case .imageDescription(_, let text): return text
        case .pageImage(_, _, let altText): return altText
        case .table(let caption, let cells, _):
            return ([caption].compactMap { $0 } + cells.flatMap { $0 }).joined(separator: " ")
        }
    }

    private static func firstHeading(in blocks: [DocBlock]) -> String? {
        for block in blocks {
            if case let .heading(level, runs) = block, level == 1 {
                let text = runsText(runs).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
        }
        return nil
    }

    // MARK: - Screen-reader display and DOCX export

    static func displayText(_ result: Result) -> String {
        var lines: [String] = []
        for block in result.blocks {
            switch block {
            case .pageMarker(let page):
                lines.append(L10n.t("صفحة \(page)", "Page \(page)"))
            case .pageBreak:
                continue
            case .heading(_, let runs):
                lines.append(runsText(runs))
            case .paragraph(let runs):
                lines.append(runsText(runs))
            case .listItem(let level, let ordered, let runs):
                let indentation = String(repeating: "  ", count: max(0, level))
                let prefix = ordered ? "1." : "•"
                lines.append("\(indentation)\(prefix) \(runsText(runs))")
            case .imageDescription(let page, let text):
                lines.append(L10n.t("وصف صورة في الصفحة \(page): \(text)",
                                    "Image description on page \(page): \(text)"))
            case .pageImage(let page, _, let altText):
                lines.append(L10n.t("صورة محفوظة للصفحة \(page): \(altText)",
                                    "Preserved image for page \(page): \(altText)"))
            case .table(let caption, let cells, _):
                if let caption { lines.append(caption) }
                lines.append(renderTableText(cells))
            }
        }
        lines.append(L10n.t(result.diagnostics.summaryArabic,
                            result.diagnostics.summaryEnglish))
        return lines.joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func renderTableText(_ cells: [[String]]) -> String {
        guard let header = cells.first else { return "" }
        if cells.count == 1 { return header.joined(separator: " | ") }
        return cells.dropFirst().enumerated().map { rowIndex, row in
            let parts = row.enumerated().compactMap { column, value -> String? in
                guard !value.isEmpty else { return nil }
                let label = column < header.count ? header[column] : ""
                return label.isEmpty ? value : "\(label): \(value)"
            }
            return L10n.t("صف \(rowIndex + 1): ", "Row \(rowIndex + 1): ")
                + parts.joined(separator: "، ")
        }.joined(separator: "\n")
    }

    static func buildDocx(_ result: Result, rtl: Bool, to url: URL) throws {
        var writer = DocxWriter(rtl: rtl)
        for block in result.blocks {
            switch block {
            case .pageMarker(let page):
                writer.append(.paragraph(
                    runs: [DocxWriter.Run(text: L10n.t("صفحة \(page)", "Page \(page)"),
                                          bold: true)]))
            case .pageBreak:
                writer.append(.pageBreak)
            case .heading(let level, let runs):
                writer.append(.heading(level: level, runs: runs.map(DocxWriter.Run.init)))
            case .paragraph(let runs):
                writer.append(.paragraph(runs: runs.map(DocxWriter.Run.init)))
            case .listItem(let level, let ordered, let runs):
                writer.append(.listItem(level: level,
                                        ordered: ordered,
                                        runs: runs.map(DocxWriter.Run.init)))
            case .imageDescription(let page, let text):
                writer.append(.paragraph(runs: [DocxWriter.Run(text: L10n.t(
                    "وصف صورة في الصفحة \(page): \(text)",
                    "Image description on page \(page): \(text)"))]))
            case .pageImage(_, let data, let altText):
                writer.append(.image(data: data, mimeType: "image/jpeg", altText: altText))
            case .table(let caption, let cells, let rowHeader):
                if let caption {
                    writer.append(.paragraph(runs: [DocxWriter.Run(text: caption, bold: true)]))
                }
                writer.append(.table(rows: cells, rowHeader: rowHeader))
            }
        }
        writer.append(.paragraph(runs: [DocxWriter.Run(
            text: L10n.t(result.diagnostics.summaryArabic,
                         result.diagnostics.summaryEnglish),
            italic: true)]))
        try writer.write(to: url)
    }
}

private extension DocxWriter.Run {
    init(_ run: DocTextRun) {
        self.init(text: run.text,
                  bold: run.bold,
                  italic: run.italic,
                  underline: run.underline,
                  strike: run.strike,
                  highlight: run.highlight,
                  superscript: run.superscript,
                  isSubscript: run.isSubscript,
                  fontSizePoints: run.fontSizePoints,
                  colorHex: run.colorHex,
                  url: run.url,
                  direction: DocxWriter.Run.Direction(rawValue: run.direction.rawValue) ?? .auto)
    }
}
