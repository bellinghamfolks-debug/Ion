// DocxWriter.swift
// Accessible OOXML writer used by Basir's document conversion pipeline.
// Supports real headings, mixed RTL/LTR runs, rich text, real lists,
// page breaks, repeated table headers, and embedded fallback images.

import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct DocxWriter {
    struct Run: Hashable {
        enum Direction: String { case auto, rtl, ltr }

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

    enum Block {
        case heading(level: Int, runs: [Run])
        case paragraph(runs: [Run])
        case listItem(level: Int, ordered: Bool, runs: [Run])
        case table(rows: [[String]], rowHeader: Bool)
        case image(data: Data, mimeType: String, altText: String)
        case pageBreak
    }

    private struct MediaItem {
        let index: Int
        let relationshipID: String
        let filename: String
        let data: Data
        let mimeType: String
        let widthEMU: Int
        let heightEMU: Int
        let altText: String
    }

    private struct HyperlinkItem {
        let relationshipID: String
        let url: String
    }

    private var blocks: [Block] = []
    let rtl: Bool
    let langTag: String

    init(rtl: Bool) {
        self.rtl = rtl
        self.langTag = rtl ? "ar-SA" : "en-US"
    }

    mutating func append(_ block: Block) {
        blocks.append(block)
    }

    mutating func appendPlain(_ text: String) {
        let lines = text.components(separatedBy: "\n")
        var pendingTable: [[String]] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushTable(&pendingTable)
                continue
            }
            if line.hasPrefix("### ") {
                flushTable(&pendingTable)
                blocks.append(.heading(level: 3, runs: [Run(text: String(line.dropFirst(4)))]))
            } else if line.hasPrefix("## ") {
                flushTable(&pendingTable)
                blocks.append(.heading(level: 2, runs: [Run(text: String(line.dropFirst(3)))]))
            } else if line.hasPrefix("# ") {
                flushTable(&pendingTable)
                blocks.append(.heading(level: 1, runs: [Run(text: String(line.dropFirst(2)))]))
            } else if line.hasPrefix("- ") || line.hasPrefix("• ") {
                flushTable(&pendingTable)
                blocks.append(.listItem(level: 0, ordered: false,
                                        runs: [Run(text: String(line.dropFirst(2)))]))
            } else if let match = line.range(of: #"^\d+[\.)]\s+"#,
                                              options: .regularExpression) {
                flushTable(&pendingTable)
                blocks.append(.listItem(level: 0, ordered: true,
                                        runs: [Run(text: String(line[match.upperBound...]))]))
            } else if line.hasPrefix("|") && line.hasSuffix("|") {
                let cells = line.dropFirst().dropLast()
                    .split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                let isSeparator = cells.allSatisfy {
                    !$0.isEmpty && $0.allSatisfy { $0 == "-" || $0 == ":" }
                }
                if cells.count >= 2 && !isSeparator { pendingTable.append(cells) }
            } else {
                flushTable(&pendingTable)
                blocks.append(.paragraph(runs: [Run(text: line)]))
            }
        }
        flushTable(&pendingTable)
    }

    private mutating func flushTable(_ pending: inout [[String]]) {
        guard !pending.isEmpty else { return }
        blocks.append(.table(rows: rectangular(pending), rowHeader: false))
        pending.removeAll(keepingCapacity: true)
    }

    func archive() -> Data {
        let media = mediaItems()
        let hyperlinks = hyperlinkItems()
        let hyperlinkIDs = Dictionary(uniqueKeysWithValues: hyperlinks.map { ($0.url, $0.relationshipID) })
        var zip = ZipWriter()
        zip.addFile(name: "[Content_Types].xml", utf8: contentTypesXml(hasJPEG: media.contains { $0.mimeType == "image/jpeg" },
                                                                       hasPNG: media.contains { $0.mimeType == "image/png" }))
        zip.addFile(name: "_rels/.rels", utf8: rootRelsXml)
        zip.addFile(name: "word/_rels/document.xml.rels", utf8: documentRelationshipsXml(media: media,
                                                                                           hyperlinks: hyperlinks))
        zip.addFile(name: "word/document.xml", utf8: documentXml(media: media,
                                                                  hyperlinkIDs: hyperlinkIDs))
        zip.addFile(name: "word/styles.xml", utf8: stylesXml)
        zip.addFile(name: "word/numbering.xml", utf8: numberingXml)
        zip.addFile(name: "word/settings.xml", utf8: settingsXml)
        for item in media {
            zip.addFile(name: "word/media/\(item.filename)", data: item.data)
        }
        return zip.archive()
    }

    func write(to url: URL) throws {
        try archive().write(to: url, options: .atomic)
    }

    // MARK: - Package parts

    private func contentTypesXml(hasJPEG: Bool, hasPNG: Bool) -> String {
        var imageDefaults = ""
        if hasJPEG {
            imageDefaults += #"<Default Extension="jpg" ContentType="image/jpeg"/>"#
        }
        if hasPNG {
            imageDefaults += #"<Default Extension="png" ContentType="image/png"/>"#
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          \(imageDefaults)
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
          <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
          <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
          <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
        </Types>
        """
    }

    private var rootRelsXml: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """
    }

    private func documentRelationshipsXml(media: [MediaItem],
                                          hyperlinks: [HyperlinkItem]) -> String {
        var relationships = ""
        relationships += #"<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>"#
        relationships += #"<Relationship Id="rIdNumbering" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>"#
        relationships += #"<Relationship Id="rIdSettings" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>"#
        for item in media {
            relationships += "<Relationship Id=\"\(item.relationshipID)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\(item.filename)\"/>"
        }
        for item in hyperlinks {
            relationships += "<Relationship Id=\"\(item.relationshipID)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(escapeAttribute(item.url))\" TargetMode=\"External\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        \(relationships)
        </Relationships>
        """
    }

    private func documentXml(media: [MediaItem],
                             hyperlinkIDs: [String: String]) -> String {
        var xml = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
        xml += #"<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">"#
        xml += "<w:body>"
        var imageIndex = 0
        for block in blocks {
            switch block {
            case .heading(let level, let runs):
                xml += paragraphXml(runs: runs,
                                    style: "Heading\(min(max(level, 1), 3))",
                                    boldFallback: true,
                                    hyperlinkIDs: hyperlinkIDs)
            case .paragraph(let runs):
                xml += paragraphXml(runs: runs,
                                    style: nil,
                                    boldFallback: false,
                                    hyperlinkIDs: hyperlinkIDs)
            case .listItem(let level, let ordered, let runs):
                xml += listParagraphXml(level: level,
                                        ordered: ordered,
                                        runs: runs,
                                        hyperlinkIDs: hyperlinkIDs)
            case .table(let rows, let rowHeader):
                xml += tableXml(rows: rectangular(rows),
                                rowHeader: rowHeader,
                                hyperlinkIDs: hyperlinkIDs)
            case .image:
                guard imageIndex < media.count else { continue }
                xml += imageXml(media[imageIndex])
                imageIndex += 1
            case .pageBreak:
                xml += "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>"
            }
        }
        xml += sectionPropertiesXml()
        xml += "</w:body></w:document>"
        return xml
    }

    // MARK: - Paragraphs and runs

    private func paragraphXml(runs: [Run],
                              style: String?,
                              boldFallback: Bool,
                              hyperlinkIDs: [String: String]) -> String {
        let expanded = expandDirectionalRuns(runs)
        let text = expanded.map(\.text).joined()
        let paragraphRTL = isMostlyRTL(text)
        var xml = "<w:p><w:pPr>"
        if let style { xml += "<w:pStyle w:val=\"\(style)\"/>" }
        if paragraphRTL { xml += "<w:bidi/>" }
        xml += "<w:spacing w:after=\"120\"/>"
        xml += "</w:pPr>"
        for run in expanded {
            xml += runXml(run,
                          forceBold: boldFallback,
                          hyperlinkIDs: hyperlinkIDs)
        }
        xml += "</w:p>"
        return xml
    }

    private func listParagraphXml(level: Int,
                                  ordered: Bool,
                                  runs: [Run],
                                  hyperlinkIDs: [String: String]) -> String {
        let expanded = expandDirectionalRuns(runs)
        let text = expanded.map(\.text).joined()
        var xml = "<w:p><w:pPr>"
        if isMostlyRTL(text) { xml += "<w:bidi/>" }
        xml += "<w:numPr><w:ilvl w:val=\"\(min(max(level, 0), 8))\"/><w:numId w:val=\"\(ordered ? 2 : 1)\"/></w:numPr>"
        xml += "<w:spacing w:after=\"80\"/></w:pPr>"
        for run in expanded {
            xml += runXml(run,
                          forceBold: false,
                          hyperlinkIDs: hyperlinkIDs)
        }
        xml += "</w:p>"
        return xml
    }

    private func runXml(_ run: Run,
                        forceBold: Bool,
                        hyperlinkIDs: [String: String]) -> String {
        let direction = resolvedDirection(for: run)
        let runLang = direction == .rtl ? "ar-SA" : "en-US"
        var properties = "<w:rPr>"
        if run.bold || forceBold { properties += "<w:b/><w:bCs/>" }
        if run.italic { properties += "<w:i/><w:iCs/>" }
        if run.underline { properties += "<w:u w:val=\"single\"/>" }
        if run.strike { properties += "<w:strike/>" }
        if run.highlight { properties += "<w:highlight w:val=\"yellow\"/>" }
        if run.superscript { properties += "<w:vertAlign w:val=\"superscript\"/>" }
        if run.isSubscript { properties += "<w:vertAlign w:val=\"subscript\"/>" }
        if let points = run.fontSizePoints, points.isFinite {
            let halfPoints = min(max(Int((points * 2).rounded()), 10), 192)
            properties += "<w:sz w:val=\"\(halfPoints)\"/><w:szCs w:val=\"\(halfPoints)\"/>"
        }
        if let color = normalizedHexColor(run.colorHex) {
            properties += "<w:color w:val=\"\(color)\"/>"
        }
        if direction == .rtl { properties += "<w:rtl/>" }
        properties += direction == .rtl
            ? "<w:lang w:val=\"ar-SA\" w:bidi=\"ar-SA\"/>"
            : "<w:lang w:val=\"\(runLang)\"/>"
        properties += "</w:rPr>"
        let body = "<w:r>\(properties)<w:t xml:space=\"preserve\">\(escape(run.text))</w:t></w:r>"
        if let url = normalizedExternalURL(run.url),
           let relationshipID = hyperlinkIDs[url] {
            return "<w:hyperlink r:id=\"\(relationshipID)\" w:history=\"1\">\(body)</w:hyperlink>"
        }
        return body
    }

    // MARK: - Tables

    private func tableXml(rows: [[String]],
                          rowHeader: Bool,
                          hyperlinkIDs: [String: String]) -> String {
        guard let first = rows.first, !first.isEmpty else { return "" }
        let columnCount = first.count
        let columnWidth = 9_000 / max(columnCount, 1)
        let tableRTL = isMostlyRTL(rows.flatMap { $0 }.joined(separator: " "))
        var xml = "<w:tbl><w:tblPr>"
        xml += "<w:tblW w:w=\"5000\" w:type=\"pct\"/>"
        if tableRTL { xml += "<w:bidiVisual/>" }
        xml += "<w:tblLayout w:type=\"fixed\"/>"
        xml += "<w:tblBorders><w:top w:val=\"single\" w:sz=\"6\" w:color=\"777777\"/><w:bottom w:val=\"single\" w:sz=\"6\" w:color=\"777777\"/><w:left w:val=\"single\" w:sz=\"6\" w:color=\"777777\"/><w:right w:val=\"single\" w:sz=\"6\" w:color=\"777777\"/><w:insideH w:val=\"single\" w:sz=\"4\" w:color=\"BBBBBB\"/><w:insideV w:val=\"single\" w:sz=\"4\" w:color=\"BBBBBB\"/></w:tblBorders>"
        xml += "</w:tblPr><w:tblGrid>"
        for _ in 0..<columnCount { xml += "<w:gridCol w:w=\"\(columnWidth)\"/>" }
        xml += "</w:tblGrid>"

        for (rowIndex, row) in rows.enumerated() {
            xml += "<w:tr>"
            if rowIndex == 0 { xml += "<w:trPr><w:tblHeader/></w:trPr>" }
            for (columnIndex, cell) in row.enumerated() {
                let isHeader = rowIndex == 0 || (rowHeader && columnIndex == 0)
                xml += "<w:tc><w:tcPr><w:tcW w:w=\"\(columnWidth)\" w:type=\"dxa\"/>"
                if isHeader { xml += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"E8EEF7\"/>" }
                xml += "<w:vAlign w:val=\"center\"/></w:tcPr>"
                xml += paragraphXml(runs: [Run(text: cell.isEmpty ? " " : cell,
                                                   bold: isHeader)],
                                    style: nil,
                                    boldFallback: false,
                                    hyperlinkIDs: hyperlinkIDs)
                xml += "</w:tc>"
            }
            xml += "</w:tr>"
        }
        xml += "</w:tbl><w:p/>"
        return xml
    }

    // MARK: - Images

    private func mediaItems() -> [MediaItem] {
        var items: [MediaItem] = []
        var index = 1
        for block in blocks {
            guard case let .image(data, mimeType, altText) = block else { continue }
            let normalizedMime = mimeType.lowercased() == "image/png" ? "image/png" : "image/jpeg"
            let ext = normalizedMime == "image/png" ? "png" : "jpg"
            let dimensions = imageDimensions(data: data)
            items.append(MediaItem(index: index,
                                   relationshipID: "rIdImage\(index)",
                                   filename: "image\(index).\(ext)",
                                   data: data,
                                   mimeType: normalizedMime,
                                   widthEMU: dimensions.width,
                                   heightEMU: dimensions.height,
                                   altText: altText))
            index += 1
        }
        return items
    }

    private func hyperlinkItems() -> [HyperlinkItem] {
        var ordered: [String] = []
        var seen = Set<String>()
        for block in blocks {
            let runs: [Run]
            switch block {
            case .heading(_, let value), .paragraph(let value), .listItem(_, _, let value):
                runs = value
            default:
                runs = []
            }
            for run in runs {
                guard let url = normalizedExternalURL(run.url), seen.insert(url).inserted else { continue }
                ordered.append(url)
            }
        }
        return ordered.enumerated().map {
            HyperlinkItem(relationshipID: "rIdLink\($0.offset + 1)", url: $0.element)
        }
    }

    private func imageDimensions(data: Data) -> (width: Int, height: Int) {
        let maxWidth = 5_800_000.0
        let maxHeight = 8_000_000.0
#if canImport(UIKit)
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
            return (Int(maxWidth), Int(maxHeight * 0.75))
        }
        let aspect = Double(image.size.height / image.size.width)
        var width = maxWidth
        var height = width * aspect
        if height > maxHeight {
            height = maxHeight
            width = height / aspect
        }
        return (Int(width), Int(height))
#else
        return (Int(maxWidth), Int(maxHeight * 0.75))
#endif
    }

    private func imageXml(_ item: MediaItem) -> String {
        let alt = escapeAttribute(item.altText)
        return """
        <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:drawing>
          <wp:inline distT="0" distB="0" distL="0" distR="0">
            <wp:extent cx="\(item.widthEMU)" cy="\(item.heightEMU)"/>
            <wp:docPr id="\(item.index)" name="Basir page image \(item.index)" descr="\(alt)"/>
            <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
              <pic:pic>
                <pic:nvPicPr><pic:cNvPr id="0" name="\(item.filename)" descr="\(alt)"/><pic:cNvPicPr/></pic:nvPicPr>
                <pic:blipFill><a:blip r:embed="\(item.relationshipID)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>
                <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(item.widthEMU)" cy="\(item.heightEMU)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>
              </pic:pic>
            </a:graphicData></a:graphic>
          </wp:inline>
        </w:drawing></w:r></w:p>
        """
    }

    // MARK: - Styles, numbering, and settings

    private var stylesXml: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/><w:rPr><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:bCs/><w:sz w:val="36"/><w:szCs w:val="36"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:bCs/><w:sz w:val="30"/><w:szCs w:val="30"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:bCs/><w:sz w:val="26"/><w:szCs w:val="26"/></w:rPr></w:style>
        </w:styles>
        """
    }

    private var numberingXml: String {
        var bulletLevels = ""
        var numberLevels = ""
        for level in 0...8 {
            let indent = 720 + level * 360
            bulletLevels += "<w:lvl w:ilvl=\"\(level)\"><w:start w:val=\"1\"/><w:numFmt w:val=\"bullet\"/><w:lvlText w:val=\"•\"/><w:lvlJc w:val=\"start\"/><w:pPr><w:tabs><w:tab w:val=\"num\" w:pos=\"\(indent)\"/></w:tabs><w:ind w:start=\"\(indent)\" w:hanging=\"360\"/></w:pPr></w:lvl>"
            numberLevels += "<w:lvl w:ilvl=\"\(level)\"><w:start w:val=\"1\"/><w:numFmt w:val=\"decimal\"/><w:lvlText w:val=\"%\(level + 1).\"/><w:lvlJc w:val=\"start\"/><w:pPr><w:tabs><w:tab w:val=\"num\" w:pos=\"\(indent)\"/></w:tabs><w:ind w:start=\"\(indent)\" w:hanging=\"360\"/></w:pPr></w:lvl>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="multilevel"/>\(bulletLevels)</w:abstractNum>
          <w:abstractNum w:abstractNumId="2"><w:multiLevelType w:val="multilevel"/>\(numberLevels)</w:abstractNum>
          <w:num w:numId="1"><w:abstractNumId w:val="1"/></w:num>
          <w:num w:numId="2"><w:abstractNumId w:val="2"/></w:num>
        </w:numbering>
        """
    }

    private var settingsXml: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:defaultTabStop w:val="720"/>
          <w:compat/>
          <w:doNotTrackMoves/>
          <w:doNotTrackFormatting/>
        </w:settings>
        """
    }

    private func sectionPropertiesXml() -> String {
        var xml = "<w:sectPr>"
        xml += "<w:pgSz w:w=\"12240\" w:h=\"15840\"/>"
        xml += "<w:pgMar w:top=\"1080\" w:right=\"1080\" w:bottom=\"1080\" w:left=\"1080\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/>"
        if rtl { xml += "<w:bidi/>" }
        xml += "</w:sectPr>"
        return xml
    }

    // MARK: - Direction and escaping

    private func expandDirectionalRuns(_ runs: [Run]) -> [Run] {
        runs.flatMap { run in
            guard run.direction == .auto else { return [run] }
            var output: [Run] = []
            var buffer = ""
            var current: Run.Direction?
            for character in run.text {
                let classified = characterDirection(character)
                let effective = classified ?? current ?? (rtl ? .rtl : .ltr)
                if let current, effective != current, !buffer.isEmpty {
                    var part = run
                    part.text = buffer
                    part.direction = current
                    output.append(part)
                    buffer = ""
                }
                current = effective
                buffer.append(character)
            }
            if !buffer.isEmpty {
                var part = run
                part.text = buffer
                part.direction = current ?? (rtl ? .rtl : .ltr)
                output.append(part)
            }
            return output
        }
    }

    private func resolvedDirection(for run: Run) -> Run.Direction {
        if run.direction != .auto { return run.direction }
        return isMostlyRTL(run.text) ? .rtl : .ltr
    }

    private func characterDirection(_ character: Character) -> Run.Direction? {
        if character.isNumber { return .ltr }
        for scalar in character.unicodeScalars {
            switch scalar.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF:
                return .rtl
            case 0x0041...0x005A, 0x0061...0x007A:
                return .ltr
            default:
                continue
            }
        }
        return nil
    }

    private func isMostlyRTL(_ text: String) -> Bool {
        var rtlCount = 0
        var ltrCount = 0
        for character in text {
            switch characterDirection(character) {
            case .rtl: rtlCount += 1
            case .ltr: ltrCount += 1
            default: break
            }
        }
        if rtlCount == ltrCount { return rtl }
        return rtlCount > ltrCount
    }

    private func rectangular(_ rows: [[String]]) -> [[String]] {
        let width = rows.map(\.count).max() ?? 0
        guard width > 0 else { return [] }
        return rows.map { row in
            if row.count >= width { return Array(row.prefix(width)) }
            return row + Array(repeating: "", count: width - row.count)
        }
    }

    private func escape(_ string: String) -> String {
        string.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapeAttribute(_ string: String) -> String {
        escape(string)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func normalizedHexColor(_ raw: String?) -> String? {
        guard var raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.hasPrefix("#") { raw.removeFirst() }
        let upper = raw.uppercased()
        guard upper.count == 6,
              upper.unicodeScalars.allSatisfy({
                  (48...57).contains($0.value) || (65...70).contains($0.value)
              }) else { return nil }
        return upper
    }

    private func normalizedExternalURL(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto", "tel"].contains(scheme) else { return nil }
        return raw
    }
}
