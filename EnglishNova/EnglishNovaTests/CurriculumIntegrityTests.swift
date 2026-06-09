import XCTest

@testable import EnglishNova

final class CurriculumIntegrityTests: XCTestCase {
  func testCatalogStructureAndUniqueIdentifiers() throws {
    let catalog = try BundledContentLoader().loadCatalog()
    XCTAssertEqual(catalog.levels.count, 6)

    let lessons = catalog.levels.flatMap(\.units).flatMap(\.lessons)
    XCTAssertGreaterThanOrEqual(lessons.count, 152)
    XCTAssertEqual(Set(lessons.map(\.id)).count, lessons.count)

    let exercises = lessons.flatMap(\.exercises)
    XCTAssertEqual(Set(exercises.map(\.id)).count, exercises.count)
    XCTAssertTrue(lessons.allSatisfy { !$0.exercises.isEmpty })
    XCTAssertTrue(
      exercises.allSatisfy { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
  }

  func testAllLevelsHaveSubstantialStartingContent() throws {
    let catalog = try BundledContentLoader().loadCatalog()
    for level in catalog.levels {
      XCTAssertGreaterThanOrEqual(
        level.units.flatMap(\.lessons).count, 8,
        "المستوى \(level.level.rawValue) يحتاج ثمانية دروس على الأقل")
    }
  }
}
