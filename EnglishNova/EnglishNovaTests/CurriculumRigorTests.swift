import XCTest
@testable import EnglishNova

final class CurriculumRigorTests: XCTestCase {
    func testProductiveRequirementRisesByLevel() {
        XCTAssertEqual(CurriculumRigorAudit.requiredProductiveTasks(for: .a0), 1)
        XCTAssertEqual(CurriculumRigorAudit.requiredProductiveTasks(for: .a2), 2)
        XCTAssertEqual(CurriculumRigorAudit.requiredProductiveTasks(for: .b2), 3)
        XCTAssertEqual(CurriculumRigorAudit.requiredProductiveTasks(for: .c1), 3)
    }

    func testEveryLoadedLessonMeetsItsLevelProductiveFloor() throws {
        let catalog = try BundledContentLoader().loadCatalog()
        for level in catalog.levels {
            let weak = CurriculumRigorAudit.lessonsBelowProductiveFloor(in: level)
            XCTAssertTrue(weak.isEmpty, "\(level.level.rawValue) lessons below productive floor: \(weak.prefix(12))")
        }
    }

    func testAdvancedCurriculumDoesNotKeepKnownGeneratorFillerGlosses() throws {
        let catalog = try BundledContentLoader().loadCatalog()
        let advanced = catalog.levels
            .filter { $0.level == .b2 || $0.level == .c1 }
            .flatMap(\.units)
            .flatMap(\.lessons)
            .flatMap(\.vocabulary)
        let forbidden = ["كلمة من المثال", "كلمة في المثال", "بداية الجملة", "جزء من المثال"]
        let offenders = advanced.filter { word in
            forbidden.contains { word.arabic.contains($0) }
        }
        XCTAssertTrue(offenders.isEmpty, "Generator filler remained in advanced vocabulary: \(offenders.prefix(8).map(\.english))")
    }
}
