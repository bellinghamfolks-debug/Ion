import XCTest
@testable import BasirConvert

final class PageSelectionNormalizerTests: XCTestCase {
    func testArabicAndPersianInputUsesWireFormat() throws {
        let normalized = PageSelectionNormalizer.normalize("١–٣، ۵؛۷")
        XCTAssertEqual(normalized, "1-3, 5,7")
        XCTAssertEqual(try PageSelectionParser.pages(from: normalized, total: 8), [1, 2, 3, 5, 7])
    }

    func testNormalizesEverySupportedDash() {
        for dash in ["‐", "‑", "‒", "–", "—", "−"] {
            XCTAssertEqual(PageSelectionNormalizer.normalize("1\(dash)2"), "1-2")
        }
    }
}

