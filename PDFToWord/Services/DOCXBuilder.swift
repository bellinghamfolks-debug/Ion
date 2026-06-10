import Foundation
import UIKit

final class DOCXBuilder {
    private struct PackagePart {
        var relationshipID: String
        var target: String
        var path: String
        var xml: String
    }

    private struct SectionReferences {
        var headerRelationshipID: String?
        var footerRelationshipID: String?
    }

    private var imageRelationships: [(id: String, target: String)] = []
    private var hyperlinkRelationships: [(id: String, target: String)] = []
    private var hyperlinkIDs: [String: String] = [:]
    private var images: [(path: String, data: Data)] = []
    private var headerParts: [PackagePart] = []
    private var footerParts: [PackagePart] = []
    private var sectionReferences: [Int: SectionReferences] = [:]
    private var footnotes: [Int: DocumentBlock] = [:]
    private var bookmarkIDs: [String: Int] = [:]
    private var nextImageID = 100
    private var nextHyperlinkID = 1_000
    private var nextHeaderFooterID = 20
    private var nextDrawingID: UInt32 = 1
    private var nextBookmarkID = 1

    func build(
        analyses: [PageAnalysis],
        extractor: PDFPageExtractor,
        options: ConversionOptions,
        outputURL: URL,
        title: String
    ) throws {
        reset()
        let sorted = analyses.sorted { $0.pageNumber < $1.pageNumber }
        prepareAncillaryParts(analyses: sorted, options: options)
        let documentXML = try makeDocumentXML(analyses: sorted, extractor: extractor, options: options)
        var zip = ZipArchiveWriter()

        try zip.add(path: "[Content_Types].xml", data: utf8(contentTypesXML()))
        try zip.add(path: "_rels/.rels", data: utf8(rootRelationshipsXML()))
        try zip.add(path: "docProps/core.xml", data: utf8(corePropertiesXML(title: title)))
        try zip.add(path: "docProps/app.xml", data: utf8(appPropertiesXML()))
        try zip.add(path: "word/document.xml", data: utf8(documentXML))
        try zip.add(path: "word/styles.xml", data: utf8(stylesXML(options: options)))
        try zip.add(path: "word/settings.xml", data: utf8(settingsXML()))
        try zip.add(path: "word/numbering.xml", data: utf8(numberingXML()))
        try zip.add(path: "word/_rels/document.xml.rels", data: utf8(documentRelationshipsXML()))

        if !footnotes.isEmpty {
            try zip.add(path: "word/footnotes.xml", data: utf8(footnotesXML(options: options)))
        }
        for part in headerParts + footerParts {
            try zip.add(path: part.path, data: utf8(part.xml))
        }
        for image in images {
            try zip.add(path: image.path, data: image.data)
        }

        let archive = try zip.finalize()
        try archive.write(to: outputURL, options: [.atomic, .completeFileProtection])
    }

    private func reset() {
        imageRelationships.removeAll()
        hyperlinkRelationships.removeAll()
        hyperlinkIDs.removeAll()
        images.removeAll()
        headerParts.removeAll()
        footerParts.removeAll()
        sectionReferences.removeAll()
        footnotes.removeAll()
        bookmarkIDs.removeAll()
        nextImageID = 100
        nextHyperlinkID = 1_000
        nextHeaderFooterID = 20
        nextDrawingID = 1
        nextBookmarkID = 1
    }

    private func prepareAncillaryParts(analyses: [PageAnalysis], options: ConversionOptions) {
        for page in analyses {
            for block in page.blocks where block.type == .footnote && block.footnoteID > 0 {
                footnotes[block.footnoteID] = block
            }

            var refs = SectionReferences()
            if options.preserveHeadersAndFooters {
                let headers = page.blocks.filter { $0.type == .header }
                if !headers.isEmpty {
                    let number = headerParts.count + 1
                    let relationshipID = "rId\(nextHeaderFooterID)"
                    nextHeaderFooterID += 1
                    headerParts.append(PackagePart(
                        relationshipID: relationshipID,
                        target: "header\(number).xml",
                        path: "word/header\(number).xml",
                        xml: headerFooterXML(blocks: headers, isHeader: true, addPageNumber: false, options: options)
                    ))
                    refs.headerRelationshipID = relationshipID
                }
            }

            let footers = options.preserveHeadersAndFooters
                ? page.blocks.filter { $0.type == .footer }
                : []
            if !footers.isEmpty || options.addPageNumbers {
                let number = footerParts.count + 1
                let relationshipID = "rId\(nextHeaderFooterID)"
                nextHeaderFooterID += 1
                footerParts.append(PackagePart(
                    relationshipID: relationshipID,
                    target: "footer\(number).xml",
                    path: "word/footer\(number).xml",
                    xml: headerFooterXML(
                        blocks: footers,
                        isHeader: false,
                        addPageNumber: options.addPageNumbers,
                        options: options
                    )
                ))
                refs.footerRelationshipID = relationshipID
            }
            sectionReferences[page.pageNumber] = refs
        }
    }

