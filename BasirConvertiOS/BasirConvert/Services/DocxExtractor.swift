import Foundation
import UIKit
import ZIPFoundation

enum ExtractedDocumentBlock {
    case heading(Int, String)
    case paragraph(String)
    case table([[String]])
    case image(PreparedImage, altText: String, title: String)
    case list(String, ordered: Bool, level: Int)
    case hyperlink(String, url: String)
    case math(String)

    var markdown: String? {
        switch self {
        case .heading(let level, let text):
            return String(repeating: "#", count: max(1, min(6, level))) + " " + text
        case .paragraph(let text):
            return text
        case .table(let rows):
            guard let first = rows.first, !first.isEmpty else { return nil }
            func row(_ cells: [String]) -> String {
                "| " + cells.map {
                    $0.replacingOccurrences(of: "|", with: "\\|")
                        .replacingOccurrences(of: "\n", with: "<br>")
                }.joined(separator: " | ") + " |"
            }
            let separator = "| " + first.map { _ in "---" }.joined(separator: " | ") + " |"
            return ([row(first), separator] + rows.dropFirst().map(row)).joined(separator: "\n")
        case .image:
            return nil
        case .list(let text, let ordered, let level):
            let prefix = ordered ? "1. " : "- "
            return String(repeating: "  ", count: level) + prefix + text
        case .hyperlink(let text, let url):
            return "[\(text)](\(url))"
        case .math:
            return nil
        }
    }
}

struct ExtractedDocument {
    let blocks: [ExtractedDocumentBlock]
    var containsReadableContent: Bool { !blocks.isEmpty }
}

enum DocxExtractor {
    static func parse(url: URL) throws -> ExtractedDocument {
        let archive = try Archive(url: url, accessMode: .read)
        guard let documentEntry = archive["word/document.xml"] else {
            throw BasirError.emptyDocument
        }
        let documentData = try data(for: documentEntry, in: archive)
        let orderedNumberingIDs: Set<String>
        if let numbering = archive["word/numbering.xml"] {
            orderedNumberingIDs = NumberingParser.orderedNumberingIDs(
                try data(for: numbering, in: archive)
            )
        } else { orderedNumberingIDs = [] }
        let rawBlocks = DocumentXMLParser.parse(documentData, orderedNumberingIDs: orderedNumberingIDs)

        var relationships: [String: DocumentRelationship] = [:]
        if let rels = archive["word/_rels/document.xml.rels"] {
            relationships = DocumentRelationshipParser.parse(try data(for: rels, in: archive))
        }

        var blocks = try resolvedBlocks(rawBlocks, relationships: relationships, archive: archive)

        let supplementalParts: [(prefix: String, title: String)] = [
            ("word/header", "Header"),
            ("word/footer", "Footer"),
            ("word/footnotes.xml", "Footnotes"),
            ("word/endnotes.xml", "Endnotes"),
            ("word/comments.xml", "Comments")
        ]
        for part in supplementalParts {
            let entries = archive.filter { entry in
                entry.type == .file && (part.prefix.hasSuffix(".xml")
                    ? entry.path == part.prefix
                    : entry.path.hasPrefix(part.prefix) && entry.path.hasSuffix(".xml"))
            }
            for entry in entries.sorted(by: { $0.path < $1.path }) {
                let raw = DocumentXMLParser.parse(
                    try data(for: entry, in: archive),
                    orderedNumberingIDs: orderedNumberingIDs
                )
                let resolved = try resolvedBlocks(raw, relationships: [:], archive: archive)
                if !resolved.isEmpty {
                    blocks.append(.heading(2, part.title))
                    blocks.append(contentsOf: resolved)
                }
            }
        }
        return ExtractedDocument(blocks: blocks)
    }

