import XCTest
@testable import EnglishNova

final class LessonAssessmentTests: XCTestCase {
    func testC1RecognitionOnlyCannotPassEvenWithTwoThirdsCorrect() {
        let evidence = [
            LessonExerciseEvidence(type: .multipleChoice, wasCorrect: true, choiceCount: 4),
            LessonExerciseEvidence(type: .multipleChoice, wasCorrect: true, choiceCount: 4),
            LessonExerciseEvidence(type: .multipleChoice, wasCorrect: false, choiceCount: 4),
            LessonExerciseEvidence(type: .listenAndChoose, wasCorrect: true, choiceCount: 4),
            LessonExerciseEvidence(type: .listenAndChoose, wasCorrect: false, choiceCount: 4),
            LessonExerciseEvidence(type: .listenAndChoose, wasCorrect: true, choiceCount: 4)
        ]
        let result = LessonAssessmentEngine.evaluate(level: .c1, evidence: evidence)
        XCTAssertFalse(result.passed)
        XCTAssertLessThan(result.masteryScore, 0.70)
        XCTAssertNil(result.productiveScore)
    }

    func testC1RequiresStrongProductiveEvidence() {
        let evidence = [
            LessonExerciseEvidence(type: .multipleChoice, wasCorrect: true, choiceCount: 4),
            LessonExerciseEvidence(type: .listenAndChoose, wasCorrect: true, choiceCount: 4),
            LessonExerciseEvidence(type: .fillBlank, wasCorrect: true, choiceCount: 0),
            LessonExerciseEvidence(type: .translation, wasCorrect: true, choiceCount: 0),
            LessonExerciseEvidence(type: .speak, wasCorrect: true, choiceCount: 0),
            LessonExerciseEvidence(type: .translation, wasCorrect: true, choiceCount: 0)
        ]
        let result = LessonAssessmentEngine.evaluate(level: .c1, evidence: evidence)
        XCTAssertTrue(result.passed)
        XCTAssertGreaterThanOrEqual(result.masteryScore, result.passThreshold)
        XCTAssertGreaterThanOrEqual(result.productiveScore ?? 0, 0.70)
    }

    func testC1GoodRecognitionButWeakProductionStillFails() {
        let evidence = [
            LessonExerciseEvidence(type: .multipleChoice, wasCorrect: true, choiceCount: 4),
            LessonExerciseEvidence(type: .listenAndChoose, wasCorrect: true, choiceCount: 4),
            LessonExerciseEvidence(type: .fillBlank, wasCorrect: true, choiceCount: 0),
            LessonExerciseEvidence(type: .translation, wasCorrect: false, choiceCount: 0),
            LessonExerciseEvidence(type: .speak, wasCorrect: false, choiceCount: 0),
            LessonExerciseEvidence(type: .translation, wasCorrect: true, choiceCount: 0)
        ]
        let result = LessonAssessmentEngine.evaluate(level: .c1, evidence: evidence)
        XCTAssertFalse(result.passed)
        XCTAssertLessThan(result.productiveScore ?? 1, 0.70)
    }

    func testThresholdRisesWithLevel() {
        XCTAssertLessThan(LessonAssessmentEngine.threshold(for: .a0), LessonAssessmentEngine.threshold(for: .b1))
        XCTAssertLessThan(LessonAssessmentEngine.threshold(for: .b1), LessonAssessmentEngine.threshold(for: .c1))
    }
}
