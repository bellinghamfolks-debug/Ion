import Foundation
import ZIPFoundation

struct PresentationMedia: Sendable {
    let name: String
    let mimeType: String
    let url: URL
    let altText: String
}

struct PresentationSlide: Sendable {
    let index: Int
    let text: String
    let images: [PresentationMedia]
    let tables: [[[String]]]
    let speakerNotes: String
    let structuredText: String
    let hyperlinks: [String]
    let hidden: Bool
}

struct PresentationDeck: Sendable {
    let slides: [PresentationSlide]
}

enum PPTXExtractor {
    static func parse(url: URL, into extractionDirectory: URL) throws -> PresentationDeck {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
        try fileManager.unzipItem(at: url, to: extractionDirectory)

        let slidesDirectory = extractionDirectory.appendingPathComponent("ppt/slides", isDirectory: true)
        guard let files = try? fileManager.contentsOfDirectory(
            at: slidesDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { throw BasirError.emptyDocument }

        let pattern = try NSRegularExpression(pattern: #"^slide([0-9]+)\.xml$"#)
        var indexed: [(Int, URL)] = []
        for file in files {
            let name = file.lastPathComponent
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            guard let match = pattern.firstMatch(in: name, range: range),
                  let numberRange = Range(match.range(at: 1), in: name),
                  let index = Int(name[numberRange]) else { continue }
            indexed.append((index, file))
        }
        indexed.sort { $0.0 < $1.0 }

        var slides: [PresentationSlide] = []
        for (index, slideURL) in indexed {
            try Task.checkCancellation()
            let slideData = try Data(contentsOf: slideURL, options: .mappedIfSafe)
            let content = SlideContentParser.parse(slideData)
            let relsURL = slidesDirectory
                .appendingPathComponent("_rels", isDirectory: true)
                .appendingPathComponent("slide\(index).xml.rels")
            var media: [PresentationMedia] = []
            var hyperlinks: [String] = []
            var structuredChunks: [String] = []
            var notes = ""
            if fileManager.fileExists(atPath: relsURL.path) {
                let relationships = RelationshipParser.parse(
                    try Data(contentsOf: relsURL, options: .mappedIfSafe)
                )
                let requestedIDs = content.imageRelationshipIDs.isEmpty
                    ? relationships.compactMap { $0.value.isImage ? $0.key : nil }.sorted()
                    : content.imageRelationshipIDs
                var emittedPaths: Set<String> = []
                for relationshipID in requestedIDs {
                    guard let relationship = relationships[relationshipID], relationship.isImage else { continue }
                    let mediaURL = URL(fileURLWithPath: relationship.target,
                                       relativeTo: slidesDirectory).standardizedFileURL
                    guard mediaURL.path.hasPrefix(extractionDirectory.standardizedFileURL.path + "/"),
                          fileManager.fileExists(atPath: mediaURL.path),
                          emittedPaths.insert(mediaURL.path).inserted else { continue }
                    let mime = mimeType(for: mediaURL)
                    guard mime.hasPrefix("image/") else { continue }
                    media.append(PresentationMedia(
                        name: mediaURL.lastPathComponent,
                        mimeType: mime,
                        url: mediaURL,
                        altText: content.imageAltText[relationshipID] ?? ""
                    ))
                }
                for relationship in relationships.values {
                    if relationship.isHyperlink {
                        hyperlinks.append(relationship.target)
                    } else if relationship.isChart || relationship.isDiagram {
                        let relatedURL = URL(fileURLWithPath: relationship.target,
                                             relativeTo: slidesDirectory).standardizedFileURL
                        if relatedURL.path.hasPrefix(extractionDirectory.standardizedFileURL.path + "/"),
                           let data = try? Data(contentsOf: relatedURL) {
                            let text = SimpleOfficeTextParser.parse(data)
                            if !text.isEmpty { structuredChunks.append(text) }
                        }
                    } else if relationship.isNotes {
                        let notesURL = URL(fileURLWithPath: relationship.target,
                                           relativeTo: slidesDirectory).standardizedFileURL
                        if notesURL.path.hasPrefix(extractionDirectory.standardizedFileURL.path + "/"),
                           let data = try? Data(contentsOf: notesURL) {
                            notes = SimpleOfficeTextParser.parse(data)
                        }
                    }
                }
            }
            let text = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty || !media.isEmpty || !content.tables.isEmpty || !notes.isEmpty {
                slides.append(PresentationSlide(
                    index: index,
                    text: text,
                    images: media,
                    tables: content.tables,
                    speakerNotes: notes,
                    structuredText: structuredChunks.joined(separator: "\n"),
                    hyperlinks: hyperlinks,
                    hidden: content.hidden
                ))
            }
        }
        return PresentationDeck(slides: slides)
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        case "svg": return "image/svg+xml"
        case "tif", "tiff": return "image/tiff"
        default: return "application/octet-stream"
        }
    }
}

private struct SlideContent {
    let text: String
    let imageRelationshipIDs: [String]
    let imageAltText: [String: String]
    let tables: [[[String]]]
    let hidden: Bool
}

private final class SlideContentParser: NSObject, XMLParserDelegate {
    private var collectingText = false
    private var textBuffer = ""
    private var chunks: [String] = []
    private var imageIDs: [String] = []
    private var imageAltText: [String: String] = [:]
    private var pendingAltText = ""
    private var shapeDepth = 0
    private var shapeChunks: [String] = []
    private var shapeX = Int.max
    private var shapeY = Int.max
    private var positionedShapes: [(x: Int, y: Int, text: String)] = []
    private var tableDepth = 0
    private var cellDepth = 0
    private var currentCell: [String] = []
    private var currentRow: [String] = []
    private var currentTable: [[String]] = []
    private var tables: [[[String]]] = []
    private var hidden = false