    private static func resolvedBlocks(
        _ rawBlocks: [RawDocumentBlock],
        relationships: [String: DocumentRelationship],
        archive: Archive
    ) throws -> [ExtractedDocumentBlock] {
        var blocks: [ExtractedDocumentBlock] = []
        for raw in rawBlocks {
            switch raw {
            case .heading(let level, let text):
                blocks.append(.heading(level, text))
            case .paragraph(let text):
                blocks.append(.paragraph(text))
            case .table(let rows):
                blocks.append(.table(rows))
            case .list(let text, let ordered, let level):
                blocks.append(.list(text, ordered: ordered, level: level))
            case .hyperlink(let text, let relationshipID):
                guard let relationship = relationships[relationshipID], relationship.isHyperlink,
                      relationship.target.lowercased().hasPrefix("https://")
                        || relationship.target.lowercased().hasPrefix("http://")
                        || relationship.target.lowercased().hasPrefix("mailto:") else {
                    if !text.isEmpty { blocks.append(.paragraph(text)) }
                    continue
                }
                blocks.append(.hyperlink(text, url: relationship.target))
            case .math(let expression):
                blocks.append(.math(expression))
            case .image(let reference):
                guard let relationship = relationships[reference.relationshipID], relationship.isImage else { continue }
                let normalized = normalizeWordTarget(relationship.target)
                guard let entry = archive[normalized] else { continue }
                let bytes = try data(for: entry, in: archive)
                guard let prepared = prepareImage(bytes, extensionName: URL(fileURLWithPath: relationship.target).pathExtension) else {
                    continue
                }
                blocks.append(.image(
                    prepared,
                    altText: reference.altText.isEmpty ? "Image from the source Word document" : reference.altText,
                    title: reference.title.isEmpty ? "Source Word image" : reference.title
                ))
            }
        }
        return blocks
    }

    private static func data(for entry: Entry, in archive: Archive) throws -> Data {
        var output = Data()
        _ = try archive.extract(entry) { output.append($0) }
        return output
    }

    private static func normalizeWordTarget(_ target: String) -> String {
        var value = target.replacingOccurrences(of: "\\", with: "/")
        while value.hasPrefix("../") { value.removeFirst(3) }
        if value.hasPrefix("/") { value.removeFirst() }
        if value.hasPrefix("word/") { return value }
        return "word/" + value
    }

    private static func prepareImage(_ data: Data, extensionName: String) -> PreparedImage? {
        guard let image = UIImage(data: data) else { return nil }
        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)
        let ext = extensionName.lowercased()
        if ext == "png" {
            return PreparedImage(data: data, mimeType: "image/png",
                                 pixelWidth: width, pixelHeight: height)
        }
        if ext == "jpg" || ext == "jpeg" {
            return PreparedImage(data: data, mimeType: "image/jpeg",
                                 pixelWidth: width, pixelHeight: height)
        }
        if let png = image.pngData() {
            return PreparedImage(data: png, mimeType: "image/png",
                                 pixelWidth: width, pixelHeight: height)
        }
        return nil
    }
}

private struct DocumentImageReference {
    let relationshipID: String
    let altText: String
    let title: String
}

private enum RawDocumentBlock {
    case heading(Int, String)
    case paragraph(String)
    case table([[String]])
    case image(DocumentImageReference)
    case list(String, ordered: Bool, level: Int)
    case hyperlink(String, relationshipID: String)
    case math(String)
}

private final class DocumentXMLParser: NSObject, XMLParserDelegate {
    private var blocks: [RawDocumentBlock] = []
    private var insideParagraph = false
    private var collectingText = false
    private var paragraphText = ""
    private var paragraphLevel: Int?
    private var paragraphImages: [DocumentImageReference] = []
    private var pendingAlt = ""
    private var pendingImageTitle = ""
    private var paragraphListLevel: Int?
    private var paragraphNumberingID: String?
    private var insideHyperlink = false
    private var hyperlinkID = ""
    private var hyperlinkText = ""
    private var deletedDepth = 0
    private var mathDepth = 0
    private var mathText = ""
    private var orderedNumberingIDs: Set<String> = []

    private var insideTable = false
    private var currentTable: [[String]] = []
    private var insideRow = false
    private var currentRow: [String] = []
    private var insideCell = false
    private var currentCellParagraphs: [String] = []
    private var deferredTableImages: [DocumentImageReference] = []
    private var currentCellGridSpan = 1
    private var currentCellVMerge: String?