    private func makeDocumentXML(
        analyses: [PageAnalysis],
        extractor: PDFPageExtractor,
        options: ConversionOptions
    ) throws -> String {
        var body = ""

        for (pageOffset, page) in analyses.enumerated() {
            let pageIndex = max(0, page.pageNumber - 1)
            let pageSize = options.preservePageSizeAndOrientation
                ? extractor.pageSize(at: pageIndex)
                : CGSize(width: 595.3, height: 841.9)
            let availableWidthPoints = max(144, pageSize.width - CGFloat(options.pageMarginPoints * 2))
            let availableWidthTwips = max(2_880, Int(availableWidthPoints * 20))

            if page.preserveWholePageImage || page.source == .visualPageFallback {
                let data = try extractor.highResolutionPageImage(at: pageIndex, longEdge: 3_400)
                let alt = page.wholePageAltText.isEmpty
                    ? L10n.format("صورة كاملة للصفحة %d محفوظة لضمان التطابق البصري.", page.pageNumber)
                    : page.wholePageAltText
                body += imageDataParagraphXML(
                    data: data,
                    altText: alt,
                    direction: page.direction,
                    maxWidthPoints: availableWidthPoints,
                    forceFullWidth: true
                )
            } else {
                for block in page.blocks {
                    if [.header, .footer, .footnote].contains(block.type) { continue }
                    if block.type == .image && block.isDecorative && !options.includeDecorativeImages { continue }
                    let direction = block.direction ?? page.direction

                    switch block.type {
                    case .heading1:
                        body += paragraphXML(block: block, style: "Heading1", direction: direction, options: options)
                    case .heading2:
                        body += paragraphXML(block: block, style: "Heading2", direction: direction, options: options)
                    case .heading3:
                        body += paragraphXML(block: block, style: "Heading3", direction: direction, options: options)
                    case .paragraph:
                        body += paragraphXML(block: block, direction: direction, options: options)
                    case .quote:
                        body += paragraphXML(block: block, style: "Quote", direction: direction, options: options)
                    case .bullet, .numbered:
                        body += paragraphXML(
                            block: block,
                            listID: numberingID(for: block.listStyle),
                            listLevel: block.listLevel,
                            direction: direction,
                            options: options
                        )
                    case .table:
                        body += tableXML(
                            block,
                            direction: direction,
                            options: options,
                            availableWidthTwips: availableWidthTwips
                        )
                    case .image, .watermark:
                        body += imageBlockXML(
                            block,
                            page: page,
                            extractor: extractor,
                            options: options,
                            maxWidthPoints: availableWidthPoints
                        )
                    case .pageImage:
                        let data = try extractor.highResolutionPageImage(at: pageIndex, longEdge: 3_400)
                        body += imageDataParagraphXML(
                            data: data,
                            altText: block.altText.isEmpty ? block.text : block.altText,
                            direction: direction,
                            maxWidthPoints: availableWidthPoints,
                            forceFullWidth: true
                        )
                    case .caption:
                        body += paragraphXML(block: block, style: "Caption", direction: direction, options: options)
                    case .textBox:
                        if abs(block.rotationDegrees) >= 1,
                           block.boundingBox[2] > 0.01,
                           let data = extractor.cropImage(
                            pageIndex: pageIndex,
                            normalizedBox: block.boundingBox,
                            maxRenderWidth: 3_200
                           ) {
                            body += imageDataParagraphXML(
                                data: data,
                                altText: block.altText.isEmpty ? block.text : block.altText,
                                direction: direction,
                                maxWidthPoints: availableWidthPoints,
                                forceFullWidth: false
                            )
                        } else {
                            body += paragraphXML(block: block, style: "TextBox", direction: direction, options: options)
                        }
                    case .equation:
                        if block.text.isEmpty,
                           block.boundingBox[2] > 0.01,
                           let data = extractor.cropImage(
                            pageIndex: pageIndex,
                            normalizedBox: block.boundingBox,
                            maxRenderWidth: 3_200
                           ) {
                            body += imageDataParagraphXML(
                                data: data,
                                altText: block.altText,
                                direction: direction,
                                maxWidthPoints: availableWidthPoints,
                                forceFullWidth: false
                            )
                        } else {
                            body += paragraphXML(block: block, style: "Equation", direction: direction, options: options)
                        }
                    case .formField:
                        body += paragraphXML(block: block, style: "FormField", direction: direction, options: options)
                    case .separator:
                        body += separatorXML()
                    case .blank:
                        body += "<w:p/>"
                    case .header, .footer, .footnote:
                        break
                    }
                }
            }

            let refs = sectionReferences[page.pageNumber] ?? SectionReferences()
            if pageOffset < analyses.count - 1, options.preservePageBreaks {
                body += sectionBreakParagraphXML(pageSize: pageSize, options: options, references: refs)
            }
        }

        let finalPage = analyses.last
        let finalPageSize: CGSize
        if options.preservePageSizeAndOrientation, let finalPage {
            finalPageSize = extractor.pageSize(at: max(0, finalPage.pageNumber - 1))
        } else {
            finalPageSize = CGSize(width: 595.3, height: 841.9)
        }
        let finalRefs = finalPage.flatMap { sectionReferences[$0.pageNumber] } ?? SectionReferences()
        let section = sectionPropertiesXML(
            pageSize: finalPageSize,
            options: options,
            references: finalRefs,
            nextPage: false
        )

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                    xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
                    xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
                    xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
          <w:body>\(body)\(section)</w:body>
        </w:document>
        """
    }

    private func paragraphXML(
        block: DocumentBlock,
        style: String? = nil,
        listID: Int? = nil,
        listLevel: Int = 0,
        direction: TextDirection,
        options: ConversionOptions,
        alignment: CellHorizontalAlignment? = nil,
        registerHyperlinks: Bool = true
    ) -> String {
        let runs = block.runs.isEmpty && !block.text.isEmpty
            ? [TextRun(text: block.text, direction: direction)]
            : block.runs
        if runs.isEmpty && block.text.isEmpty { return "<w:p/>" }

        var pPr = ""
        if let style { pPr += "<w:pStyle w:val=\"\(style)\"/>" }
        if direction == .rtl { pPr += "<w:bidi/>" }
        if let alignment {
            pPr += "<w:jc w:val=\"\(wordAlignment(alignment, direction: direction))\"/>"
        } else if direction == .rtl {
            pPr += "<w:jc w:val=\"right\"/>"
        }
        if block.keepWithNext { pPr += "<w:keepNext/>" }
        if let listID {
            pPr += "<w:numPr><w:ilvl w:val=\"\(max(0, min(8, listLevel)))\"/><w:numId w:val=\"\(listID)\"/></w:numPr>"
        }

        var content = ""
        if !block.bookmark.isEmpty {
            let bookmarkID = bookmarkID(for: block.bookmark)
            content += "<w:bookmarkStart w:id=\"\(bookmarkID)\" w:name=\"\(XML.escape(block.bookmark))\"/>"
        }
        content += runs.map {
            richRunContainerXML(
                $0,
                paragraphDirection: direction,
                options: options,
                registerHyperlinks: registerHyperlinks
            )
        }.joined()
        if !block.bookmark.isEmpty {
            let bookmarkID = bookmarkID(for: block.bookmark)
            content += "<w:bookmarkEnd w:id=\"\(bookmarkID)\"/>"
        }

        return "<w:p><w:pPr>\(pPr)</w:pPr>\(content)</w:p>"
    }

    private func richRunContainerXML(
        _ run: TextRun,
        paragraphDirection: TextDirection,
        options: ConversionOptions,
        registerHyperlinks: Bool
    ) -> String {
        let runXML = richRunXML(run, paragraphDirection: paragraphDirection, options: options)
        if registerHyperlinks, !run.linkURL.isEmpty {
            let relationID = hyperlinkRelationshipID(for: run.linkURL)
            return "<w:hyperlink r:id=\"\(relationID)\" w:history=\"1\">\(runXML)</w:hyperlink>"
        }
        if !run.internalLink.isEmpty {
            return "<w:hyperlink w:anchor=\"\(XML.escape(run.internalLink))\" w:history=\"1\">\(runXML)</w:hyperlink>"
        }
        return runXML
    }

    private func richRunXML(
        _ run: TextRun,
        paragraphDirection: TextDirection,
        options: ConversionOptions
    ) -> String {
        let runDirection = run.direction ?? (XML.containsArabic(run.text) ? .rtl : paragraphDirection)
        var properties = ""
        if run.bold { properties += "<w:b/><w:bCs/>" }
        if run.italic { properties += "<w:i/><w:iCs/>" }
        if run.underline { properties += "<w:u w:val=\"single\"/>" }
        if run.strike { properties += "<w:strike/>" }
        if !run.highlightColor.isEmpty { properties += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(run.highlightColor)\"/>" }
        if !run.textColor.isEmpty { properties += "<w:color w:val=\"\(run.textColor)\"/>" }
        if run.fontSize > 0 {
            let halfPoints = max(2, Int((run.fontSize * 2).rounded()))
            properties += "<w:sz w:val=\"\(halfPoints)\"/><w:szCs w:val=\"\(halfPoints)\"/>"
        }
        switch run.baseline {
        case .normal: break
        case .superscript: properties += "<w:vertAlign w:val=\"superscript\"/>"
        case .subscriptText: properties += "<w:vertAlign w:val=\"subscript\"/>"
        }
        if runDirection == .rtl {
            properties += "<w:rtl/><w:lang w:bidi=\"ar-SA\"/>"
        } else {
            properties += "<w:lang w:val=\"en-US\"/>"
        }
        if !run.linkURL.isEmpty || !run.internalLink.isEmpty {
            if !run.underline { properties += "<w:u w:val=\"single\"/>" }
            if run.textColor.isEmpty { properties += "<w:color w:val=\"0563C1\"/>" }
        }

        var content = ""
        if run.footnoteReferenceID > 0 {
            content += "<w:footnoteReference w:id=\"\(run.footnoteReferenceID)\"/>"
        }
        let pieces = run.text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, piece) in pieces.enumerated() {
            if index > 0 { content += "<w:br/>" }
            let text = String(piece)
            if !text.isEmpty {
                let space = run.preserveSpaces ? " xml:space=\"preserve\"" : ""
                content += "<w:t\(space)>\(XML.escape(text))</w:t>"
            }
        }
        return "<w:r><w:rPr>\(properties)</w:rPr>\(content)</w:r>"
    }

    private func tableXML(
        _ block: DocumentBlock,
        direction: TextDirection,
        options: ConversionOptions,
        availableWidthTwips: Int
    ) -> String {
        let rowCount = max(block.tableRowCount, block.rows.count)
        let columnCount = max(block.tableColumnCount, block.rows.map(\.count).max() ?? 0)
        guard rowCount > 0, columnCount > 0 else { return "" }

        let cells: [TableCell]
        if !block.tableCells.isEmpty {
            cells = block.tableCells
        } else {
            cells = block.rows.enumerated().flatMap { rowIndex, row in
                row.enumerated().map { columnIndex, text in
                    TableCell(row: rowIndex, column: columnIndex, text: text)
                }
            }
        }

        var origins: [Int: TableCell] = [:]
        var continuations: [Int: TableCell] = [:]
        for cell in cells {
            origins[cell.row * 1_000 + cell.column] = cell
            if cell.rowSpan > 1 {
                for row in (cell.row + 1)..<(cell.row + cell.rowSpan) {
                    continuations[row * 1_000 + cell.column] = cell
                }
            }
        }

        let baseCellWidth = max(360, availableWidthTwips / max(1, columnCount))
        let grid = (0..<columnCount).map { _ in "<w:gridCol w:w=\"\(baseCellWidth)\"/>" }.joined()
        var tableRows = ""

        for rowIndex in 0..<rowCount {
            let headerRow = rowIndex < block.repeatHeaderRows
                || cells.contains { $0.row == rowIndex && $0.isHeader }
            var rowXML = "<w:tr><w:trPr><w:cantSplit/>\(headerRow ? "<w:tblHeader/>" : "")</w:trPr>"
            var columnIndex = 0
            while columnIndex < columnCount {
                let key = rowIndex * 1_000 + columnIndex
                if let cell = origins[key] {
                    rowXML += tableCellXML(
                        cell,
                        direction: direction,
                        options: options,
                        baseCellWidth: baseCellWidth,
                        verticalMerge: cell.rowSpan > 1 ? "restart" : nil
                    )
                    columnIndex += max(1, cell.columnSpan)
                } else if let origin = continuations[key] {
                    var continuation = origin
                    continuation.text = ""
                    continuation.runs = []
                    rowXML += tableCellXML(
                        continuation,
                        direction: direction,
                        options: options,
                        baseCellWidth: baseCellWidth,
                        verticalMerge: "continue"
                    )
                    columnIndex += max(1, origin.columnSpan)
                } else {
                    rowXML += tableCellXML(
                        TableCell(row: rowIndex, column: columnIndex),
                        direction: direction,
                        options: options,
                        baseCellWidth: baseCellWidth,
                        verticalMerge: nil
                    )
                    columnIndex += 1
                }
            }
            rowXML += "</w:tr>"
            tableRows += rowXML
        }

        let bidi = direction == .rtl ? "<w:bidiVisual/>" : ""
        return """
        <w:tbl>
          <w:tblPr>\(bidi)<w:tblW w:w="\(availableWidthTwips)" w:type="dxa"/><w:tblLayout w:type="fixed"/>
            <w:tblBorders>
              <w:top w:val="single" w:sz="4" w:space="0" w:color="808080"/>
              <w:left w:val="single" w:sz="4" w:space="0" w:color="808080"/>
              <w:bottom w:val="single" w:sz="4" w:space="0" w:color="808080"/>
              <w:right w:val="single" w:sz="4" w:space="0" w:color="808080"/>
              <w:insideH w:val="single" w:sz="4" w:space="0" w:color="B0B0B0"/>
              <w:insideV w:val="single" w:sz="4" w:space="0" w:color="B0B0B0"/>
            </w:tblBorders>
          </w:tblPr>
          <w:tblGrid>\(grid)</w:tblGrid>
          \(tableRows)
        </w:tbl>
        """
    }

    private func tableCellXML(
        _ cell: TableCell,
        direction: TextDirection,
        options: ConversionOptions,
        baseCellWidth: Int,
        verticalMerge: String?
    ) -> String {
        let width = baseCellWidth * max(1, cell.columnSpan)
        var properties = "<w:tcW w:w=\"\(width)\" w:type=\"dxa\"/>"
        if cell.columnSpan > 1 { properties += "<w:gridSpan w:val=\"\(cell.columnSpan)\"/>" }
        if let verticalMerge {
            properties += verticalMerge == "restart" ? "<w:vMerge w:val=\"restart\"/>" : "<w:vMerge/>"
        }
        properties += "<w:vAlign w:val=\"\(wordVerticalAlignment(cell.verticalAlignment))\"/>"
        if cell.isHeader { properties += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"D9EAF7\"/>" }

        var block = DocumentBlock(
            type: .paragraph,
            text: cell.text,
            runs: cell.runs,
            direction: direction
        )
        if cell.isHeader {
            block.runs = (block.runs.isEmpty ? [TextRun(text: block.text)] : block.runs).map { run in
                var updated = run
                updated.bold = true
                return updated
            }
        }
        let paragraph = paragraphXML(
            block: block,
            direction: direction,
            options: options,
            alignment: cell.horizontalAlignment
        )
        return "<w:tc><w:tcPr>\(properties)</w:tcPr>\(paragraph)</w:tc>"
    }

    private func imageBlockXML(
        _ block: DocumentBlock,
        page: PageAnalysis,
        extractor: PDFPageExtractor,
        options: ConversionOptions,
        maxWidthPoints: CGFloat
    ) -> String {
        var result = ""
        let description = block.altText.trimmingCharacters(in: .whitespacesAndNewlines)
        let direction = block.direction ?? page.direction

        if options.embedImages,
           let data = extractor.cropImage(
            pageIndex: max(0, page.pageNumber - 1),
            normalizedBox: block.boundingBox,
            maxRenderWidth: 3_200
           ) {
            result += imageDataParagraphXML(
                data: data,
                altText: block.isDecorative ? "" : (description.isEmpty ? block.text : description),
                direction: direction,
                maxWidthPoints: maxWidthPoints,
                forceFullWidth: false
            )
        }

        if options.describeImages,
           options.showImageDescriptions,
           !block.isDecorative,
           !description.isEmpty {
            let descriptionBlock = DocumentBlock(
                type: .paragraph,
                text: L10n.format("وصف العنصر البصري: %@", description),
                direction: direction
            )
            result += paragraphXML(
                block: descriptionBlock,
                style: "ImageDescription",
                direction: direction,
                options: options
            )
        }
        return result
    }

    private func imageDataParagraphXML(
        data: Data,
        altText: String,
        direction: TextDirection,
        maxWidthPoints: CGFloat,
        forceFullWidth: Bool
    ) -> String {
        guard let image = UIImage(data: data) else { return "" }
        let relationID = "rId\(nextImageID)"
        let filename = "image\(images.count + 1).png"
        imageRelationships.append((relationID, "media/\(filename)"))
        images.append(("word/media/\(filename)", data))
        nextImageID += 1

        let sourceWidth = max(1, image.size.width)
        let sourceHeight = max(1, image.size.height)
        let safeMaxWidth = max(72, min(maxWidthPoints, 936))
        let desiredWidth = forceFullWidth ? safeMaxWidth : min(safeMaxWidth, max(72, sourceWidth / 2))
        let desiredHeight = desiredWidth * sourceHeight / sourceWidth
        let widthEMU = max(12_700, Int64(desiredWidth * 12_700))
        let heightEMU = max(12_700, Int64(desiredHeight * 12_700))
        let drawingID = nextDrawingID
        nextDrawingID += 1
        let alt = XML.escape(altText)

        return """
        <w:p>
          <w:pPr>\(direction == .rtl ? "<w:bidi/>" : "")<w:jc w:val="center"/></w:pPr>
          <w:r><w:drawing>
            <wp:inline distT="0" distB="0" distL="0" distR="0">
              <wp:extent cx="\(widthEMU)" cy="\(heightEMU)"/>
              <wp:effectExtent l="0" t="0" r="0" b="0"/>
              <wp:docPr id="\(drawingID)" name="Image \(drawingID)" descr="\(alt)"/>
              <wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>
              <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
                <pic:pic>
                  <pic:nvPicPr><pic:cNvPr id="0" name="\(XML.escape(filename))" descr="\(alt)"/><pic:cNvPicPr/></pic:nvPicPr>
                  <pic:blipFill><a:blip r:embed="\(relationID)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>
                  <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(widthEMU)" cy="\(heightEMU)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>
                </pic:pic>
              </a:graphicData></a:graphic>
            </wp:inline>
          </w:drawing></w:r>
        </w:p>
        """
    }

    private func headerFooterXML(
        blocks: [DocumentBlock],
        isHeader: Bool,
        addPageNumber: Bool,
        options: ConversionOptions
    ) -> String {
        let root = isHeader ? "hdr" : "ftr"
        var content = blocks.map { block in
            paragraphXML(
                block: block,
                style: isHeader ? "HeaderText" : "FooterText",
                direction: block.direction ?? (XML.containsArabic(block.text) ? .rtl : .ltr),
                options: options,
                registerHyperlinks: false
            )
        }.joined()
        if addPageNumber {
            content += """
            <w:p><w:pPr><w:jc w:val="center"/></w:pPr>
              <w:r><w:fldChar w:fldCharType="begin"/></w:r>
              <w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>
              <w:r><w:fldChar w:fldCharType="separate"/></w:r>
              <w:r><w:t>1</w:t></w:r>
              <w:r><w:fldChar w:fldCharType="end"/></w:r>
            </w:p>
            """
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:\(root) xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\(content)</w:\(root)>
        """
    }

