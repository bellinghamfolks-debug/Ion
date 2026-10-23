import XCTest
@testable import BasirConvert

final class RestyleTests: XCTestCase {
    /// Made by the server's own engine (tests/test_restyle.py), so the app reads exactly what it sends.
    private let serverJSON = #"""
{"title":"الرواية","language":"ar","strength":"full","profile":{"language":"ar","genre":"رواية","narration":"راوٍ عليم، ماضٍ","voice":"جمل قصيرة","dialogue":"فصحى بين «»","names":["سالم","نورة"],"ai_marks":["؛ كثيرة"],"keep":[]},"blocks":[{"id":"P1","kind":"heading","level":1,"text":"الفصل الأول","original":""},{"id":"P2","kind":"paragraph","level":0,"text":"وقف سالم عند باب البيت، كان الليل ثقيلًا، كأن الزمن توقف. فتح الباب.","original":"وقف سالم عند باب البيت؛ كان الليل ثقيلًا — كأن الزمن توقف. في نهاية المطاف، فتح الباب."},{"id":"P3","kind":"paragraph","level":0,"text":"قالت نورة: «تأخرت يا سالم، الساعة 11».","original":""},{"id":"P4","kind":"paragraph","level":0,"text":"***","original":""},{"id":"P5","kind":"break","level":0,"text":"","original":""},{"id":"P6","kind":"heading","level":1,"text":"الفصل الثاني","original":""},{"id":"P7","kind":"paragraph","level":0,"text":"في صباح اليوم التالي، خرج سالم إلى السوق، اشترى خبزًا وتمرًا، ثم عاد بسرعة.","original":"في صباح اليوم التالي، خرج سالم إلى السوق؛ اشترى خبزًا وتمرًا — ثم عاد بسرعة."}],"report":{"paragraphs_total":3,"paragraphs_changed":2,"parts_total":1,"parts_kept_original":[],"before":{"words":37,"semicolons":2,"dashes":2,"colons":1,"exclamations":0,"stock_phrases":1,"semicolons_per_1000":54.05,"dashes_per_1000":54.05,"average_sentence_words":9.2,"sentence_length_spread":0.38},"after":{"words":34,"semicolons":0,"dashes":0,"colons":1,"exclamations":0,"stock_phrases":0,"semicolons_per_1000":0.0,"dashes_per_1000":0.0,"average_sentence_words":8.5,"sentence_length_spread":0.53},"names_checked":2,"notes":[]}}
"""#

    func testTheServerResultDecodesAndKeepsItsStructure() throws {
        let result = try RestyleResult.decode(Data(serverJSON.utf8))
        XCTAssertEqual(result.title, "الرواية")
        XCTAssertEqual(result.blocks.map(\.kind), ["heading", "paragraph", "paragraph", "paragraph", "break", "heading", "paragraph"])
        XCTAssertEqual(result.blocks.filter(\.changed).count, 2)
        XCTAssertEqual(result.profile.names, ["سالم", "نورة"])
        XCTAssertEqual(result.report.paragraphsTotal, 3)
        XCTAssertLessThan(result.report.after.semicolons, result.report.before.semicolons)
        XCTAssertFalse(result.isPartial)
        // Kept on the phone and read back the same.
        XCTAssertEqual(try RestyleResult.decode(result.encoded()), result)
    }

    func testTheReaderGetsTheTextWithItsChapters() throws {
        let result = try RestyleResult.decode(Data(serverJSON.utf8))
        let blocks = result.readerBlocks()
        XCTAssertEqual(blocks.first?.text, "الرواية")
        XCTAssertEqual(blocks.filter(\.isHeading).map(\.text), ["الرواية", "الفصل الأول", "الفصل الثاني"])
        XCTAssertFalse(result.plainText.contains("في نهاية المطاف"))
    }

    func testTheRequestUsesTheServerNamesAndTheSameRequestKeepsItsKey() throws {
        var body = RestyleRequestBody(title: "رواية")
        body.documentBase64 = "UEs="
        body.documentName = "رواية.docx"
        body.styleSample = "فصل من كتابتي"
        let data = try body.encoded()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["title", "language", "text", "document_base64", "document_name",
                                         "style_sample", "strength", "notes"])
        XCTAssertEqual(RestyleRequestBody.requestKey(data), RestyleRequestBody.requestKey(try body.encoded()))
        XCTAssertTrue(RestyleRequestBody.requestKey(data).hasPrefix("restyle-"))
        XCTAssertNotNil(UUID(uuidString: RestyleRequestBody.notificationID(data)))
    }

    @MainActor
    func testProgressNamesTheStage() {
        let l10n = L10n()
        let reading = RestyleRunner.stage(SummaryJobProgress(status: "processing", current: 0, total: 9, error: nil),
                                          percent: 0, l10n: l10n)
        XCTAssertTrue(reading.contains("كاملًا") || reading.contains("whole"))
        let review = RestyleRunner.stage(SummaryJobProgress(status: "processing", current: 7, total: 9, error: nil),
                                         percent: 77, l10n: l10n)
        XCTAssertTrue(review.contains("77"))
    }

    func testWordsAreCountedForTheScreen() {
        XCTAssertEqual(RestyleView.words(in: "وقف سالم\nعند   الباب"), 4)
    }

    func testNotificationsNameTheTask() {
        XCTAssertTrue(JobNotifier.ready(task: .restyle, title: "t", arabic: true).body.contains("بأسلوب طبيعي"))
        XCTAssertTrue(JobNotifier.working(task: .restyle, title: "t", percent: 30, uploading: false, arabic: true)
            .body.contains("تحرير الأسلوب"))
    }
}
