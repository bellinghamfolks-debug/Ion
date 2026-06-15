import XCTest
@testable import EnglishNova

final class AdaptiveMemoryEngineTests: XCTestCase {
    func testGoodReviewIncreasesStabilityAndSchedulesFutureReview() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let word = VocabularyWord(id: "test", english: "evidence", arabic: "دليل", example: "The evidence is clear.", exampleArabic: "الدليل واضح.", partOfSpeech: "noun", phonetic: nil)
        let card = ReviewCard(word: word, lastReviewedAt: now.addingTimeInterval(-86_400), stabilityDays: 1)
        let reviewed = AdaptiveReviewEngine.reviewed(card, grade: .good, now: now)
        XCTAssertGreaterThan(reviewed.stabilityDays, card.stabilityDays)
        XCTAssertGreaterThan(reviewed.dueDate, now)
        XCTAssertEqual(reviewed.repetitions, card.repetitions + 1)
    }

    func testAgainCreatesLapseAndShortInterval() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let word = VocabularyWord(id: "test", english: "policy", arabic: "سياسة", example: "Read the policy.", exampleArabic: "اقرأ السياسة.", partOfSpeech: "noun", phonetic: nil)
        let card = ReviewCard(word: word, repetitions: 4, lastReviewedAt: now.addingTimeInterval(-172_800), stabilityDays: 20)
        let reviewed = AdaptiveReviewEngine.reviewed(card, grade: .again, now: now)
        XCTAssertEqual(reviewed.repetitions, 0)
        XCTAssertEqual(reviewed.lapses, 1)
        XCTAssertLessThan(reviewed.stabilityDays, card.stabilityDays)
        XCTAssertLessThan(reviewed.dueDate.timeIntervalSince(now), 3_600)
    }

    func testKnowledgeMasteryRespondsToSuccessAndFailure() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let success = MasteryEngine.updatedState(current: nil, itemID: "reading-1", score: 0.9, now: now)
        let failure = MasteryEngine.updatedState(current: success, itemID: "reading-1", score: 0.3, now: now.addingTimeInterval(86_400))
        XCTAssertEqual(success.successes, 1)
        XCTAssertEqual(failure.lapses, 1)
        XCTAssertGreaterThan(failure.difficulty, success.difficulty)
    }
}
