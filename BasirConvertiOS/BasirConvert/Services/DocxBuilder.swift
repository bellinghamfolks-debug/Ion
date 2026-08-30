import Foundation
import ZIPFoundation

final class DocxBuilder {
    private struct TableBlock {
        let cells: [[String]]
        let headerRow: Bool
        let headerColumn: Bool
        let caption: String
        let description: String
    }

    private struct ImageBlock {
        let data: Data
        let extensionName: String
        let contentType: String
        let pixelWidth: Int
        let pixelHeight: Int
        let altText: String
        let title: String
        let maximumWidthInches: Double
    }

    private struct HyperlinkBlock {
        let url: String
        let text: String
    }

    private struct ListBlock {
        let text: String
        let ordered: Bool
        let level: Int
    }

    private enum Block {
        case title(String)
        case heading(Int, String)
        case paragraph(String)
        case hyperlink(HyperlinkBlock)
        case list(ListBlock)
        case equation(String)
        case table(TableBlock)
        case image(ImageBlock)
        case pageBreak
    }

    private var blocks: [Block] = []
    private let baseLanguage: String

    init(language: String) {
        let value = language.trimmingCharacters(in: .whitespacesAndNewlines)
        baseLanguage = value.isEmpty ? "auto" : value
    }

    @discardableResult
    func title(_ text: String) -> Self {
        let value = Self.clean(text)
        if !value.isEmpty { blocks.append(.title(value)) }
        return self
    }

    @discardableResult
    func heading(_ level: Int, _ text: String) -> Self {
        let value = Self.clean(text)
        if !value.isEmpty { blocks.append(.heading(max(1, min(6, level)), value)) }
        return self
    }

    @discardableResult
    func paragraph(_ text: String) -> Self {
        let value = Self.clean(text)
        if !value.isEmpty { blocks.append(.paragraph(value)) }
        return self
    }

    @discardableResult
    func hyperlink(_ url: String, text: String) -> Self {
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanText = Self.clean(text)
        guard let components = URLComponents(string: cleanURL),
              let scheme = components.scheme?.lowercased(),
              ["https", "http", "mailto"].contains(scheme),
              !cleanText.isEmpty else { return paragraph(cleanText) }
        blocks.append(.hyperlink(.init(url: cleanURL, text: cleanText)))
        return self
    }

    @discardableResult
    func listItem(_ text: String, ordered: Bool, level: Int = 0) -> Self {
        let value = Self.clean(text)
        if !value.isEmpty {
            blocks.append(.list(.init(text: value, ordered: ordered, level: max(0, min(8, level)))))
        }
        return self
    }

    /// Writes a native Word OMML equation block. The source expression is kept
    /// verbatim so translation never corrupts mathematical symbols.
    @discardableResult
    func equation(_ expression: String) -> Self {
        let value = Self.clean(expression)
        if !value.isEmpty { blocks.append(.equation(value)) }
        return self
    }

    @discardableResult
    func pageBreak() -> Self {
        blocks.append(.pageBreak)
        return self
    }

    @discardableResult
    func table(
        _ cells: [[String]],
        headerRow: Bool = true,
        headerColumn: Bool = false,
        caption: String = "",
        description: String = ""
    ) -> Self {
        let width = cells.map(\.count).max() ?? 0
        guard width > 0, !cells.isEmpty else { return self }
        let padded = cells.map { row -> [String] in
            var copy = row.map(Self.clean)
            while copy.count < width { copy.append("") }
            return copy
        }
        blocks.append(.table(TableBlock(
            cells: padded,
            headerRow: headerRow,
            headerColumn: headerColumn,
            caption: Self.clean(caption),
            description: Self.clean(description)
        )))
        return self
    }

    @discardableResult
    func image(
        _ prepared: PreparedImage,
        altText: String,
        title: String,
        maximumWidthInches: Double
    ) -> Self {
        guard !prepared.data.isEmpty, prepared.pixelWidth > 0, prepared.pixelHeight > 0 else { return self }
        let mime = prepared.mimeType.lowercased()
        let extensionName: String
        let contentType: String
        switch mime {
        case "image/png":
            extensionName = "png"; contentType = "image/png"
        case "image/gif":
            extensionName = "gif"; contentType = "image/gif"
        default:
            extensionName = "jpg"; contentType = "image/jpeg"
        }
        var safeAlt = Self.clean(altText)
        if safeAlt.isEmpty { safeAlt = defaultRTL ? "صورة من المستند" : "Image from the document" }
        var safeTitle = Self.clean(title)
        if safeTitle.isEmpty { safeTitle = defaultRTL ? "صورة" : "Image" }
        blocks.append(.image(ImageBlock(
            data: prepared.data,
            extensionName: extensionName,
            contentType: contentType,
            pixelWidth: prepared.pixelWidth,
            pixelHeight: prepared.pixelHeight,
            altText: safeAlt,
            title: safeTitle,
            maximumWidthInches: max(0.5, min(6.6, maximumWidthInches))
        )))
        return self
    }

