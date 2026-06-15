import XCTest

@testable import EnglishNova

final class MigrationDecodingTests: XCTestCase {
    func testOldReviewCardGetsBatchTwoDefaults() throws {
        let json = #"""
        {
          "word": {
            "id": "hello",
            "english": "Hello",
            "arabic": "مرحبًا",
            "example": "Hello, Sara.",
            "exampleArabic": "مرحبًا يا سارة.",
            "partOfSpeech": "interjection",
            "phonetic": null
          },
          "repetitions": 1,
          "intervalDays": 2,
          "easeFactor": 2.5,
          "dueDate": "2026-06-08T00:00:00Z",
          "lastReviewedAt": null
        }
        """#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let card = try decoder.decode(ReviewCard.self, from: Data(json.utf8))
        XCTAssertFalse(card.isFavorite)
        XCTAssertEqual(card.tags, [])
        XCTAssertEqual(card.note, "")
        XCTAssertEqual(card.confidence, 0)
    }

    func testOldSettingsGetReminderDefaults() throws {
        let json = #"""
        {
          "interfaceLanguage": "ar",
          "dailyGoalMinutes": 15,
          "speechRate": 0.45,
          "hapticsEnabled": true,
          "serverURLString": ""
        }
        """#
        let snapshot = try JSONDecoder().decode(SettingsSnapshot.self, from: Data(json.utf8))
        XCTAssertFalse(snapshot.reminderEnabled)
        XCTAssertEqual(snapshot.reminderHour, 19)
        XCTAssertFalse(snapshot.autoPlayLessonAudio)
    }


    func testBatchTwoSettingsGetBatchThreeCoachDefaults() throws {
        let json = #"""
        {
          "interfaceLanguage": "ar",
          "dailyGoalMinutes": 15,
          "speechRate": 0.45,
          "hapticsEnabled": true,
          "serverURLString": "",
          "reminderEnabled": false,
          "reminderHour": 19,
          "reminderMinute": 0,
          "autoPlayLessonAudio": false,
          "reduceLearningPressure": false
        }
        """#
        let snapshot = try JSONDecoder().decode(SettingsSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.accentVariant, .american)
        XCTAssertTrue(snapshot.adaptiveCoachEnabled)
        XCTAssertTrue(snapshot.autoSpeakCoachPrompts)
        XCTAssertTrue(snapshot.showArabicCoachHints)
    }

    func testEmptyLearningMemoryGetsSafeDefaults() throws {
        let memory = try JSONDecoder().decode(LearnerMemorySnapshot.self, from: Data("{}".utf8))
        XCTAssertTrue(memory.pronunciationReports.isEmpty)
        XCTAssertTrue(memory.mistakes.isEmpty)
        XCTAssertTrue(memory.examAttempts.isEmpty)
    }
}
