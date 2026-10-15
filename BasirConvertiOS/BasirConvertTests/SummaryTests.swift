import XCTest
@testable import BasirConvert

/// The summary system on the phone: the server's answer is read exactly,
/// summaries are kept and found again, and every point names its place.
final class SummaryTests: XCTestCase {
    private let serverJSON = """
    {"language":"ar","template":"contract","document_type":"عقد إيجار",
     "one_line":{"text":"عقد لمدة سنتين","flagged_numbers":[]},
     "short":{"text":"الإيجار 36000 ريال","flagged_numbers":["450"]},
     "easy_read":{"text":"هذا عقد","flagged_numbers":[]},
     "key_points":[{"text":"الإيجار السنوي 36,000 ريال","kind":"amount","locations":[{"file":0,"page":1}],
                    "quote":"إيجار سنوي قدره 36,000 ريال","verified":true,"flagged_numbers":[],"owner":"","deadline":""},
                   {"text":"نقطة غير مؤكدة","kind":"idea","locations":[],"quote":"","verified":false,
                    "flagged_numbers":["999"],"owner":"","deadline":""}],
     "groups":[{"heading":"الالتزامات","points":[]}],
     "sections":[{"title":"المقدمة","file":0,"first_page":1,"last_page":2,"summary":"عن العقد","flagged_numbers":[],"points":[]}],
     "cards":[],"quiz":[{"question":"كم المدة؟","choices":["سنة","سنتان"],"answer_index":1,"explanation":"","locations":[]}],
     "notice":"للفهم فقط","files":[{"name":"عقد","page_kind":"page","pages":3}],
     "verification":{"points_total":6,"points_verified":5,"numbers_flagged":2,"pages_total":3,"pages_covered":3}}
    """

    func testTheServersSummaryIsReadExactly() throws {
        let summary = try DocumentSummary.decode(Data(serverJSON.utf8))
        XCTAssertEqual(summary.template, "contract")
        XCTAssertEqual(summary.short.flaggedNumbers, ["450"])
        XCTAssertEqual(summary.keyPoints.first?.locations, [DocumentSummary.Location(file: 0, page: 1)])
        XCTAssertFalse(summary.keyPoints[1].verified)
        XCTAssertEqual(summary.sections.first?.lastPage, 2)
        XCTAssertEqual(summary.quiz.first?.answerIndex, 1)
        XCTAssertEqual(summary.verification.pointsVerified, 5)
        XCTAssertTrue(summary.usesPages(file: 0))
        // Kept on the phone in the same shape it arrived in.
        XCTAssertEqual(try DocumentSummary.decode(summary.encoded()), summary)
    }

    func testTheRequestUsesTheServersFieldNames() throws {
        let body = SummaryRequestBody(text: "نص", title: "عقد", language: "en", template: "contract",
                                      includeStudy: true, choice: "accurate")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body.encoded()) as? [String: Any])
        XCTAssertEqual(json["include_study"] as? Bool, true)
        XCTAssertEqual(json["choice"] as? String, "accurate")
        XCTAssertEqual(body.variantKey, "en|contract|study")
    }

    func testSummariesAreKeptWithTheirFileAndFoundAgain() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("عقد.docx")
        let summary = try DocumentSummary.decode(Data(serverJSON.utf8))
        XCTAssertFalse(SummaryStore.hasSummary(forOutput: output))
        SummaryStore.save(summary, variant: "ar|auto|plain", forOutput: output)
        XCTAssertTrue(SummaryStore.hasSummary(forOutput: output))
        XCTAssertEqual(SummaryStore.load(variant: "ar|auto|plain", forOutput: output), summary)
        XCTAssertNil(SummaryStore.load(variant: "en|auto|plain", forOutput: output))
        XCTAssertEqual(SummaryStore.latest(forOutput: output)?.documentType, "عقد إيجار")
        XCTAssertTrue(summary.searchableText.contains("36,000"))
    }

    func testAConversionCanAskForASummary() {
        let plain = ConversionOptions(operation: .convert, outputMode: .full, targetLanguage: nil, embedVisuals: true,
                                      includeMath: false, interfaceLanguage: .arabic)
        XCTAssertFalse(plain.encodedMode.contains("|summary"))
        let summarized = ConversionOptions(operation: .convert, outputMode: .full, targetLanguage: nil,
                                           embedVisuals: true, includeMath: false, interfaceLanguage: .arabic,
                                           includeSummary: true)
        XCTAssertTrue(summarized.encodedMode.hasSuffix("|summary"))
    }

    @MainActor
    func testEveryPointSaysWhereItIsAndWhetherItIsConfirmed() throws {
        let l10n = L10n()
        l10n.language = .arabic
        let summary = try DocumentSummary.decode(Data(serverJSON.utf8))
        let confirmed = SummaryExport.describe(summary.keyPoints[0], in: summary, l10n: l10n)
        XCTAssertTrue(confirmed.contains("ص 1"), confirmed)
        XCTAssertFalse(confirmed.contains("غير مؤكد"))
        let unconfirmed = SummaryExport.describe(summary.keyPoints[1], in: summary, l10n: l10n)
        XCTAssertTrue(unconfirmed.contains("غير مؤكد"))
        XCTAssertTrue(unconfirmed.contains("999"))
        let text = SummaryExport.plainText(summary, title: "عقد", l10n: l10n)
        XCTAssertTrue(text.contains("أهم النقاط"))
        XCTAssertTrue(text.contains("تحقق بصير من 5 من 6"))
    }
}