    var imageCount: Int {
        blocks.reduce(0) { count, block in
            if case .image = block { return count + 1 }
            return count
        }
    }

    var tableCount: Int {
        blocks.reduce(0) { count, block in
            if case .table = block { return count + 1 }
            return count
        }
    }

    var isEmpty: Bool { blocks.isEmpty }

    func write(to outputURL: URL) throws {
        let fileManager = FileManager.default
        let package = fileManager.temporaryDirectory
            .appendingPathComponent("BasirDocx-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: package, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: package) }

        try writePackage(to: package)
        try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        try fileManager.zipItem(at: package, to: outputURL,
                                shouldKeepParent: false,
                                compressionMethod: .deflate)
    }

    private func writePackage(to root: URL) throws {
        let fileManager = FileManager.default
        let directories = [
            "_rels", "docProps", "word", "word/_rels", "word/media"
        ]
        for directory in directories {
            try fileManager.createDirectory(
                at: root.appendingPathComponent(directory, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        try write(contentTypesXML, to: root.appendingPathComponent("[Content_Types].xml"))
        try write(rootRelationshipsXML, to: root.appendingPathComponent("_rels/.rels"))
        try write(corePropertiesXML, to: root.appendingPathComponent("docProps/core.xml"))
        try write(appPropertiesXML, to: root.appendingPathComponent("docProps/app.xml"))
        try write(documentRelationshipsXML, to: root.appendingPathComponent("word/_rels/document.xml.rels"))
        try write(stylesXML, to: root.appendingPathComponent("word/styles.xml"))
        try write(numberingXML, to: root.appendingPathComponent("word/numbering.xml"))
        try write(settingsXML, to: root.appendingPathComponent("word/settings.xml"))
        try write(documentXML, to: root.appendingPathComponent("word/document.xml"))

        var index = 0
        for block in blocks {
            guard case .image(let image) = block else { continue }
            index += 1
            let target = root.appendingPathComponent("word/media/image\(index).\(image.extensionName)")
            try image.data.write(to: target, options: .atomic)
        }
    }

    private func write(_ value: String, to url: URL) throws {
        try Data(value.utf8).write(to: url, options: .atomic)
    }

    private var documentXML: String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        xml += "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" "
        xml += "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" "
        xml += "xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" "
        xml += "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" "
        xml += "xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\" "
        xml += "xmlns:m=\"http://schemas.openxmlformats.org/officeDocument/2006/math\">"
        xml += "<w:body>"
        var imageIndex = 0
        var hyperlinkIndex = 0
        for block in blocks {
            switch block {
            case .title(let text):
                xml += paragraphXML(text, style: "Title", halfPointSize: 44)
            case .heading(let level, let text):
                let size = level == 1 ? 30 : (level == 2 ? 26 : (level <= 4 ? 22 : 20))
                xml += paragraphXML(text, style: "Heading\(level)", halfPointSize: size)
            case .paragraph(let text):
                xml += paragraphXML(text, style: "Normal", halfPointSize: 20)
            case .hyperlink(let link):
                hyperlinkIndex += 1
                xml += hyperlinkXML(link, index: hyperlinkIndex)
            case .list(let item):
                xml += listXML(item)
            case .equation(let expression):
                xml += equationXML(expression)
            case .table(let table):
                xml += tableXML(table)
            case .image(let image):
                imageIndex += 1
                xml += imageXML(image, index: imageIndex)
            case .pageBreak:
                xml += "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\"/></w:pPr>"
                xml += "<w:r><w:br w:type=\"page\"/></w:r></w:p>"
            }
        }
        xml += "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/>"
        xml += "<w:pgMar w:top=\"1134\" w:right=\"765\" w:bottom=\"680\" w:left=\"765\" "
        xml += "w:header=\"425\" w:footer=\"255\" w:gutter=\"0\"/></w:sectPr>"
        xml += "</w:body></w:document>"
        return xml
    }

    private func equationXML(_ expression: String) -> String {
        let rtl = isRTL(expression)
        var xml = "<m:oMathPara><m:oMath><m:r><w:rPr>"
        if rtl { xml += "<w:rtl/>" }
        xml += "<w:rFonts w:ascii=\"Cambria Math\" w:hAnsi=\"Cambria Math\"/>"
        xml += "</w:rPr><m:t xml:space=\"preserve\">\(Self.escape(expression))</m:t>"
        xml += "</m:r></m:oMath></m:oMathPara>"
        return xml
    }

    private func hyperlinkXML(_ link: HyperlinkBlock, index: Int) -> String {
        let rtl = isRTL(link.text)
        var xml = "<w:p><w:pPr>"
        if rtl { xml += "<w:bidi/>" }
        xml += "<w:jc w:val=\"\(rtl ? "right" : "left")\"/></w:pPr>"
        xml += "<w:hyperlink r:id=\"rIdLink\(index)\" w:history=\"1\"><w:r><w:rPr>"
        xml += "<w:rStyle w:val=\"Hyperlink\"/><w:color w:val=\"0563C1\"/><w:u w:val=\"single\"/>"
        if rtl { xml += "<w:rtl/>" }
        xml += "</w:rPr><w:t xml:space=\"preserve\">\(Self.escape(link.text))</w:t></w:r></w:hyperlink></w:p>"
        return xml
    }

    private func listXML(_ item: ListBlock) -> String {
        let rtl = isRTL(item.text)
        var xml = "<w:p><w:pPr><w:numPr><w:ilvl w:val=\"\(item.level)\"/>"
        xml += "<w:numId w:val=\"\(item.ordered ? 2 : 1)\"/></w:numPr>"
        if rtl { xml += "<w:bidi/><w:jc w:val=\"right\"/>" }
        xml += "</w:pPr>"
        xml += runsXML(item.text, halfPointSize: 20, bold: false, rtl: rtl)
        xml += "</w:p>"
        return xml
    }

    private func paragraphXML(_ text: String, style: String, halfPointSize: Int) -> String {
        let rtl = isRTL(text)
        let isHeading = style == "Title" || style.hasPrefix("Heading")
        var xml = "<w:p><w:pPr><w:pStyle w:val=\"\(style)\"/>"
        if rtl { xml += "<w:bidi/>" }
        xml += "<w:jc w:val=\"\(isHeading ? "center" : (rtl ? "right" : "left"))\"/>"
        if isHeading { xml += "<w:keepNext/>" }
        xml += "<w:spacing w:before=\"0\" w:after=\"\(isHeading ? 60 : 40)\" "
        xml += "w:line=\"240\" w:lineRule=\"auto\"/></w:pPr>"
        xml += runsXML(text, halfPointSize: halfPointSize, bold: false, rtl: rtl)
        xml += "</w:p>"
        return xml
    }

    private func runsXML(_ text: String, halfPointSize: Int, bold: Bool, rtl: Bool) -> String {
        let lines = text.components(separatedBy: .newlines)
        let language = languageTag(for: text, rtl: rtl)
        var xml = ""
        for (index, line) in lines.enumerated() {
            let segments = Self.inlineSegments(line)
            for (segmentIndex, segment) in segments.enumerated() {
                xml += "<w:r><w:rPr>"
                if rtl { xml += "<w:rtl/>" }
                if bold || segment.bold { xml += "<w:b/><w:bCs/>" }
                if segment.italic { xml += "<w:i/><w:iCs/>" }
                if segment.underline { xml += "<w:u w:val=\"single\"/>" }
                if segment.strike { xml += "<w:strike/>" }
                xml += "<w:rFonts w:ascii=\"Arial\" w:hAnsi=\"Arial\" w:eastAsia=\"Arial\" w:cs=\"Arial\"/>"
                xml += "<w:sz w:val=\"\(halfPointSize)\"/><w:szCs w:val=\"\(halfPointSize)\"/>"
                xml += "<w:lang w:val=\"\(Self.escapeAttribute(language))\" "
                xml += "w:bidi=\"\(Self.escapeAttribute(language))\"/></w:rPr>"
                let value = segment.text.isEmpty ? "&#160;" : Self.escape(segment.text)
                xml += "<w:t xml:space=\"preserve\">\(value)</w:t>"
                if index < lines.count - 1, segmentIndex == segments.count - 1 { xml += "<w:br/>" }
                xml += "</w:r>"
            }
        }
        return xml
    }

    private struct InlineSegment {
        let text: String
        let bold: Bool
        let italic: Bool
        let underline: Bool
        let strike: Bool
    }

    private static func inlineSegments(_ text: String) -> [InlineSegment] {
        guard !text.isEmpty else {
            return [.init(text: "", bold: false, italic: false, underline: false, strike: false)]
        }
        let markers: [(open: String, close: String, style: Int)] = [
            ("**", "**", 1), ("__", "__", 1), ("~~", "~~", 4),
            ("<u>", "</u>", 3), ("_", "_", 2), ("*", "*", 2)
        ]
        var result: [InlineSegment] = []
        var cursor = text.startIndex
        while cursor < text.endIndex {
            var earliest: (Range<String.Index>, String, Int)?
            for marker in markers {
                if let range = text.range(of: marker.open, range: cursor..<text.endIndex),
                   earliest == nil || range.lowerBound < earliest!.0.lowerBound {
                    earliest = (range, marker.close, marker.style)
                }
            }
            guard let match = earliest else {
                result.append(.init(text: String(text[cursor...]), bold: false, italic: false,
                                    underline: false, strike: false))
                break
            }
            if cursor < match.0.lowerBound {
                result.append(.init(text: String(text[cursor..<match.0.lowerBound]), bold: false,
                                    italic: false, underline: false, strike: false))
            }
            let contentStart = match.0.upperBound
            guard let closing = text.range(of: match.1, range: contentStart..<text.endIndex) else {
                result.append(.init(text: String(text[match.0.lowerBound...]), bold: false,
                                    italic: false, underline: false, strike: false))
                break
            }
            result.append(.init(
                text: String(text[contentStart..<closing.lowerBound]),
                bold: match.2 == 1,
                italic: match.2 == 2,
                underline: match.2 == 3,
                strike: match.2 == 4
            ))
            cursor = closing.upperBound
        }
        return result.isEmpty
            ? [.init(text: text, bold: false, italic: false, underline: false, strike: false)]
            : result
    }

    private func tableXML(_ table: TableBlock) -> String {
        guard let first = table.cells.first, !first.isEmpty else { return "" }
        let columns = first.count
        let widths = columnWidths(table.cells, total: 10_000)
        let spanningTitle = isSpanningTitleRow(first)
        let headerIndex = table.headerRow ? (spanningTitle && table.cells.count > 1 ? 1 : 0) : -1
        let fontSize = columns >= 7 ? 14 : (columns >= 5 ? 16 : 18)

        var xml = "<w:tbl><w:tblPr><w:tblStyle w:val=\"TableGrid\"/>"
        xml += "<w:tblW w:w=\"5000\" w:type=\"pct\"/><w:tblLayout w:type=\"fixed\"/>"
        xml += "<w:jc w:val=\"center\"/>"
        if !table.caption.isEmpty {
            xml += "<w:tblCaption w:val=\"\(Self.escapeAttribute(table.caption))\"/>"
        }
        if !table.description.isEmpty {
            xml += "<w:tblDescription w:val=\"\(Self.escapeAttribute(table.description))\"/>"
        }
        xml += "<w:tblBorders>"
        for edge in ["top", "left", "bottom", "right", "insideH", "insideV"] {
            xml += "<w:\(edge) w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"94A3B8\"/>"
        }
        xml += "</w:tblBorders><w:tblCellMar>"
        for edge in ["top", "left", "bottom", "right"] {
            xml += "<w:\(edge) w:w=\"55\" w:type=\"dxa\"/>"
        }
        xml += "</w:tblCellMar><w:tblLook w:val=\"04A0\" w:firstRow=\"1\" w:lastRow=\"0\" "
        xml += "w:firstColumn=\"\(table.headerColumn ? 1 : 0)\" w:lastColumn=\"0\" "
        xml += "w:noHBand=\"0\" w:noVBand=\"1\"/></w:tblPr><w:tblGrid>"
        for width in widths { xml += "<w:gridCol w:w=\"\(width)\"/>" }
        xml += "</w:tblGrid>"

        for (rowIndex, row) in table.cells.enumerated() {
            let totalRow = isTotalRow(row)
            xml += "<w:tr><w:trPr><w:cantSplit/>"
            if rowIndex == headerIndex { xml += "<w:tblHeader/>" }
            xml += "</w:trPr>"

            if rowIndex == 0, spanningTitle {
                let value = row.first(where: { !Self.clean($0).isEmpty }) ?? ""
                xml += "<w:tc><w:tcPr><w:tcW w:w=\"10000\" w:type=\"dxa\"/>"
                xml += "<w:gridSpan w:val=\"\(columns)\"/><w:shd w:fill=\"DBEAFE\"/></w:tcPr>"
                xml += tableCellParagraph(value, bold: true, fontSize: max(16, fontSize), fillRTL: isRTL(value))
                xml += "</w:tc>"
            } else {
                var column = 0
                while column < columns {
                    var value = column < row.count ? row[column] : ""
                    if value == "[[BASIR_MERGED]]" { column += 1; continue }
                    let span = Self.extractIntMarker("BASIR_GRIDSPAN", from: &value) ?? 1
                    let verticalMerge = Self.extractStringMarker("BASIR_VMERGE", from: &value)
                    let header = rowIndex == headerIndex || (table.headerColumn && column == 0)
                    let fill = header ? "DCEAF7" : (totalRow ? "E8F5E9" : "FFFFFF")
                    let combinedWidth = widths[column..<min(columns, column + span)].reduce(0, +)
                    xml += "<w:tc><w:tcPr><w:tcW w:w=\"\(combinedWidth)\" w:type=\"dxa\"/>"
                    if span > 1 { xml += "<w:gridSpan w:val=\"\(span)\"/>" }
                    if let verticalMerge {
                        xml += verticalMerge == "restart" ? "<w:vMerge w:val=\"restart\"/>" : "<w:vMerge/>"
                    }
                    xml += "<w:shd w:val=\"clear\" w:fill=\"\(fill)\"/></w:tcPr>"
                    xml += tableCellParagraph(value, bold: header || totalRow,
                                              fontSize: fontSize, fillRTL: isRTL(value))
                    xml += "</w:tc>"
                    column += max(1, span)
                }
            }
            xml += "</w:tr>"
        }
        xml += "</w:tbl>"
        return xml
    }

    private func tableCellParagraph(_ value: String, bold: Bool, fontSize: Int, fillRTL: Bool) -> String {
        var xml = "<w:p><w:pPr>"
        if fillRTL { xml += "<w:bidi/>" }
        xml += "<w:jc w:val=\"\(fillRTL ? "right" : "left")\"/>"
        xml += "<w:spacing w:before=\"0\" w:after=\"0\" w:line=\"210\" w:lineRule=\"auto\"/>"
        xml += "</w:pPr>"
        xml += runsXML(value.isEmpty ? "\u{00A0}" : value,
                       halfPointSize: fontSize, bold: bold, rtl: fillRTL)
        xml += "</w:p>"
        return xml
    }

    private func imageXML(_ image: ImageBlock, index: Int) -> String {
        let emuPerPixel: Int64 = 9_525
        let emuPerInch: Int64 = 914_400
        var width = max(1, Int64(image.pixelWidth) * emuPerPixel)
        var height = max(1, Int64(image.pixelHeight) * emuPerPixel)
        let maximumWidth = max(emuPerInch / 2, Int64(image.maximumWidthInches * Double(emuPerInch)))
        let maximumHeight = Int64(8.7 * Double(emuPerInch))
        let scale = min(1, min(Double(maximumWidth) / Double(width),
                               Double(maximumHeight) / Double(height)))
        width = max(1, Int64(Double(width) * scale))
        height = max(1, Int64(Double(height) * scale))
        let drawingID = 1_000 + index
        let name = Self.escapeAttribute(image.title)
        let alt = Self.escapeAttribute(image.altText)

        var xml = "<w:p><w:pPr><w:jc w:val=\"center\"/>"
        xml += "<w:spacing w:before=\"40\" w:after=\"40\"/></w:pPr><w:r><w:drawing>"
        xml += "<wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\">"
        xml += "<wp:extent cx=\"\(width)\" cy=\"\(height)\"/>"
        xml += "<wp:effectExtent l=\"0\" t=\"0\" r=\"0\" b=\"0\"/>"
        xml += "<wp:docPr id=\"\(drawingID)\" name=\"\(name)\" descr=\"\(alt)\"/>"
        xml += "<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect=\"1\"/></wp:cNvGraphicFramePr>"
        xml += "<a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\">"
        xml += "<pic:pic><pic:nvPicPr><pic:cNvPr id=\"\(drawingID)\" name=\"\(name)\" descr=\"\(alt)\"/>"
        xml += "<pic:cNvPicPr/></pic:nvPicPr><pic:blipFill>"
        xml += "<a:blip r:embed=\"rIdImage\(index)\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>"
        xml += "<pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(width)\" cy=\"\(height)\"/>"
        xml += "</a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>"
        xml += "</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>"
        return xml
    }

    private func columnWidths(_ rows: [[String]], total: Int) -> [Int] {
        guard let columns = rows.first?.count, columns > 0 else { return [] }
        var weights = [Double](repeating: 1, count: columns)
        var sum = 0.0
        for column in 0..<columns {
            let header = Self.normalizeHeader(rows.first?[column] ?? "")
            let shortHeader = Self.isShortHeader(header)
            var maximumLength = 0
            var compact = true
            for row in rows {
                let value = column < row.count ? row[column] : ""
                maximumLength = max(maximumLength, Self.visibleLength(value))
                if !value.isEmpty, !Self.isCompactValue(value) { compact = false }
            }
            let weight: Double
            if shortHeader || (compact && maximumLength <= 18) {
                weight = 1
            } else {
                weight = max(1.4, min(4.6, 1.2 + sqrt(Double(maximumLength)) * 0.55))
            }
            weights[column] = weight
            sum += weight
        }
        var result = [Int](repeating: 0, count: columns)
        var assigned = 0
        for column in 0..<columns {
            result[column] = column == columns - 1
                ? total - assigned
                : max(420, Int((Double(total) * weights[column] / sum).rounded()))
            assigned += result[column]
        }
        if assigned != total { result[columns - 1] += total - assigned }
        return result
    }

    private func isRTL(_ text: String) -> Bool {
        var rtlCount = 0
        var latinCount = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF:
                rtlCount += 1
            case 0x0041...0x005A, 0x0061...0x007A:
                latinCount += 1
            default:
                break
            }
        }
        if rtlCount == latinCount { return defaultRTL }
        return rtlCount > latinCount
    }

    private var defaultRTL: Bool {
        let code = baseLanguage.lowercased()
        return code.hasPrefix("ar") || code.hasPrefix("he")
            || code.hasPrefix("fa") || code.hasPrefix("ur")
    }

    private func languageTag(for text: String, rtl: Bool) -> String {
        if rtl {
            if baseLanguage.lowercased().hasPrefix("fa") { return "fa-IR" }
            if baseLanguage.lowercased().hasPrefix("ur") { return "ur-PK" }
            if baseLanguage.lowercased().hasPrefix("he") { return "he-IL" }
            return "ar-SA"
        }
        if baseLanguage == "auto" || defaultRTL { return "en-US" }
        return baseLanguage
    }

    private func isSpanningTitleRow(_ row: [String]) -> Bool {
        let populated = row.map(Self.clean).filter { !$0.isEmpty }
        return row.count >= 2 && populated.count == 1 && populated[0].count <= 120
    }

    private func isTotalRow(_ row: [String]) -> Bool {
        row.contains { value in
            let normalized = Self.normalizeHeader(value)
            return ["المجموع", "الإجمالي", "total", "sum"].contains(normalized)
        }
    }

    private var stylesXML: String {
        let header = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        var xml = header + "<w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
        xml += "<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"Arial\" w:hAnsi=\"Arial\" "
        xml += "w:eastAsia=\"Arial\" w:cs=\"Arial\"/><w:sz w:val=\"20\"/><w:szCs w:val=\"20\"/>"
        xml += "</w:rPr></w:rPrDefault></w:docDefaults>"
        xml += "<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\">"
        xml += "<w:name w:val=\"Normal\"/><w:qFormat/></w:style>"
        xml += styleXML(id: "Title", name: "Title", color: "0F172A", outline: nil)
        for level in 1...6 {
            let color = level == 1 ? "0D47A1" : (level == 2 ? "1565C0" : "1976D2")
            xml += styleXML(id: "Heading\(level)", name: "heading \(level)",
                            color: color, outline: level - 1)
        }
        xml += "<w:style w:type=\"table\" w:styleId=\"TableGrid\"><w:name w:val=\"Table Grid\"/>"
        xml += "<w:tblPr><w:tblBorders>"
        for edge in ["top", "left", "bottom", "right", "insideH", "insideV"] {
            xml += "<w:\(edge) w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"94A3B8\"/>"
        }
        xml += "</w:tblBorders></w:tblPr></w:style></w:styles>"
        return xml
    }

    private func styleXML(id: String, name: String, color: String, outline: Int?) -> String {
        var xml = "<w:style w:type=\"paragraph\" w:styleId=\"\(id)\"><w:name w:val=\"\(name)\"/>"
        xml += "<w:basedOn w:val=\"Normal\"/><w:next w:val=\"Normal\"/><w:qFormat/>"
        xml += "<w:pPr><w:spacing w:before=\"120\" w:after=\"40\"/><w:keepNext/>"
        if let outline { xml += "<w:outlineLvl w:val=\"\(outline)\"/>" }
        xml += "</w:pPr><w:rPr><w:b/><w:bCs/><w:color w:val=\"\(color)\"/></w:rPr></w:style>"
        return xml
    }

    private var contentTypesXML: String {
        var jpeg = false
        var png = false
        var gif = false
        for block in blocks {
            guard case .image(let image) = block else { continue }
            if image.extensionName == "png" { png = true }
            else if image.extensionName == "gif" { gif = true }
            else { jpeg = true }
        }
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        xml += "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
        xml += "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
        xml += "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        if jpeg { xml += "<Default Extension=\"jpg\" ContentType=\"image/jpeg\"/>" }
        if png { xml += "<Default Extension=\"png\" ContentType=\"image/png\"/>" }
        if gif { xml += "<Default Extension=\"gif\" ContentType=\"image/gif\"/>" }
        xml += "<Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>"
        xml += "<Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/>"
        xml += "<Override PartName=\"/word/settings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml\"/>"
        xml += "<Override PartName=\"/word/numbering.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml\"/>"
        xml += "<Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/>"
        xml += "<Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/>"
        xml += "</Types>"
        return xml
    }

