import XCTest
@testable import EnglishNova

final class AdvancedSkillsLibraryTests: XCTestCase {
    func testAdvancedLibrariesHaveExpectedCoverage() {
        XCTAssertEqual(AdvancedSkillsLibrary.readingPassages.count, 24)
        XCTAssertEqual(AdvancedSkillsLibrary.listeningPassages.count, 24)
        XCTAssertEqual(AdvancedSkillsLibrary.writingPrompts.count, 24)
        XCTAssertEqual(Set(AdvancedSkillsLibrary.readingPassages.map(\.id)).count, 24)
        XCTAssertEqual(Set(AdvancedSkillsLibrary.listeningPassages.map(\.id)).count, 24)
        XCTAssertEqual(Set(AdvancedSkillsLibrary.writingPrompts.map(\.id)).count, 24)
        for level in CEFRLevel.allCases {
            XCTAssertFalse(AdvancedSkillsLibrary.readings(for: level).isEmpty)
            XCTAssertFalse(AdvancedSkillsLibrary.listenings(for: level).isEmpty)
            XCTAssertFalse(AdvancedSkillsLibrary.writings(for: level).isEmpty)
        }
    }

    func testWritingEvaluatorProducesBoundedScoresAndAdvice() {
        let prompt = AdvancedSkillsLibrary.writingPrompts.first!
        let evaluation = WritingEvaluator.evaluate(
            text: "First, I arrived safely. However, I will call later because the meeting is still running.",
            prompt: prompt
        )
        XCTAssertTrue((0...1).contains(evaluation.overall))
        XCTAssertGreaterThan(evaluation.wordCount, 5)
        XCTAssertFalse(evaluation.strengthsAr.isEmpty)
        XCTAssertFalse(evaluation.improvementsAr.isEmpty)
    }
}
