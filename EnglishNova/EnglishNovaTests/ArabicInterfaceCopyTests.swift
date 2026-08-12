import XCTest
@testable import EnglishNova

final class ArabicInterfaceCopyTests: XCTestCase {
    func testHighVisibilityCopyIsNaturalArabic() {
        XCTAssertEqual(ArabicInterfaceCopy.polish("خطتك الذكية"), "خطة اليوم")
        XCTAssertEqual(ArabicInterfaceCopy.polish("مختبرات"), "تدريب المهارات")
        XCTAssertEqual(ArabicInterfaceCopy.polish("لنصححها معًا"), "راجع الإجابة")
        XCTAssertEqual(ArabicInterfaceCopy.polish("جاري تجهيز رحلتك التعليمية"), "جارٍ تجهيز رحلتك التعليمية")
    }

    func testPolisherDoesNotRewriteUnrelatedText() {
        XCTAssertEqual(ArabicInterfaceCopy.polish("المراجعة"), "المراجعة")
        XCTAssertEqual(ArabicInterfaceCopy.polish("IELTS"), "IELTS")
    }

    func testEnglishModeNeverSilentlyReturnsUnknownArabicUI() {
        let previous = Localizer.shared.isEnglish
        defer { Localizer.shared.isEnglish = previous }
        Localizer.shared.isEnglish = true
        let output = L("نص عربي تجريبي غير موجود في قاموس الترجمة ٩٩٩")
        XCTAssertFalse(output.contains("عربي"))
        XCTAssertEqual(output, "Translation unavailable")
    }

    func testExplicitBilingualDynamicCopy() {
        let previous = Localizer.shared.isEnglish
        defer { Localizer.shared.isEnglish = previous }
        Localizer.shared.isEnglish = true
        XCTAssertEqual(LE("خطة اليوم", "Today's plan"), "Today's plan")
        XCTAssertEqual(LfE("راجع %@ بطاقة", "Review %@ cards", "12"), "Review 12 cards")
    }
}
