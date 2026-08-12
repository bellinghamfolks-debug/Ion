import XCTest
@testable import EnglishNova

final class ArabicCopyQualityTests: XCTestCase {
    func testLegacyInterfaceLabelsAreNormalized() {
        let expected: [String: String] = [
            "ذكاء الخادم": "أدوات الذكاء الاصطناعي",
            "مختبرات المستوى المتقدم": "تدريب المهارات",
            "استوديو المحادثة": "تدريب المحادثة",
            "مختبر النطق": "تدريب النطق",
            "مختبر الاستماع": "تدريب الاستماع",
            "مصنع الجمل": "بناء الجمل",
            "المراجعة الذكية": "المراجعة",
            "مصحّح الكتابة": "تدريب الكتابة",
            "مولّد التمارين": "تمارين مخصصة",
            "خطتي الذكية": "خطة اليوم"
        ]

        for (legacy, replacement) in expected {
            XCTAssertEqual(ArabicInterfaceCopy.polish(legacy), replacement)
        }
    }

    func testArabicLearningCopyRemovesHighConfidenceMachinePatterns() {
        let samples = [
            "قم باختيار الإجابة الصحيحة من الخيارات التالية",
            "قم بالاستماع إلى الجملة",
            "قم بترجمة العبارة التالية إلى اللغة الإنجليزية",
            "إضغط للمتابعة",
            "جاري تحميل الدرس"
        ]

        for sample in samples {
            let polished = ArabicLearningCopy.polish(sample)
            XCTAssertFalse(polished.contains("قم ب"), polished)
            XCTAssertFalse(polished.contains("إضغط"), polished)
            XCTAssertFalse(polished.contains("جاري "), polished)
        }
    }

}
