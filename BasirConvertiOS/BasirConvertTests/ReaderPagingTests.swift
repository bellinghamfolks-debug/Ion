import XCTest
@testable import BasirConvert

final class ReaderPagingTests: XCTestCase {
    private func paragraph(_ id: Int, _ text: String = String(repeating: "كلمة ", count: 20)) -> ReaderBlock {
        ReaderBlock(id: id, kind: .paragraph, text: text)
    }

    func testPagesFollowTheDocumentsOwnMarkers() {
        var blocks = [paragraph(0)]
        blocks.append(ReaderBlock(id: 1, kind: .heading(2), text: "الصفحة 1", pageNumber: 1))
        blocks.append(paragraph(2))
        blocks.append(ReaderBlock(id: 3, kind: .heading(2), text: "الصفحة 2", pageNumber: 2))
        blocks.append(paragraph(4))
        blocks.append(paragraph(5))
        let pages = ReaderPaging.pages(for: blocks)
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].range, 0..<3)
        XCTAssertEqual(pages[0].printedNumber, 1)
        XCTAssertEqual(pages[1].range, 3..<6)
        XCTAssertEqual(pages[1].printedNumber, 2)
        XCTAssertEqual(ReaderPaging.pageIndex(of: 5, in: pages), 1)
    }

    func testDocumentsWithoutMarkersAreCutIntoScreens() {
        let long = String(repeating: "a", count: 900)
        let blocks = (0..<10).map { paragraph($0, long) }
        let pages = ReaderPaging.pages(for: blocks)
        XCTAssertGreaterThan(pages.count, 2)
        // Every block is on exactly one page, in order.
        XCTAssertEqual(pages.flatMap { Array($0.range) }, Array(0..<10))
        XCTAssertNil(pages[0].printedNumber)
    }

    func testEmptyDocumentHasNoPages() {
        XCTAssertTrue(ReaderPaging.pages(for: []).isEmpty)
    }

    func testLongPassagesAreSpokenInSentences() {
        let sentence = "هذه جملة عربية طويلة بعض الشيء لتجربة التقسيم إلى أجزاء صغيرة. "
        let chunks = SpeechChunker.chunks(String(repeating: sentence, count: 20))
        XCTAssertGreaterThan(chunks.count, 3)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= SpeechChunker.maximumLength })
        XCTAssertEqual(SpeechChunker.chunks("قصير"), ["قصير"])
        XCTAssertEqual(SpeechChunker.chunks("   "), [])
        let noPunctuation = String(repeating: "word ", count: 200)
        XCTAssertTrue(SpeechChunker.chunks(noPunctuation).allSatisfy { $0.count <= SpeechChunker.maximumLength })
    }
}

final class ArabicInstantReadTests: XCTestCase {
    func testBackwardsArabicTextLayerIsRejected() {
        let forward = "ذهب الطالب إلى المدرسة في الصباح الباكر وكان الجو جميلا على الطريق مع الأصدقاء من الحي"
        let backward = forward.split(separator: " ").map { String($0.reversed()) }.joined(separator: " ")
        XCTAssertNotNil(TextLayerCheck.usableText(forward))
        XCTAssertNil(TextLayerCheck.usableText(backward))
    }

    func testPresentationFormsAreNormalised() {
        // "مرحبا بكم في التطبيق" written with presentation forms, repeated past the minimum length.
        let shaped = String(repeating: "ﻣﺮﺣﺒﺎ ﺑﻜﻢ ﻓﻲ ﺍﻟﺘﻄﺒﻴﻖ ", count: 3)
        let usable = TextLayerCheck.usableText(shaped)
        XCTAssertNotNil(usable)
        XCTAssertTrue(usable?.contains("مرحبا") == true)
    }

    func testEnglishTextLayerIsKept() {
        let text = "The quick brown fox jumps over the lazy dog, again and again, page after page."
        XCTAssertEqual(TextLayerCheck.usableText(text), text)
    }

    func testPiecesOfOneArabicRowAreReadRightToLeft() {
        let right = InstantReader.Line(text: "السلام", box: CGRect(x: 0.6, y: 0.8, width: 0.3, height: 0.03))
        let left = InstantReader.Line(text: "عليكم", box: CGRect(x: 0.2, y: 0.8, width: 0.3, height: 0.03))
        XCTAssertEqual(InstantReader.group([left, right]), ["السلام عليكم"])
    }

    func testPiecesOfOneEnglishRowAreReadLeftToRight() {
        let left = InstantReader.Line(text: "Hello", box: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.03))
        let right = InstantReader.Line(text: "world", box: CGRect(x: 0.5, y: 0.8, width: 0.3, height: 0.03))
        XCTAssertEqual(InstantReader.group([right, left]), ["Hello world"])
    }

    func testArabicShare() {
        XCTAssertEqual(ScriptMix.arabicShare("مرحبا"), 1)
        XCTAssertEqual(ScriptMix.arabicShare("hello"), 0)
    }
}