    static func parse(_ data: Data, orderedNumberingIDs: Set<String>) -> [RawDocumentBlock] {
        let delegate = DocumentXMLParser()
        delegate.orderedNumberingIDs = orderedNumberingIDs
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        _ = parser.parse()
        return delegate.blocks
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let local = Self.localName(elementName)
        switch local {
        case "del":
            deletedDepth += 1
        case "tbl":
            insideTable = true
            currentTable = []
            deferredTableImages = []
        case "tr":
            insideRow = true
            currentRow = []
        case "tc":
            insideCell = true
            currentCellParagraphs = []
            currentCellGridSpan = 1
            currentCellVMerge = nil
        case "gridSpan":
            currentCellGridSpan = max(1, Int(attributeDict["w:val"] ?? attributeDict["val"] ?? "1") ?? 1)
        case "vMerge":
            currentCellVMerge = (attributeDict["w:val"] ?? attributeDict["val"] ?? "continue").lowercased()
        case "p":
            insideParagraph = true
            paragraphText = ""
            paragraphLevel = nil
            paragraphImages = []
            pendingAlt = ""
            pendingImageTitle = ""
            paragraphListLevel = nil
            paragraphNumberingID = nil
        case "oMath":
            if mathDepth == 0 {
                let leading = Self.clean(paragraphText)
                if !leading.isEmpty {
                    if insideCell { currentCellParagraphs.append(leading) }
                    else { blocks.append(.paragraph(leading)) }
                    paragraphText = ""
                }
                mathText = ""
            }
            mathDepth += 1
        case "ilvl":
            paragraphListLevel = Int(attributeDict["w:val"] ?? attributeDict["val"] ?? "0") ?? 0
        case "numId":
            paragraphNumberingID = attributeDict["w:val"] ?? attributeDict["val"]
        case "hyperlink":
            insideHyperlink = true
            hyperlinkID = attributeDict["r:id"] ?? attributeDict["id"] ?? ""
            hyperlinkText = ""
        case "pStyle":
            let style = attributeDict["w:val"] ?? attributeDict["val"] ?? ""
            if let range = style.range(of: #"(?i)heading\s*([1-6])"#, options: .regularExpression),
               let digit = style[range].last, let level = Int(String(digit)) {
                paragraphLevel = level
            } else if style.lowercased() == "title" {
                paragraphLevel = 1
            }
        case "t":
            collectingText = true
        case "tab":
            if insideParagraph { paragraphText += "\t" }
        case "br", "cr":
            if insideParagraph, !paragraphText.hasSuffix("\n") { paragraphText += "\n" }
        case "docPr", "cNvPr":
            pendingAlt = attributeDict["descr"] ?? pendingAlt
            pendingImageTitle = attributeDict["name"] ?? attributeDict["title"] ?? pendingImageTitle
        case "blip":
            if let id = attributeDict["r:embed"] ?? attributeDict["embed"], !id.isEmpty {
                paragraphImages.append(DocumentImageReference(
                    relationshipID: id,
                    altText: pendingAlt,
                    title: pendingImageTitle
                ))
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collectingText, deletedDepth == 0 {
            if mathDepth > 0 { mathText += string }
            else if insideParagraph {
                if insideHyperlink { hyperlinkText += string }
                else { paragraphText += string }
            }
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let local = Self.localName(elementName)
        switch local {
        case "del":
            deletedDepth = max(0, deletedDepth - 1)
        case "hyperlink":
            let clean = Self.clean(hyperlinkText)
            if !clean.isEmpty, !hyperlinkID.isEmpty {
                if !Self.clean(paragraphText).isEmpty {
                    blocks.append(.paragraph(Self.clean(paragraphText)))
                    paragraphText = ""
                }
                blocks.append(.hyperlink(clean, relationshipID: hyperlinkID))
            }
            insideHyperlink = false
            hyperlinkID = ""
            hyperlinkText = ""
        case "oMath":
            mathDepth = max(0, mathDepth - 1)
            if mathDepth == 0 {
                let expression = Self.clean(mathText)
                if !expression.isEmpty {
                    if insideCell { currentCellParagraphs.append("Equation: \(expression)") }
                    else { blocks.append(.math(expression)) }
                }
                mathText = ""
            }
        case "t":
            collectingText = false
        case "p":
            let text = Self.clean(paragraphText)
            if insideCell {
                if !text.isEmpty { currentCellParagraphs.append(text) }
                for image in paragraphImages {
                    let label = image.altText.isEmpty ? image.title : image.altText
                    if !label.isEmpty { currentCellParagraphs.append("[Image: \(label)]") }
                }
                deferredTableImages.append(contentsOf: paragraphImages)
            } else {
                if !text.isEmpty {
                    if let level = paragraphLevel { blocks.append(.heading(level, text)) }
                    else if let numberingID = paragraphNumberingID {
                        blocks.append(.list(text,
                                            ordered: orderedNumberingIDs.contains(numberingID),
                                            level: paragraphListLevel ?? 0))
                    }
                    else { blocks.append(.paragraph(text)) }
                }
                blocks.append(contentsOf: paragraphImages.map(RawDocumentBlock.image))
            }
            insideParagraph = false
            paragraphText = ""
            paragraphImages = []
        case "tc":
            var value = currentCellParagraphs.joined(separator: "\n")
            if let merge = currentCellVMerge {
                value = "[[BASIR_VMERGE:\(merge)]]" + value
            }
            if currentCellGridSpan > 1 {
                value = "[[BASIR_GRIDSPAN:\(currentCellGridSpan)]]" + value
            }
            currentRow.append(value)
            if currentCellGridSpan > 1 {
                currentRow.append(contentsOf: repeatElement("[[BASIR_MERGED]]", count: currentCellGridSpan - 1))
            }
            currentCellParagraphs = []
            insideCell = false
        case "tr":
            if !currentRow.isEmpty { currentTable.append(currentRow) }
            currentRow = []
            insideRow = false
        case "tbl":
            if !currentTable.isEmpty { blocks.append(.table(currentTable)) }
            blocks.append(contentsOf: deferredTableImages.map(RawDocumentBlock.image))
            currentTable = []
            deferredTableImages = []
            insideTable = false
        default:
            break
        }
    }

    private static func localName(_ value: String) -> String {
        value.split(separator: ":").last.map(String.init) ?? value
    }

    private static func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class DocumentRelationshipParser: NSObject, XMLParserDelegate {
    private var relationships: [String: DocumentRelationship] = [:]

    static func parse(_ data: Data) -> [String: DocumentRelationship] {
        let delegate = DocumentRelationshipParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        _ = parser.parse()
        return delegate.relationships
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        guard elementName.split(separator: ":").last == "Relationship",
              let id = attributeDict["Id"] ?? attributeDict["id"],
              let target = attributeDict["Target"] ?? attributeDict["target"] else { return }
        relationships[id] = DocumentRelationship(
            target: target,
            type: attributeDict["Type"] ?? attributeDict["type"] ?? "",
            external: (attributeDict["TargetMode"] ?? attributeDict["targetMode"] ?? "").lowercased() == "external"
        )
    }
}

private struct DocumentRelationship {
    let target: String
    let type: String
    let external: Bool
    var isImage: Bool { type.lowercased().hasSuffix("/image") }
    var isHyperlink: Bool { external && type.lowercased().hasSuffix("/hyperlink") }
}

private final class NumberingParser: NSObject, XMLParserDelegate {
    private var currentAbstract = ""
    private var orderedAbstracts: Set<String> = []
    private var currentNumberID = ""
    private var numberToAbstract: [String: String] = [:]

    static func orderedNumberingIDs(_ data: Data) -> Set<String> {
        let delegate = NumberingParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        _ = parser.parse()
        return Set(delegate.numberToAbstract.compactMap { key, value in
            delegate.orderedAbstracts.contains(value) ? key : nil
        })
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        let value = attributeDict["w:val"] ?? attributeDict["val"] ?? ""
        if local == "abstractNum" {
            currentAbstract = attributeDict["w:abstractNumId"] ?? attributeDict["abstractNumId"] ?? ""
        } else if local == "numFmt", value.lowercased() != "bullet", !currentAbstract.isEmpty {
            orderedAbstracts.insert(currentAbstract)
        } else if local == "num" {
            currentNumberID = attributeDict["w:numId"] ?? attributeDict["numId"] ?? ""
        } else if local == "abstractNumId", !currentNumberID.isEmpty {
            numberToAbstract[currentNumberID] = value
        }
    }
}

