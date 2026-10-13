import Foundation
import ZIPFoundation

/// Checks a Word file the server returned before it is shown or saved.
enum DocxValidator {
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

