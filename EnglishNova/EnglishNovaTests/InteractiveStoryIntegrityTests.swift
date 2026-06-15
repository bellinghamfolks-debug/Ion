import XCTest

@testable import EnglishNova

final class InteractiveStoryIntegrityTests: XCTestCase {
    func testEveryChoicePointsToExistingScene() {
        for story in InteractiveStoryLibrary.stories {
            let ids = Set(story.scenes.map(\.id))
            XCTAssertTrue(ids.contains(story.startSceneID), story.id)
            XCTAssertTrue(story.scenes.contains { $0.ending != nil }, story.id)
            for choice in story.scenes.flatMap(\.choices) {
                XCTAssertTrue(ids.contains(choice.nextSceneID), "\(story.id): \(choice.nextSceneID)")
            }
        }
    }

    func testEveryStoryHasVocabularyAndAtLeastTwoEndings() {
        for story in InteractiveStoryLibrary.stories {
            XCTAssertFalse(story.keyWords.isEmpty)
            XCTAssertGreaterThanOrEqual(story.scenes.compactMap(\.ending).count, 2)
        }
    }
}
