import XCTest

@testable import EnglishNova

final class AdaptivePlacementEngineTests: XCTestCase {
    func testCorrectAnswerRaisesAbility() {
        var engine = AdaptivePlacementEngine(questions: PlacementQuestionBank.all, startingLevel: .a1)
        let question = PlacementQuestionBank.all.first { $0.level == .b1 }!
        let before = engine.ability
        engine.submit(question: question, selectedAnswer: question.answer)
        XCTAssertGreaterThan(engine.ability, before)
    }

    func testIncorrectAnswerLowersAbility() {
        var engine = AdaptivePlacementEngine(questions: PlacementQuestionBank.all, startingLevel: .b2)
        let question = PlacementQuestionBank.all.first { $0.level == .a2 }!
        let before = engine.ability
        engine.submit(question: question, selectedAnswer: "إجابة غير صحيحة")
        XCTAssertLessThan(engine.ability, before)
    }

    func testResultAlwaysContainsAllSkillRows() {
        var engine = AdaptivePlacementEngine(questions: PlacementQuestionBank.all)
        for question in PlacementQuestionBank.all.prefix(12) {
            engine.submit(question: question, selectedAnswer: question.answer)
        }
        let result = engine.result()
        XCTAssertEqual(result.skills.count, LanguageSkill.allCases.count)
        XCTAssertGreaterThan(result.confidence, 0.4)
    }
}
