import XCTest
@testable import EnglishNova

final class ArabicInterfaceCopyTests: XCTestCase {
    func testHighVisibilityCopyIsNaturalArabic() {
        XCTAssertEqual(ArabicInterfaceCopy.polish("خطتك الذكية"), "خطة اليوم")
        XCTAssertEqual(ArabicInterfaceCopy.polish("مختبرات"), "مهارات متقدمة")
        XCTAssertEqual(ArabicInterfaceCopy.polish("لنصححها معًا"), "راجع الإجابة")
        XCTAssertEqual(ArabicInterfaceCopy.polish("جاري تجهيز رحلتك التعليمية"), "جارٍ تجهيز خطتك التعليمية")
    }

    func testPolisherDoesNotRewriteUnrelatedText() {
        XCTAssertEqual(ArabicInterfaceCopy.polish("المراجعة"), "المراجعة")
        XCTAssertEqual(ArabicInterfaceCopy.polish("IELTS"), "IELTS")
    }
}
