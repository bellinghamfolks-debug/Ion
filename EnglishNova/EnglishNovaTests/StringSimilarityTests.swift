import XCTest

@testable import EnglishNova

final class StringSimilarityTests: XCTestCase {
  func testExactSentence() {
    XCTAssertEqual(StringSimilarity.score("Hello world", "Hello world"), 1, accuracy: 0.001)
  }

  func testIgnoresPunctuationAndCase() {
    XCTAssertGreaterThan(StringSimilarity.score("I am ready.", "i am ready"), 0.99)
  }

  func testDifferentSentenceScoresLower() {
    XCTAssertLessThan(StringSimilarity.score("Hello", "Goodbye"), 0.5)
  }


  func testPronunciationAnalyzerRewardsExactSentence() {
    let report = PronunciationAnalyzer.analyze(
      target: "I would like coffee please",
      recognized: "I would like coffee please",
      accent: .american,
      duration: 3.2,
      segments: []
    )
    XCTAssertGreaterThan(report.accuracy, 0.95)
    XCTAssertGreaterThan(report.completeness, 0.95)
    XCTAssertTrue(report.needsPractice.isEmpty)
  }

  func testPronunciationAnalyzerFindsOmittedWord() {
    let report = PronunciationAnalyzer.analyze(
      target: "I would like a cup of coffee",
      recognized: "I would like coffee",
      accent: .british,
      duration: 2.8,
      segments: []
    )
    XCTAssertTrue(report.words.contains { $0.issue == .omitted })
    XCTAssertLessThan(report.completeness, 1)
  }
}
