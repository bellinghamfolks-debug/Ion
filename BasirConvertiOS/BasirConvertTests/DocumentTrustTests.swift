import XCTest
@testable import BasirConvert

final class DocumentTrustTests: XCTestCase {
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
