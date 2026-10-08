import XCTest
@testable import BasirConvert

final class ReaderContentTests: XCTestCase {
    func testRecognisesBasirPageMarkers() {
        XCTAssertEqual(ReaderContent.pageNumber(in: "الصفحة 12"), 12)
        XCTAssertEqual(ReaderContent.pageNumber(in: "صفحة ١٢"), 12)
        XCTAssertEqual(ReaderContent.pageNumber(in: "Page 3"), 3)
        XCTAssertEqual(ReaderContent.pageNumber(in: "Source page 40"), 40)
    }

    func testOrdinaryTextIsNotAPageMarker() {
        XCTAssertNil(ReaderContent.pageNumber(in: "الصفحة الرئيسية للموقع"))
        XCTAssertNil(ReaderContent.pageNumber(in: "Pages 3"))
        XCTAssertNil(ReaderContent.pageNumber(in: "Page 3 explains the method used in this study"))
    }

    func testTableRowNamesEachCellByItsColumn() {
        let sentence = ReaderContent.rowSentence(["أحمد", "", "90"], headers: ["الاسم", "الصف", "الدرجة"])
        XCTAssertEqual(sentence, "الاسم: أحمد، الدرجة: 90")
    }

    func testSpeechLanguageFollowsTheScript() {
        XCTAssertEqual(ReaderContent.speechLanguage(for: "مرحبا بكم في بصير"), "ar-SA")
        XCTAssertEqual(ReaderContent.speechLanguage(for: "Welcome to Basir"), "en-US")
        XCTAssertEqual(ReaderContent.speechLanguage(for: "تقرير PDF السنوي"), "ar-SA")
    }

    func testBlocksDropEmptyParagraphsAndMarkPages() {
        let document = ExtractedDocument(blocks: [
            .heading(1, "Page 1"),
            .paragraph("   "),
            .paragraph("Hello"),
            .table([["A", "B"], ["", ""], ["1", "2"]]),
        ])
        let blocks = ReaderContent.blocks(from: document)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].pageNumber, 1)
        XCTAssertEqual(blocks.map(\.id), [0, 1, 2])
        XCTAssertEqual(blocks[2].rows, [["A", "B"], ["1", "2"]])
    }

    func testMemoryKeepsPositionAndBookmarksPerFile() {
        let defaults = UserDefaults(suiteName: "reader-tests")!
        defaults.removePersistentDomain(forName: "reader-tests")
        let memory = ReaderMemory(fileName: "a.docx", defaults: defaults)
        memory.position = 7
        XCTAssertTrue(memory.toggleBookmark(3))
        XCTAssertTrue(memory.toggleBookmark(1))
        XCTAssertEqual(memory.bookmarks, [1, 3])
        XCTAssertFalse(memory.toggleBookmark(3))
        XCTAssertEqual(ReaderMemory(fileName: "a.docx", defaults: defaults).position, 7)
        XCTAssertEqual(ReaderMemory(fileName: "b.docx", defaults: defaults).position, 0)
        memory.forget()
        XCTAssertEqual(memory.bookmarks, [])
    }
}

final class SensitiveMaskTests: XCTestCase {
    func testLongNumbersAreHiddenKeepingTheLastFour() {
        XCTAssertEqual(SensitiveMask.mask("الهوية 1098765432", isArabic: true), "الهوية (رقم مخفي ينتهي بـ 5432)")
        XCTAssertEqual(SensitiveMask.mask("Card 4111 1111 1111 1234", isArabic: false), "Card (hidden number ending 1234)")
        XCTAssertEqual(SensitiveMask.mask("IBAN SA0380000000608010167519", isArabic: false), "IBAN SA(hidden number ending 7519)")
    }

    func testDatesAmountsAndShortNumbersStay() {
        let text = "الموعد 2026-10-15 والمبلغ 1,500,000 ريال والغرفة 12"
        XCTAssertEqual(SensitiveMask.mask(text, isArabic: true), text)
    }
}
