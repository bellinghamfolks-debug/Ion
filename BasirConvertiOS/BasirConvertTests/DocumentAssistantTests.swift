import XCTest
@testable import BasirConvert

final class DocumentAssistantTests: XCTestCase {
    private let blocks: [ReaderBlock] = [
        ReaderBlock(id: 0, kind: .heading(1), text: "خطاب المدرسة"),
        ReaderBlock(id: 1, kind: .paragraph, text: "رسومُ الرحلة 150 ريالًا تُدفع نقدًا."),
        ReaderBlock(id: 2, kind: .table, text: "", rows: [["الاسم", "الدرجة"], ["أحمد", "90"]]),
    ]

    func testQuoteFindsItsBlockIgnoringHarakatAndSpacing() {
        XCTAssertEqual(DocumentAssistant.blockID(containing: "رسوم الرحلة  150 ريالًا", in: blocks), 1)
        XCTAssertEqual(DocumentAssistant.blockID(containing: "أحمد 90", in: blocks), 2)
        XCTAssertNil(DocumentAssistant.blockID(containing: "نص غير موجود", in: blocks))
    }

    func testDocumentTextKeepsHeadingsAndTableRows() {
        let text = DocumentAssistant.text(of: blocks)
        XCTAssertTrue(text.hasPrefix("# خطاب المدرسة"))
        XCTAssertTrue(text.contains("أحمد | 90"))
    }

    func testEventDatesParseOnTheGregorianCalendar() {
        let timed = DocumentEvent(title: "اجتماع", date: "2026-10-15", time: "17:30", endTime: "",
                                  location: "", notes: "", quote: "")
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute], from: timed.start!)
        XCTAssertEqual([components.year, components.month, components.day, components.hour, components.minute],
                       [2026, 10, 15, 17, 30])
        XCTAssertFalse(timed.isAllDay)
        XCTAssertNil(DocumentEvent(title: "x", date: "15/10/2026", time: "", endTime: "",
                                   location: "", notes: "", quote: "").start)
    }

    func testServerAnswersDecode() throws {
        let json = """
        {"task":"brief","cached":false,"result":{"document_type":"خطاب","summary":"ملخص",
         "requests":[{"action":"إحضار الهوية","deadline":"2026-10-20","details":""}],
         "amounts":[],"contacts":[],"documents_needed":["صورة الهوية"],"warnings":[]}}
        """.data(using: .utf8)!
        struct Envelope: Decodable { let result: DocumentBrief }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let brief = try decoder.decode(Envelope.self, from: json).result
        XCTAssertEqual(brief.documentsNeeded, ["صورة الهوية"])
        XCTAssertEqual(brief.requests.first?.deadline, "2026-10-20")
    }

    func testRequestEncodesSnakeCaseKeys() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let body = AssistRequestBody(task: .compare, language: "ar", text: "b", otherText: "a")
        let object = try JSONSerialization.jsonObject(with: encoder.encode(body)) as! [String: Any]
        XCTAssertEqual(object["task"] as? String, "compare")
        XCTAssertEqual(object["other_text"] as? String, "a")
        XCTAssertNotNil(object["image_base64"])
    }
}

final class TextComparisonTests: XCTestCase {
    func testIdenticalVersionsHaveNoChanges() {
        XCTAssertEqual(TextComparison.compare(old: ["أ", "ب"], new: ["أ", "ب"]), [])
    }

    func testEditedParagraphIsOneChange() {
        let changes = TextComparison.compare(old: ["المقدمة", "المبلغ 150 ريالًا", "الخاتمة"],
                                             new: ["المقدمة", "المبلغ 200 ريال", "الخاتمة"])
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].kind, .changed)
        XCTAssertEqual(changes[0].before, "المبلغ 150 ريالًا")
        XCTAssertEqual(changes[0].after, "المبلغ 200 ريال")
    }

    func testAddedAndRemovedParagraphs() {
        let changes = TextComparison.compare(old: ["أ", "ب", "ج"], new: ["أ", "ج", "د"])
        XCTAssertEqual(changes.map(\.kind), [.removed, .added])
    }

    func testSpacingAloneIsNotAChange() {
        XCTAssertEqual(TextComparison.compare(old: ["نص  مع   مسافات"], new: ["نص مع مسافات"]), [])
    }
}

final class InstantReaderTests: XCTestCase {
    func testLinesWithSmallGapsFormOneParagraph() {
        let lines = [
            InstantReader.Line(text: "السطر الأول", box: CGRect(x: 0.1, y: 0.80, width: 0.8, height: 0.03)),
            InstantReader.Line(text: "السطر الثاني", box: CGRect(x: 0.1, y: 0.76, width: 0.8, height: 0.03)),
            InstantReader.Line(text: "فقرة جديدة", box: CGRect(x: 0.1, y: 0.60, width: 0.8, height: 0.03)),
        ]
        XCTAssertEqual(InstantReader.group(lines.reversed()), ["السطر الأول السطر الثاني", "فقرة جديدة"])
    }
}
