import XCTest
@testable import Basir

final class DocumentContextSelectorTests: XCTestCase {
    func testQuestionCanRetrieveContentNearEndOfLongDocument() {
        let filler = (1...40).map { "قسم \($0): نص عام لا يحتوي المعلومة المطلوبة." }.joined(separator: "\n\n")
        let document = filler + "\n\nصفحة 41\nتاريخ انتهاء العقد هو 30 يونيو 2028، والمرجع AX19-B7."
        let result = DocumentContextSelector.select(
            document: document,
            question: "ما تاريخ انتهاء العقد للمرجع AX19-B7؟",
            maxCharacters: 6_000,
            targetChunkCharacters: 180
        )
        XCTAssertTrue(result.context.contains("30 يونيو 2028"))
        XCTAssertTrue(result.context.contains("AX19-B7"))
    }

    func testSelectedContextStaysWithinBudget() {
        let document = String(repeating: "فقرة طويلة عن العقد والالتزامات.\n", count: 2_000)
        let result = DocumentContextSelector.select(
            document: document,
            question: "ما الالتزامات؟",
            maxCharacters: 5_000,
            targetChunkCharacters: 500
        )
        XCTAssertLessThanOrEqual(result.context.count, 5_000)
        XCTAssertGreaterThan(result.selectedChunks, 0)
    }

    func testNoKeywordMatchSamplesAcrossDocument() {
        let document = (1...20).map { "المقطع \($0): محتوى مستقل." }.joined(separator: "\n\n")
        let result = DocumentContextSelector.select(
            document: document,
            question: "سؤال غير مرتبط تمامًا",
            maxCharacters: 4_000,
            targetChunkCharacters: 80
        )
        XCTAssertTrue(result.context.contains("المقطع 1"))
        XCTAssertTrue(result.context.contains("المقطع 20"))
    }
}