    private func footnotesXML(options: ConversionOptions) -> String {
        let items = footnotes.keys.sorted().compactMap { id -> String? in
            guard let block = footnotes[id] else { return nil }
            let paragraph = paragraphXML(
                block: block,
                style: "FootnoteText",
                direction: block.direction ?? (XML.containsArabic(block.text) ? .rtl : .ltr),
                options: options,
                registerHyperlinks: false
            )
            return "<w:footnote w:id=\"\(id)\">\(paragraph)</w:footnote>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:footnotes xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:footnote w:type="separator" w:id="-1"><w:p><w:r><w:separator/></w:r></w:p></w:footnote>
          <w:footnote w:type="continuationSeparator" w:id="0"><w:p><w:r><w:continuationSeparator/></w:r></w:p></w:footnote>
          \(items)
        </w:footnotes>
        """
    }

    private func separatorXML() -> String {
        "<w:p><w:pPr><w:pBdr><w:bottom w:val=\"single\" w:sz=\"6\" w:space=\"1\" w:color=\"B7B7B7\"/></w:pBdr></w:pPr></w:p>"
    }

    private func sectionBreakParagraphXML(
        pageSize: CGSize,
        options: ConversionOptions,
        references: SectionReferences
    ) -> String {
        "<w:p><w:pPr>\(sectionPropertiesXML(pageSize: pageSize, options: options, references: references, nextPage: true))</w:pPr></w:p>"
    }

    private func sectionPropertiesXML(
        pageSize: CGSize,
        options: ConversionOptions,
        references: SectionReferences,
        nextPage: Bool
    ) -> String {
        let width = max(1_440, min(31_680, Int(pageSize.width * 20)))
        let height = max(1_440, min(31_680, Int(pageSize.height * 20)))
        let marginTwips = max(360, Int(options.pageMarginPoints * 20))
        let headerReference = references.headerRelationshipID.map {
            "<w:headerReference w:type=\"default\" r:id=\"\($0)\"/>"
        } ?? ""
        let footerReference = references.footerRelationshipID.map {
            "<w:footerReference w:type=\"default\" r:id=\"\($0)\"/>"
        } ?? ""
        let type = nextPage ? "<w:type w:val=\"nextPage\"/>" : ""
        let orientation = width > height ? " w:orient=\"landscape\"" : ""
        return """
        <w:sectPr>
          \(type)\(headerReference)\(footerReference)
          <w:pgSz w:w="\(width)" w:h="\(height)"\(orientation)/>
          <w:pgMar w:top="\(marginTwips)" w:right="\(marginTwips)" w:bottom="\(marginTwips)" w:left="\(marginTwips)" w:header="480" w:footer="480" w:gutter="0"/>
          <w:cols w:space="720"/>
        </w:sectPr>
        """
    }

    private func stylesXML(options: ConversionOptions) -> String {
        let bodyHalfPoints = Int(options.bodyFontSize * 2)
        let heading1 = Int(options.headingFontSize * 2)
        let heading2 = max(bodyHalfPoints + 4, heading1 - 4)
        let heading3 = max(bodyHalfPoints + 2, heading1 - 8)
        let arabic = XML.escape(options.bodyFontArabic)
        let latin = XML.escape(options.bodyFontLatin)

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:docDefaults>
            <w:rPrDefault><w:rPr><w:rFonts w:ascii="\(latin)" w:hAnsi="\(latin)" w:cs="\(arabic)"/><w:sz w:val="\(bodyHalfPoints)"/><w:szCs w:val="\(bodyHalfPoints)"/><w:lang w:val="en-US" w:bidi="ar-SA"/></w:rPr></w:rPrDefault>
            <w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault>
          </w:docDefaults>
          <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>
          <w:style w:type="character" w:default="1" w:styleId="DefaultParagraphFont"><w:name w:val="Default Paragraph Font"/><w:uiPriority w:val="1"/><w:semiHidden/><w:unhideWhenUsed/></w:style>
          <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="240" w:after="120"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:bCs/><w:sz w:val="\(heading1)"/><w:szCs w:val="\(heading1)"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="200" w:after="100"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:bCs/><w:sz w:val="\(heading2)"/><w:szCs w:val="\(heading2)"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="160" w:after="80"/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:bCs/><w:sz w:val="\(heading3)"/><w:szCs w:val="\(heading3)"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="720" w:right="720"/><w:spacing w:before="120" w:after="120"/></w:pPr><w:rPr><w:i/><w:iCs/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Caption"><w:name w:val="Caption"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:jc w:val="center"/></w:pPr><w:rPr><w:i/><w:iCs/><w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="ImageDescription"><w:name w:val="Image Description"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="360" w:right="360"/><w:spacing w:after="160"/></w:pPr><w:rPr><w:i/><w:iCs/><w:color w:val="404040"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="HeaderText"><w:name w:val="Header Text"/><w:basedOn w:val="Normal"/><w:rPr><w:color w:val="666666"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="FooterText"><w:name w:val="Footer Text"/><w:basedOn w:val="Normal"/><w:rPr><w:color w:val="666666"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="FootnoteText"><w:name w:val="Footnote Text"/><w:basedOn w:val="Normal"/><w:rPr><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="TextBox"><w:name w:val="Text Box"/><w:basedOn w:val="Normal"/><w:pPr><w:pBdr><w:top w:val="single" w:sz="4" w:color="A0A0A0"/><w:left w:val="single" w:sz="4" w:color="A0A0A0"/><w:bottom w:val="single" w:sz="4" w:color="A0A0A0"/><w:right w:val="single" w:sz="4" w:color="A0A0A0"/></w:pBdr><w:shd w:val="clear" w:fill="F7F7F7"/></w:pPr></w:style>
          <w:style w:type="paragraph" w:styleId="Equation"><w:name w:val="Equation"/><w:basedOn w:val="Normal"/><w:pPr><w:jc w:val="center"/><w:keepLines/></w:pPr><w:rPr><w:rFonts w:ascii="Cambria Math" w:hAnsi="Cambria Math"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="FormField"><w:name w:val="Form Field"/><w:basedOn w:val="Normal"/><w:pPr><w:keepLines/><w:spacing w:after="80"/></w:pPr></w:style>
        </w:styles>
        """
    }

    private func numberingXML() -> String {
        let styles: [(id: Int, format: String, levelText: (Int) -> String)] = [
            (1, "bullet", { _ in "•" }),
            (2, "decimal", { "%\($0 + 1)." }),
            (3, "decimal", { "%\($0 + 1)." }),
            (4, "lowerLetter", { "%\($0 + 1)." }),
            (5, "upperLetter", { "%\($0 + 1)." }),
            (6, "lowerRoman", { "%\($0 + 1)." }),
            (7, "upperRoman", { "%\($0 + 1)." })
        ]
        let abstracts = styles.map { style in
            let levels = (0..<9).map { level in
                let indent = 720 + level * 360
                let hanging = 360
                let format = style.id == 1 ? "bullet" : style.format
                let text = style.id == 1 ? (level % 2 == 0 ? "•" : "◦") : style.levelText(level)
                return """
                <w:lvl w:ilvl="\(level)"><w:start w:val="1"/><w:numFmt w:val="\(format)"/><w:lvlText w:val="\(text)"/><w:lvlJc w:val="start"/><w:pPr><w:tabs><w:tab w:val="num" w:pos="\(indent)"/></w:tabs><w:ind w:start="\(indent)" w:hanging="\(hanging)"/></w:pPr></w:lvl>
                """
            }.joined()
            return "<w:abstractNum w:abstractNumId=\"\(style.id)\"><w:multiLevelType w:val=\"multilevel\"/>\(levels)</w:abstractNum>"
        }.joined()
        let instances = styles.map {
            "<w:num w:numId=\"\($0.id)\"><w:abstractNumId w:val=\"\($0.id)\"/></w:num>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\(abstracts)\(instances)</w:numbering>
        """
    }

    private func settingsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:zoom w:percent="100"/><w:defaultTabStop w:val="720"/><w:characterSpacingControl w:val="doNotCompress"/><w:doNotAutoCompressPictures/><w:updateFields w:val="true"/><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat>
        </w:settings>
        """
    }

    private func documentRelationshipsXML() -> String {
        var relationships = """
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>
        <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
        """
        if !footnotes.isEmpty {
            relationships += "<Relationship Id=\"rId4\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes\" Target=\"footnotes.xml\"/>"
        }
        for part in headerParts {
            relationships += "<Relationship Id=\"\(part.relationshipID)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/header\" Target=\"\(part.target)\"/>"
        }
        for part in footerParts {
            relationships += "<Relationship Id=\"\(part.relationshipID)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer\" Target=\"\(part.target)\"/>"
        }
        for image in imageRelationships {
            relationships += "<Relationship Id=\"\(image.id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"\(XML.escape(image.target))\"/>"
        }
        for hyperlink in hyperlinkRelationships {
            relationships += "<Relationship Id=\"\(hyperlink.id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(XML.escape(hyperlink.target))\" TargetMode=\"External\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(relationships)</Relationships>
        """
    }

    private func contentTypesXML() -> String {
        let headers = headerParts.enumerated().map { index, _ in
            "<Override PartName=\"/word/header\(index + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml\"/>"
        }.joined()
        let footers = footerParts.enumerated().map { index, _ in
            "<Override PartName=\"/word/footer\(index + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml\"/>"
        }.joined()
        let footnotesType = footnotes.isEmpty ? "" : "<Override PartName=\"/word/footnotes.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml\"/>"
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Default Extension="png" ContentType="image/png"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
          <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
          <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
          <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
          \(headers)\(footers)\(footnotesType)
          <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
          <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
        </Types>
        """
    }

    private func rootRelationshipsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
          <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
        </Relationships>
        """
    }

    private func corePropertiesXML(title: String) -> String {
        let formatter = ISO8601DateFormatter()
        let now = formatter.string(from: Date())
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:title>\(XML.escape(title))</dc:title><dc:creator>PDFToWord</dc:creator><cp:lastModifiedBy>PDFToWord</cp:lastModifiedBy><dcterms:created xsi:type="dcterms:W3CDTF">\(now)</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">\(now)</dcterms:modified>
        </cp:coreProperties>
        """
    }

    private func appPropertiesXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"><Application>PDFToWord</Application><DocSecurity>0</DocSecurity><ScaleCrop>false</ScaleCrop><Company></Company><LinksUpToDate>false</LinksUpToDate><SharedDoc>false</SharedDoc><HyperlinksChanged>false</HyperlinksChanged><AppVersion>2.0</AppVersion></Properties>
        """
    }

    private func numberingID(for style: ListStyle) -> Int {
        switch style {
        case .bullet: return 1
        case .decimal: return 2
        case .arabicIndic: return 3
        case .lowerLetter: return 4
        case .upperLetter: return 5
        case .lowerRoman: return 6
        case .upperRoman: return 7
        }
    }

    private func wordAlignment(_ alignment: CellHorizontalAlignment, direction: TextDirection) -> String {
        switch alignment {
        case .start: return direction == .rtl ? "right" : "left"
        case .center: return "center"
        case .end: return direction == .rtl ? "left" : "right"
        case .justify: return "both"
        }
    }

    private func wordVerticalAlignment(_ alignment: CellVerticalAlignment) -> String {
        switch alignment {
        case .top: return "top"
        case .center: return "center"
        case .bottom: return "bottom"
        }
    }

    private func hyperlinkRelationshipID(for url: String) -> String {
        if let existing = hyperlinkIDs[url] { return existing }
        let relationshipID = "rId\(nextHyperlinkID)"
        nextHyperlinkID += 1
        hyperlinkIDs[url] = relationshipID
        hyperlinkRelationships.append((relationshipID, url))
        return relationshipID
    }

    private func bookmarkID(for name: String) -> Int {
        if let existing = bookmarkIDs[name] { return existing }
        let value = nextBookmarkID
        nextBookmarkID += 1
        bookmarkIDs[name] = value
        return value
    }

    private func utf8(_ string: String) -> Data { Data(string.utf8) }
}
