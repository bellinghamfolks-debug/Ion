import XCTest
@testable import BasirConvert

final class RestyleTests: XCTestCase {
    /// Made by the server's own engine (tests/test_restyle.py), so the app reads exactly what it sends.
    private let serverJSON = #"""
{"title":"الرواية","language":"ar","strength":"full","profile":{"language":"ar","genre":"رواية","narration":"راوٍ عليم، ماضٍ","voice":"جمل قصيرة","dialogue":"فصحى بين «»","names":["سالم","نورة"],"ai_marks":["؛ كثيرة"],"keep":[]},"blocks":[{"id":"P1","kind":"heading","level":1,"text":"الفصل الأول","original":""},{"id":"P2","kind":"paragraph","level":0,"text":"وقف سالم عند باب البيت، كان الليل ثقيلًا، كأن الزمن توقف. فتح الباب.","original":"وقف سالم عند باب البيت؛ كان الليل ثقيلًا — كأن الزمن توقف. في نهاية المطاف، فتح الباب."},{"id":"P3","kind":"paragraph","level":0,"text":"قالت نورة: «تأخرت يا سالم، الساعة 11».","original":""},{"id":"P4","kind":"paragraph","level":0,"text":"***","original":""},{"id":"P5","kind":"break","level":0,"text":"","original":""},{"id":"P6","kind":"heading","level":1,"text":"الفصل الثاني","original":""},{"id":"P7","kind":"paragraph","level":0,"text":"في صباح اليوم التالي، خرج سالم إلى السوق، اشترى خبزًا وتمرًا، ثم عاد بسرعة.","original":"في صباح اليوم التالي، خرج سالم إلى السوق؛ اشترى خبزًا وتمرًا — ثم عاد بسرعة."}],"report":{"paragraphs_total":3,"paragraphs_changed":2,"parts_total":1,"parts_kept_original":[],"before":{"words":37,"semicolons":2,"dashes":2,"colons":1,"exclamations":0,"stock_phrases":1,"semicolons_per_1000":54.05,"dashes_per_1000":54.05,"average_sentence_words":9.2,"sentence_length_spread":0.38},"after":{"words":34,"semicolons":0,"dashes":0,"colons":1,"exclamations":0,"stock_phrases":0,"semicolons_per_1000":0.0,"dashes_per_1000":0.0,"average_sentence_words":8.5,"sentence_length_spread":0.53},"names_checked":2,"notes":[]}}
"""#

    /// Made by the new engine (measured, planned, chosen, checked), from the same tests.
    private let humanJSON = #"""
{"title":"الرواية","language":"ar","strength":"full","profile":{"language":"ar","kind":"literary","genre":"رواية","synopsis":"سالم يعود","narration":"راوٍ عليم، ماضٍ","language_register":"","conventions":"","voice":"جمل قصيرة","dialogue":"فصحى بين «»","characters":[{"name":"نورة","speech":"قصيرة","phrases":["يا سالم"]}],"names":["سالم","نورة"],"verbatim":[],"ai_marks":["؛ كثيرة"],"keep":[]},"blocks":[{"id":"P1","kind":"paragraph","level":0,"text":"يهدف هذا البحث إلى تسليط الضوء على أهمية تعزيز الوعي البيئي في المجتمعات المحلية. كما يناقش البحث الدور المحوري للمؤسسات التعليمية في تحقيق التنمية المستدامة. ويستعرض البحث منهجية متكاملة لتعزيز المشاركة المجتمعية. ويتم تحليل البيانات بشكل دقيق. ويسلط البحث الضوء على التحديات الرئيسية. وتجدر الإشارة إلى أن النتائج تعكس أهمية التعاون بين القطاعات المختلفة، مما يعزز فرص النجاح. كما تؤكد الدراسة على ضرورة تعزيز الوعي بأهمية الاستدامة. وفي الختام، يقدم البحث توصيات عملية لتعزيز الجهود المبذولة في هذا المجال، مما يسهم في تحقيق الأهداف المنشودة.","original":"","edits":[],"restored":"","plan":"rewrite"},{"id":"P2","kind":"heading","level":1,"text":"الفصل الأول","original":"","edits":[],"restored":"","plan":""},{"id":"P3","kind":"paragraph","level":0,"text":"وقف سالم عند باب البيت، وكان الليل ثقيلًا، كأن الزمن توقف. فتح الباب.","original":"وقف سالم عند باب البيت؛ كان الليل ثقيلًا — كأن الزمن توقف. في نهاية المطاف، فتح الباب.","edits":[{"category":"cliche","before":"في نهاية المطاف،","after":"","reason":"عبارة مستهلكة"}],"restored":"","plan":"rewrite"},{"id":"P4","kind":"paragraph","level":0,"text":"قالت نورة: «تأخرت يا سالم، الساعة 11».","original":"","edits":[],"restored":"","plan":"keep"},{"id":"P5","kind":"paragraph","level":0,"text":"***","original":"","edits":[],"restored":"","plan":""},{"id":"P6","kind":"break","level":0,"text":"","original":"","edits":[],"restored":"","plan":""},{"id":"P7","kind":"heading","level":1,"text":"الفصل الثاني","original":"","edits":[],"restored":"","plan":""},{"id":"P8","kind":"paragraph","level":0,"text":"في صباح اليوم التالي، خرج سالم إلى السوق؛ اشترى خبزًا وتمرًا، ثم عاد بسرعة.","original":"في صباح اليوم التالي، خرج سالم إلى السوق؛ اشترى خبزًا وتمرًا — ثم عاد بسرعة.","edits":[],"restored":"","plan":"edit"}],"report":{"mode":"humanize","paragraphs_total":4,"paragraphs_changed":2,"parts_total":1,"parts_kept_original":[],"before":{"words":122,"semicolons":2,"semicolons_misplaced":2,"semicolons_missing":0,"dashes":2,"colons":1,"exclamations":0,"stock_phrases":2,"translated_constructions":1,"participle_tails":2,"semicolons_per_1000":16.39,"dashes_per_1000":16.39,"average_sentence_words":10.2,"sentence_length_spread":0.41},"after":{"words":119,"semicolons":1,"semicolons_misplaced":1,"semicolons_missing":0,"dashes":0,"colons":1,"exclamations":0,"stock_phrases":1,"translated_constructions":1,"participle_tails":2,"semicolons_per_1000":8.4,"dashes_per_1000":0.0,"average_sentence_words":9.9,"sentence_length_spread":0.46},"names_checked":2,"paragraphs_reviewed":0,"words_changed_percent":5.7,"sentences_restored":0,"meaning_checked":2,"meaning_failed":0,"edit_categories":{"cliche":1},"distance":{"available":false,"reason":"no_sample","held_out_words":0,"reliable":false,"delta_before":0.0,"delta_after":0.0,"delta_author":0.0,"ngrams_before":0.0,"ngrams_after":0.0,"ngrams_author":0.0},"author":null,"counters":[],"sample_source":"none","sample_words_shown":0,"draft_paragraphs":0,"edited_with":"unknown","review_rounds":0,"machine":{"available":true,"domain":"literary","windows":1,"judge_flagged_before":1,"judge_flagged_after":1,"ranker_flagged_before":1,"ranker_flagged_after":1,"full_flagged_before":1,"full_flagged_after":1,"judge_mean_before":1.0,"judge_mean_after":1.0,"in_range_before":0.778,"in_range_after":0.833,"judge_false_positive_rate":0.0767,"judge_true_positive_rate":0.463,"judge_literary_false_positive_rate":0.0767,"uniform_signals":[]},"windows":[{"paragraphs":["P1","P3","P4","P8"],"before":1.0,"after":1.0,"flagged_before":true,"flagged_after":true,"in_range_before":28,"in_range_after":30,"signals":36,"reasons":["machine vocabulary","participle tails","word commonness","machine vocabulary"]}],"paragraphs_kept":1,"paragraphs_rewritten":2,"candidates":3,"repairs":1,"voices_before":null,"voices_after":null,"notes":[]}}
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
                                         "style_sample", "sample_source", "author_draft", "author_draft_base64",
                                         "author_draft_name", "mode", "domain", "strength", "notes"])
        XCTAssertEqual(object["mode"] as? String, "humanize")
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
        XCTAssertTrue(JobNotifier.ready(task: .restyle, title: "t", arabic: true).body.contains("بأسلوب بشري"))
        XCTAssertTrue(JobNotifier.working(task: .restyle, title: "t", percent: 30, uploading: false, arabic: true)
            .body.contains("تحرير الأسلوب"))
    }

    func testATextSavedBeforeTheNewReportStillOpens() throws {
        let result = try RestyleResult.decode(Data(serverJSON.utf8))
        XCTAssertNil(result.report.machine)
        XCTAssertNil(result.blocks[1].edits)
    }

    @MainActor
    func testTheNewReportDecodesWithEveryMeasure() throws {
        let result = try RestyleResult.decode(Data(humanJSON.utf8))
        let machine = try XCTUnwrap(result.report.machine)
        XCTAssertTrue(machine.available)
        XCTAssertGreaterThan(machine.windows, 0)
        XCTAssertGreaterThan(machine.judgeFalsePositiveRate, 0)
        XCTAssertEqual(result.report.mode, "humanize")
        XCTAssertNotNil(result.report.windows)
        XCTAssertTrue(result.blocks.contains { $0.plan == "rewrite" })
        XCTAssertTrue(result.blocks.contains { !($0.edits ?? []).isEmpty })
        XCTAssertEqual(try RestyleResult.decode(result.encoded()), result)
        let categories = try XCTUnwrap(result.report.editCategories)
        XCTAssertTrue(categories.keys.allSatisfy { RestyleResultView.category($0, l10n: L10n()) != $0 },
                      "every kind of edit has a name")
    }

    func testRefusedParagraphsComeBackAsTheyWere() throws {
        let result = try RestyleResult.decode(Data(serverJSON.utf8))
        let kept = result.applying(refused: ["P2"])
        XCTAssertEqual(kept.blocks[1].text, result.blocks[1].original)
        XCTAssertFalse(kept.blocks[1].changed)
        XCTAssertEqual(kept.blocks[6].text, result.blocks[6].text)
    }

    func testTheBlindTestHidesTheOrderAndStatesItsUncertainty() throws {
        let result = try RestyleResult.decode(Data(serverJSON.utf8))
        var generator = SystemRandomNumberGenerator()
        var test = BlindTest.make(from: result, using: &generator)
        XCTAssertFalse(test.trials.isEmpty)
        XCTAssertNil(test.share)
        for index in test.trials.indices { test.trials[index].choseEdited = true }
        let share = try XCTUnwrap(test.share)
        XCTAssertEqual(share.value, 1)
        XCTAssertLessThan(share.low, 1, "a handful of answers is never certainty")
    }
}
