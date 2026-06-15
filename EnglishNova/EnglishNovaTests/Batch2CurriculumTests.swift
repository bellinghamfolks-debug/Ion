import XCTest

@testable import EnglishNova

final class Batch2CurriculumTests: XCTestCase {
    func testA0AndA1ContainSixtyLessonsEach() throws {
        let catalog = try BundledContentLoader().loadCatalog()
        for expected in [CEFRLevel.a0, .a1] {
            let level = try XCTUnwrap(catalog.levels.first { $0.level == expected })
            XCTAssertEqual(level.units.count, 10)
            XCTAssertEqual(level.units.flatMap(\.lessons).count, 60)
            XCTAssertTrue(level.units.allSatisfy { $0.lessons.count == 6 })
        }
    }

    func testFoundationLessonsHaveSixExerciseModes() throws {
        let catalog = try BundledContentLoader().loadCatalog()
        let lessons = catalog.levels
            .filter { $0.level == .a0 || $0.level == .a1 }
            .flatMap(\.units)
            .flatMap(\.lessons)
        XCTAssertTrue(lessons.allSatisfy { $0.exercises.count >= 6 })
        XCTAssertTrue(lessons.allSatisfy { Set($0.exercises.map(\.type)).contains(.speak) })
        XCTAssertTrue(lessons.allSatisfy { Set($0.exercises.map(\.type)).contains(.listenAndChoose) })
        XCTAssertTrue(lessons.allSatisfy { Set($0.exercises.map(\.type)).contains(.translation) })
    }


    func testBatchThreeAdvancedPracticeCounts() {
        XCTAssertEqual(AdvancedPracticeLibrary.ieltsSpeakingQuestions.count, 12)
        XCTAssertEqual(AdvancedPracticeLibrary.stepQuestions.count, 24)
        XCTAssertEqual(AdvancedPracticeLibrary.interviewQuestions.count, 18)
    }
}
