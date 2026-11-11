import XCTest
import PDFKit
import UIKit
@testable import BasirConvert

final class DocumentTrustTests: XCTestCase {
    func testObjectDirectionsRejectUnknownAndInvalidResponses() {
        XCTAssertNil(ObjectLocation.parse("not JSON"))
        XCTAssertNil(ObjectLocation.parse(#"{"found":true,"horizontal":"unknown","vertical":"upper","landmark":""}"#))
        let absent = ObjectLocation.parse(#"{"found":false,"horizontal":"unknown","vertical":"unknown","landmark":""}"#)
        XCTAssertEqual(absent?.pulseCount, 0)
        let located = ObjectLocation.parse(#"{"found":true,"horizontal":"right","vertical":"upper","landmark":"table"}"#)
        XCTAssertEqual(located?.pulseCount, 3)
    }
    func testPronunciationOnlyReplacesCompleteTerms() {
        XCTAssertEqual(SpeechPronunciation.apply("STC and STCloud", rules: "STC=ess tee see"), "ess tee see and STCloud")
        XCTAssertEqual(SpeechPronunciation.apply("العقد", rules: "=invalid"), "العقد")
    }
    func testNumberAuditNormalizesArabicAndPersianDigits() {
        XCTAssertEqual(DocumentConsistencyAudit.numbers("١٢٣ و ۱۲۳"), ["123"])
        XCTAssertEqual(DocumentConsistencyAudit.numbers("2026-11-11"), ["2026-11-11"])
    }
    func testPrivateCopyFlattensOriginalTextWithoutLosingPages() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("privacy-test-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: source) }
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)).writePDF(to: source) { context in
            context.beginPage()
            ("secret@example.com" as NSString).draw(at: CGPoint(x: 30, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
            context.beginPage()
            ("Second page" as NSString).draw(at: CGPoint(x: 30, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
        }
        let finding = PrivateDocumentRedactor.Finding(id: UUID(), page: 1, text: "secret@example.com", region: CGRect(x: 0, y: 0, width: 1, height: 1))
        let output = try PrivateDocumentRedactor.export(source, findings: [finding])
        defer { try? FileManager.default.removeItem(at: output) }
        let pdf = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(pdf.pageCount, 2)
        XCTAssertFalse((pdf.string ?? "").contains("secret@example.com"))
    }
    func testSensitiveDataDetectionAndExplicitPhrases() {
        XCTAssertTrue(PrivateDocumentRedactor.isSensitive("Contact person@example.com", phrases: []))
        XCTAssertTrue(PrivateDocumentRedactor.isSensitive("هوية ١٠١٢٣٤٥٦٧٨", phrases: []))
        XCTAssertTrue(PrivateDocumentRedactor.isSensitive("Customer Abdullah", phrases: ["Abdullah"]))
        XCTAssertFalse(PrivateDocumentRedactor.isSensitive("Chapter 2: introduction", phrases: [""]))
    }
    func testNonFiniteQualityScoresNeverTrapOrOverstate() {
        var report = fixture()
        report.score = .infinity
        XCTAssertNil(report.percentScore)
        report.score = .nan
        XCTAssertNil(report.percentScore)
        report.score = 125
        XCTAssertEqual(report.percentScore, 100)
        report.score = 0.82
        XCTAssertEqual(report.percentScore, 82)
    }
    func testOldQualityRecordsRemainDecodableWithoutPageEvidence() throws {
        let encoded = try JSONEncoder().encode(fixture())
        let decoded = try JSONDecoder().decode(QualityReport.self, from: encoded)
        XCTAssertNil(decoded.fallbackPageNumbers)
        XCTAssertNil(decoded.pageAccountingVerified)
        XCTAssertTrue(decoded.hasConcerns)
    }
    private func fixture() -> QualityReport {
        QualityReport(score: nil, warnings: [], sourcePages: 2, retainedPages: 2,
                      skippedBlankPages: 0, fallbackPages: 1, tables: 0, images: 1,
                      imagesMissingDescription: 0, textCharacters: 120, wordPackageVerified: true)
    }
}