    static func parse(_ data: Data) -> SlideContent {
        let delegate = SlideContentParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        _ = parser.parse()
        let ordered = delegate.positionedShapes
            .sorted { lhs, rhs in lhs.y == rhs.y ? lhs.x < rhs.x : lhs.y < rhs.y }
            .map(\.text)
        let text = ordered.isEmpty ? delegate.chunks : ordered
        return SlideContent(text: text.joined(separator: "\n"),
                            imageRelationshipIDs: delegate.imageIDs,
                            imageAltText: delegate.imageAltText,
                            tables: delegate.tables,
                            hidden: delegate.hidden)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let local = Self.localName(elementName)
        if local == "sld", attributeDict["show"] == "0" {
            hidden = true
        } else if local == "sp" || local == "graphicFrame" {
            shapeDepth += 1
            if shapeDepth == 1 {
                shapeChunks = []
                shapeX = Int.max
                shapeY = Int.max
            }
        } else if local == "off", shapeDepth > 0 {
            shapeX = Int(attributeDict["x"] ?? "") ?? shapeX
            shapeY = Int(attributeDict["y"] ?? "") ?? shapeY
        } else if local == "tbl" {
            tableDepth += 1
            if tableDepth == 1 { currentTable = [] }
        } else if local == "tr", tableDepth > 0 {
            currentRow = []
        } else if local == "tc", tableDepth > 0 {
            cellDepth += 1
            currentCell = []
        } else if local == "t" {
            collectingText = true
            textBuffer = ""
        } else if local == "cNvPr" {
            pendingAltText = attributeDict["descr"] ?? attributeDict["title"] ?? ""
        } else if local == "blip" {
            if let relationship = attributeDict["r:embed"] ?? attributeDict["embed"],
               !relationship.isEmpty {
                imageIDs.append(relationship)
                if !pendingAltText.isEmpty { imageAltText[relationship] = pendingAltText }
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collectingText { textBuffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if Self.localName(elementName) == "t" {
            let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                chunks.append(value)
                if shapeDepth > 0 { shapeChunks.append(value) }
                if cellDepth > 0 { currentCell.append(value) }
            }
            collectingText = false
            textBuffer = ""
        } else if Self.localName(elementName) == "tc", tableDepth > 0 {
            currentRow.append(currentCell.joined(separator: " "))
            currentCell = []
            cellDepth = max(0, cellDepth - 1)
        } else if Self.localName(elementName) == "tr", tableDepth > 0 {
            if !currentRow.isEmpty { currentTable.append(currentRow) }
            currentRow = []
        } else if Self.localName(elementName) == "tbl" {
            if !currentTable.isEmpty { tables.append(currentTable) }
            currentTable = []
            tableDepth = max(0, tableDepth - 1)
        } else if Self.localName(elementName) == "sp" || Self.localName(elementName) == "graphicFrame" {
            if shapeDepth == 1 {
                let value = shapeChunks.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { positionedShapes.append((shapeX, shapeY, value)) }
            }
            shapeDepth = max(0, shapeDepth - 1)
        }
    }

    private static func localName(_ value: String) -> String {
        value.split(separator: ":").last.map(String.init) ?? value
    }
}

private struct PresentationRelationship {
    let target: String
    let type: String
    let targetMode: String
    var isImage: Bool { type.lowercased().hasSuffix("/image") }
    var isHyperlink: Bool { type.lowercased().hasSuffix("/hyperlink") || targetMode.lowercased() == "external" }
    var isChart: Bool { type.lowercased().hasSuffix("/chart") }
    var isDiagram: Bool { type.lowercased().contains("/diagram") }
    var isNotes: Bool { type.lowercased().hasSuffix("/notesslide") }
}

private final class RelationshipParser: NSObject, XMLParserDelegate {
    private var relationships: [String: PresentationRelationship] = [:]

    static func parse(_ data: Data) -> [String: PresentationRelationship] {
        let delegate = RelationshipParser()
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
        relationships[id] = PresentationRelationship(
            target: target,
            type: attributeDict["Type"] ?? attributeDict["type"] ?? "",
            targetMode: attributeDict["TargetMode"] ?? attributeDict["targetMode"] ?? ""
        )
    }
}

private final class SimpleOfficeTextParser: NSObject, XMLParserDelegate {
    private var collecting = false
    private var buffer = ""
    private var chunks: [String] = []

    static func parse(_ data: Data) -> String {
        let delegate = SimpleOfficeTextParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.chunks.joined(separator: "\n")
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if local == "t" || local == "v" { collecting = true; buffer = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collecting { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if local == "t" || local == "v" {
            let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { chunks.append(value) }
            collecting = false
        }
    }
}

