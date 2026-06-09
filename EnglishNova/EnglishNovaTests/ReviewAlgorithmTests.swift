import XCTest

@testable import EnglishNova

final class ReviewAlgorithmTests: XCTestCase {
  func testReviewGradeTitlesExist() {
    XCTAssertEqual(ReviewGrade.good.titleAr, "جيد")
    XCTAssertEqual(ReviewGrade.again.titleAr, "إعادة")
  }
}
