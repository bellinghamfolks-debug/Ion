import XCTest
@testable import Basir

final class DocxWriterTests: XCTestCase {
    func testAccessibleDocumentContainsRealStructuresAndMixedDirectionRuns() throws {
        var writer = DocxWriter(rtl: true)
        writer.append(.heading(level: 1, runs: [.init(text: "عنوان الاختبار")]))
        writer.append(.paragraph(runs: [
            .init(text: "الهاتف: ", direction: .rtl),
            .init(text: "+966 55 123 4567", bold: true,
                  url: "tel:+966551234567", direction: .ltr)
        ]))
        writer.append(.listItem(level: 0, ordered: true,
                                runs: [.init(text: "البند الأول")]))
        writer.append(.table(rows: [["العنصر", "القيمة"], ["رمز", "AX19-B7"]],
                             rowHeader: true))

        let archive = try ZipReader(data: writer.archive())
        let document = try XCTUnwrap(
            String(data: archive.read("word/document.xml"), encoding: .utf8))
        let relationships = try XCTUnwrap(
            String(data: archive.read("word/_rels/document.xml.rels"), encoding: .utf8))

        XCTAssertTrue(document.contains("w:tbl"))
        XCTAssertTrue(document.contains("w:numPr"))
        XCTAssertTrue(document.contains("w:rtl"))
        XCTAssertTrue(document.contains("w:bidi"))
        XCTAssertTrue(document.contains("+966 55 123 4567"))
        XCTAssertTrue(document.contains("w:hyperlink"))
        XCTAssertTrue(relationships.contains("tel:+966551234567"))
    }

    func testMarkdownLikeSpacesDoNotCreateTables() throws {
        var writer = DocxWriter(rtl: false)
        writer.appendPlain("ordinary text    with spaces\nsecond paragraph")
        let archive = try ZipReader(data: writer.archive())
        let document = try XCTUnwrap(
            String(data: archive.read("word/document.xml"), encoding: .utf8))
        XCTAssertFalse(document.contains("<w:tbl>"))
    }
}
