import XCTest
@testable import EnglishNova

final class AIIntegrationModelsTests: XCTestCase {
    func testWritingResultDecodesRichServerFeedback() throws {
        let data = #"""
{
          "corrected":"I went to work yesterday.",
          "feedbackAr":"راجع زمن الماضي.",
          "score":82,
          "strengthsAr":["المعنى واضح"],
          "improvementsAr":["ثبّت الماضي البسيط"],
          "corrections":[{"original":"I go yesterday","replacement":"I went yesterday","reasonAr":"استخدم الماضي."}],
          "nextTaskEn":"Write one more sentence about yesterday."
        }
"""#.data(using: .utf8)!

        let result = try JSONDecoder().decode(WritingResult.self, from: data)
        XCTAssertEqual(result.score, 82)
        XCTAssertEqual(result.corrections.count, 1)
        XCTAssertEqual(result.strengthsAr, ["المعنى واضح"])
        XCTAssertEqual(result.nextTaskEn, "Write one more sentence about yesterday.")
    }

    func testWritingResultRemainsBackwardCompatible() throws {
        let data = #"{"corrected":"Hello.","feedbackAr":"جيد","score":90}"#.data(using: .utf8)!
        let result = try JSONDecoder().decode(WritingResult.self, from: data)
        XCTAssertTrue(result.corrections.isEmpty)
        XCTAssertTrue(result.strengthsAr.isEmpty)
        XCTAssertTrue(result.improvementsAr.isEmpty)
    }

    func testAdaptiveExerciseMetadataDecodes() throws {
        let data = #"""
{
          "questions":[{"prompt":"Choose.","options":["a","b"],"answerIndex":0,"hintAr":"تلميح"}],
          "focusAr":"الماضي البسيط",
          "reasonAr":"ظهر في أخطائك الأخيرة.",
          "domain":"grammar"
        }
"""#.data(using: .utf8)!

        let result = try JSONDecoder().decode(ExerciseResult.self, from: data)
        XCTAssertEqual(result.questions.count, 1)
        XCTAssertEqual(result.domain, "grammar")
        XCTAssertEqual(result.reasonAr, "ظهر في أخطائك الأخيرة.")
    }

    func testLearningBriefDecodesWithSafeDefaults() throws {
        let data = #"""
{
          "headlineAr":"ركّز اليوم على الاسترجاع",
          "focusAr":"المفردات",
          "whyAr":"هناك كلمات مستحقة.",
          "actionsAr":["راجع خمس كلمات"],
          "challengeEn":"Use one word in a sentence.",
          "domain":"vocabulary"
        }
"""#.data(using: .utf8)!

        let brief = try JSONDecoder().decode(AILearningBrief.self, from: data)
        XCTAssertEqual(brief.domain, "vocabulary")
        XCTAssertEqual(brief.actionsAr.count, 1)
        XCTAssertFalse(brief.challengeEn.isEmpty)
    }
}
