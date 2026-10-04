import XCTest
@testable import EnglishNova

final class EnglishNovaPhase2Tests: XCTestCase {

    func testWritingResultDecodesRubricAndRevision() throws {
        let json = #"{"corrected":"I went.","feedbackAr":"جيد","score":72,"rubric":{"taskAchievement":80,"coherence":70,"vocabulary":null,"grammar":65},"revisionAr":"تحسّن","strengthsAr":[],"improvementsAr":[],"corrections":[]}"#
        let result = try JSONDecoder().decode(WritingResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.rubric?.taskAchievement, 80)
        XCTAssertNil(result.rubric?.vocabulary)
        XCTAssertEqual(result.revisionAr, "تحسّن")
    }

    func testWritingResultStillDecodesOldServerResponses() throws {
        let json = #"{"corrected":"Hi.","feedbackAr":"","score":null,"strengthsAr":[],"improvementsAr":[],"corrections":[]}"#
        let result = try JSONDecoder().decode(WritingResult.self, from: Data(json.utf8))
        XCTAssertNil(result.rubric)
        XCTAssertNil(result.revisionAr)
    }

    func testExplainTextResultToleratesMissingFields() throws {
        let json = #"{"translationAr":"ترجمة","vocabulary":[{"term":"notice","meaningAr":"إشعار"}]}"#
        let result = try JSONDecoder().decode(ExplainTextResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.translationAr, "ترجمة")
        XCTAssertEqual(result.summaryAr, "")
        XCTAssertEqual(result.vocabulary.first?.term, "notice")
        XCTAssertNil(result.vocabulary.first?.exampleEn)
        XCTAssertTrue(result.grammar.isEmpty)
    }

    func testQuotaDecodes() throws {
        let json = #"{"dailyUnits":60,"usedUnits":12,"remainingUnits":48,"costs":{"tutor":1},"resetsAt":"2026-10-04T21:00:00Z"}"#
        let quota = try JSONDecoder().decode(AIQuota.self, from: Data(json.utf8))
        XCTAssertEqual(quota.remainingUnits, 48)
    }

    func testWritingTaskTypesMatchServerValues() {
        XCTAssertEqual(Set(WritingTaskType.allCases.map(\.rawValue)),
                       ["free", "email", "opinion", "story", "description", "ielts_task2"])
    }

    func testShadowingPrefersRecentLessonsAndFiltersPlaceholders() throws {
        let catalog = try BundledContentLoader().loadCatalog()
        let a1 = try XCTUnwrap(catalog.levels.first { $0.level == .a1 }?.units.first?.lessons.first)
        var progress = UserProgressSnapshot()
        progress.lessons[a1.id] = LessonProgress(lessonID: a1.id, completedAt: .now, bestScore: 0.9, attempts: 1, earnedPoints: 10)

        let sentences = ShadowingSentencePicker.sentences(catalog: catalog, progress: progress, level: .a0)
        XCTAssertFalse(sentences.isEmpty)
        XCTAssertLessThanOrEqual(sentences.count, 6)
        XCTAssertEqual(Set(sentences.map { $0.lowercased() }).count, sentences.count, "No duplicates")
        for sentence in sentences {
            XCTAssertFalse(sentence.lowercased().contains("key word"))
            XCTAssertNil(sentence.range(of: #"[؀-ۿ]"#, options: .regularExpression))
        }
        let fromRecent = a1.exercises.map(\.answer) + a1.vocabulary.map(\.example)
        XCTAssertTrue(fromRecent.contains(sentences[0]), "The most recent lesson comes first")
    }

    func testShadowingFallsBackWithoutContent() {
        let sentences = ShadowingSentencePicker.sentences(catalog: nil, progress: UserProgressSnapshot(), level: .a0)
        XCTAssertEqual(sentences.count, 2)
    }

    @MainActor
    func testVoiceListingIsSortedBestFirst() {
        let voices = TextToSpeechService.voices(for: "en-US")
        let ranks = voices.map(\.qualityRank)
        XCTAssertEqual(ranks, ranks.sorted(by: >))
        XCTAssertNotNil(TextToSpeechService.preferredVoice(for: "en-US"))
    }
}