    private var documentRelationshipsXML: String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        xml += "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        xml += "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        xml += "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings\" Target=\"settings.xml\"/>"
        xml += "<Relationship Id=\"rIdNumbering\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering\" Target=\"numbering.xml\"/>"
        var index = 0
        for block in blocks {
            guard case .image(let image) = block else { continue }
            index += 1
            xml += "<Relationship Id=\"rIdImage\(index)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" "
            xml += "Target=\"media/image\(index).\(image.extensionName)\"/>"
        }
        var hyperlinkIndex = 0
        for block in blocks {
            guard case .hyperlink(let link) = block else { continue }
            hyperlinkIndex += 1
            xml += "<Relationship Id=\"rIdLink\(hyperlinkIndex)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" "
            xml += "Target=\"\(Self.escapeAttribute(link.url))\" TargetMode=\"External\"/>"
        }
        xml += "</Relationships>"
        return xml
    }

    private var numberingXML: String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        xml += "<w:numbering xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
        xml += "<w:abstractNum w:abstractNumId=\"1\"><w:multiLevelType w:val=\"hybridMultilevel\"/>"
        for level in 0...8 {
            xml += "<w:lvl w:ilvl=\"\(level)\"><w:start w:val=\"1\"/><w:numFmt w:val=\"bullet\"/>"
            xml += "<w:lvlText w:val=\"•\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"\(720 + level * 360)\" w:hanging=\"360\"/></w:pPr></w:lvl>"
        }
        xml += "</w:abstractNum><w:abstractNum w:abstractNumId=\"2\"><w:multiLevelType w:val=\"multilevel\"/>"
        for level in 0...8 {
            xml += "<w:lvl w:ilvl=\"\(level)\"><w:start w:val=\"1\"/><w:numFmt w:val=\"decimal\"/>"
            xml += "<w:lvlText w:val=\"%\(level + 1).\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"\(720 + level * 360)\" w:hanging=\"360\"/></w:pPr></w:lvl>"
        }
        xml += "</w:abstractNum><w:num w:numId=\"1\"><w:abstractNumId w:val=\"1\"/></w:num>"
        xml += "<w:num w:numId=\"2\"><w:abstractNumId w:val=\"2\"/></w:num></w:numbering>"
        return xml
    }

    private var rootRelationshipsXML: String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        + "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/>"
        + "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/>"
        + "<Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties\" Target=\"docProps/app.xml\"/>"
        + "</Relationships>"
    }

    private var settingsXML: String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        + "<w:settings xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
        + "<w:zoom w:percent=\"100\"/><w:defaultTabStop w:val=\"720\"/>"
        + "<w:compat><w:compatSetting w:name=\"compatibilityMode\" "
        + "w:uri=\"http://schemas.microsoft.com/office/word\" w:val=\"15\"/></w:compat>"
        + "</w:settings>"
    }

    private var corePropertiesXML: String {
        let date = ISO8601DateFormatter().string(from: Date())
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        + "<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" "
        + "xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\" "
        + "xmlns:dcmitype=\"http://purl.org/dc/dcmitype/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">"
        + "<dc:title>Basir</dc:title><dc:creator>Basir</dc:creator>"
        + "<cp:lastModifiedBy>Basir iOS</cp:lastModifiedBy>"
        + "<dcterms:created xsi:type=\"dcterms:W3CDTF\">\(date)</dcterms:created>"
        + "<dcterms:modified xsi:type=\"dcterms:W3CDTF\">\(date)</dcterms:modified>"
        + "</cp:coreProperties>"
    }

    private var appPropertiesXML: String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        + "<Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\" "
        + "xmlns:vt=\"http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes\">"
        + "<Application>Basir iOS</Application><AppVersion>1.0</AppVersion>"
        + "</Properties>"
    }

    private static func clean(_ value: String) -> String {
        value.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractIntMarker(_ name: String, from value: inout String) -> Int? {
        guard let result = extractStringMarker(name, from: &value) else { return nil }
        return Int(result)
    }

    private static func extractStringMarker(_ name: String, from value: inout String) -> String? {
        let prefix = "[[\(name):"
        guard value.hasPrefix(prefix), let end = value.range(of: "]]" ) else { return nil }
        let raw = String(value[value.index(value.startIndex, offsetBy: prefix.count)..<end.lowerBound])
        value.removeSubrange(value.startIndex..<end.upperBound)
        return raw
    }

    private static func escape(_ value: String) -> String {
        var output = ""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x26: output += "&amp;"
            case 0x3C: output += "&lt;"
            case 0x3E: output += "&gt;"
            case 0x22: output += "&quot;"
            case 0x27: output += "&apos;"
            case 0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F: output += " "
            default: output.unicodeScalars.append(scalar)
            }
        }
        return output
    }

    private static func escapeAttribute(_ value: String) -> String {
        escape(value).replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private static func normalizeHeader(_ value: String) -> String {
        clean(value).lowercased()
            .replacingOccurrences(of: #"[\p{P}\p{S}\s]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isShortHeader(_ value: String) -> Bool {
        ["س", "م", "مع", "مس", "سع", "cr", "hrs", "hours", "credits"].contains(value)
    }

    private static func visibleLength(_ value: String) -> Int {
        value.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces).count }.max() ?? 0
    }

    private static func isCompactValue(_ value: String) -> Bool {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return true }
        return text.range(of: #"^[-–—0-9٠-٩.,،/:٪%+() ]{1,18}$"#, options: .regularExpression) != nil
    }

    static func validate(
        url: URL,
        expectedPages: Int = 0,
        expectedTables: Int = 0,
        expectedImages: Int = 0
    ) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size >= 500 else { throw BasirError.conversionFailed("Generated DOCX is missing or too small.") }
        let archive = try Archive(url: url, accessMode: .read)
        guard let documentEntry = archive["word/document.xml"], archive["word/styles.xml"] != nil else {
            throw BasirError.conversionFailed("Generated DOCX is missing required Word parts.")
        }
        var data = Data()
        _ = try archive.extract(documentEntry) { data.append($0) }
        guard let xml = String(data: data, encoding: .utf8),
              xml.contains("<w:document"), xml.contains("</w:document>") else {
            throw BasirError.conversionFailed("Generated Word XML is incomplete.")
        }
        let tables = occurrences(of: "<w:tbl>", in: xml)
        if tables < expectedTables {
            throw BasirError.conversionFailed("Expected Word tables are missing from the generated DOCX.")
        }
        if tables == 0, occurrences(of: "|", in: xml) >= 4 {
            throw BasirError.conversionFailed("A table appears to have been flattened into plain text.")
        }
        let lower = xml.lowercased()
        if lower.contains("&lt;br&gt;") || lower.contains("&lt;br/&gt;") || lower.contains("&lt;br /&gt;") {
            throw BasirError.conversionFailed("The DOCX still contains a literal HTML line-break marker.")
        }
        if expectedPages > 0 {
            let explicitPages = occurrences(of: "<w:br w:type=\"page\"/>", in: xml) + 1
            let sectionPages = occurrences(of: "<w:sectPr", in: xml)
            let preservedPages = max(explicitPages, sectionPages)
            if preservedPages < expectedPages {
                throw BasirError.conversionFailed("Only \(preservedPages) of \(expectedPages) source page boundaries were preserved.")
            }
        }
        if expectedImages > 0 {
            let drawings = occurrences(of: "<w:drawing>", in: xml)
            let altTexts = occurrences(of: "<wp:docPr ", in: xml)
            let media = archive.filter { $0.path.hasPrefix("word/media/") && $0.type == .file }.count
            guard drawings >= expectedImages, altTexts >= expectedImages,
                  media >= expectedImages, archive["word/_rels/document.xml.rels"] != nil else {
                throw BasirError.conversionFailed("Expected accessible images are missing from the DOCX.")
            }
        }
    }

    private static func occurrences(of token: String, in text: String) -> Int {
        var count = 0
        var range = text.startIndex..<text.endIndex
        while let found = text.range(of: token, range: range) {
            count += 1
            range = found.upperBound..<text.endIndex
        }
        return count
    }
}

