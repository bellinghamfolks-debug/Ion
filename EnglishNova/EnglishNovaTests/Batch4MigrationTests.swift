import XCTest
@testable import EnglishNova

final class Batch4MigrationTests: XCTestCase {
    func testOldReviewCardDecodesWithAdaptiveDefaults() throws {
        let json = """
        {
          "word": {
            "id": "legacy-word",
            "english": "clear",
            "arabic": "واضح",
            "example": "The message is clear.",
            "exampleArabic": "الرسالة واضحة.",
            "partOfSpeech": "adjective"
          },
          "repetitions": 2,
          "intervalDays": 6,
          "easeFactor": 2.5,
          "dueDate": 0,
          "addedAt": 0,
          "isFavorite": false,
          "tags": [],
          "note": "",
          "confidence": 0.4
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let card = try decoder.decode(ReviewCard.self, from: json)
        XCTAssertEqual(card.difficulty, 5)
        XCTAssertEqual(card.stabilityDays, 6)
        XCTAssertEqual(card.lapses, 0)
        XCTAssertEqual(card.scheduledIntervalDays, 6)
    }

    func testOldProgressDecodesWithoutBatch4Collections() throws {
        let json = """
        {"lessons":{},"activity":[],"skills":{},"stories":{}}
        """.data(using: .utf8)!
        let progress = try JSONDecoder().decode(UserProgressSnapshot.self, from: json)
        XCTAssertTrue(progress.practiceSessions.isEmpty)
        XCTAssertTrue(progress.knowledgeStates.isEmpty)
    }

    func testPathwayProgressIsBounded() {
        let snapshot = UserProgressSnapshot(practiceSessions: [
            .init(id: "1", domain: .reading, sourceID: "r1", titleAr: "قراءة", level: .b1, score: 0.9, minutes: 5, createdAt: .now, details: []),
            .init(id: "2", domain: .writing, sourceID: "w1", titleAr: "كتابة", level: .b1, score: 0.8, minutes: 8, createdAt: .now, details: [])
        ])
        let value = LearningPathwayCatalog.progress(for: .academicIELTS, snapshot: snapshot)
        XCTAssertTrue((0...1).contains(value.overallProgress))
        XCTAssertTrue((0...1).contains(value.currentMilestoneProgress))
    }
}
