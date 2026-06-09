import XCTest

@testable import EnglishNova

final class LearningPlannerTests: XCTestCase {
    func testPlanStartsWithIncompleteLesson() throws {
        let catalog = try BundledContentLoader().loadCatalog()
        let plan = LearningPlanner.makePlan(
            catalog: catalog,
            progress: UserProgressSnapshot(),
            dueCards: [],
            level: .a0,
            targetMinutes: 15,
            reducePressure: false
        )
        XCTAssertFalse(plan.items.isEmpty)
        XCTAssertEqual(plan.items.first?.kind, .lesson)
        XCTAssertEqual(plan.items.first?.referenceID, "a0-u1-l1")
    }

    func testCalmModeCapsTargetAtTenMinutes() throws {
        let catalog = try BundledContentLoader().loadCatalog()
        let plan = LearningPlanner.makePlan(
            catalog: catalog,
            progress: UserProgressSnapshot(),
            dueCards: [],
            level: .a1,
            targetMinutes: 45,
            reducePressure: true
        )
        XCTAssertEqual(plan.targetMinutes, 10)
    }


    func testPersonalizationPrioritizesUnresolvedMistakes() {
        let mistake = LearningMistake(
            id: "m1",
            category: "النطق",
            source: "test",
            prompt: "three",
            learnerAnswer: "tree",
            correction: "three",
            explanationAr: "اختبار",
            createdAt: .now,
            reviewCount: 0,
            resolved: false
        )
        let recommendations = PersonalizationEngine.recommendations(
            progress: UserProgressSnapshot(),
            memory: LearnerMemorySnapshot(mistakes: [mistake]),
            dueCards: []
        )
        XCTAssertTrue(recommendations.contains { $0.destination == .mistakes })
    }
}
