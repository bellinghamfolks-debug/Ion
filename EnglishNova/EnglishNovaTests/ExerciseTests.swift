import XCTest

@testable import EnglishNova

final class ExerciseTests: XCTestCase {
  func testAcceptableAnswer() {
    let exercise = Exercise(
      id: "1", type: .translation, promptAr: "", promptEn: nil, answer: "Thank you", choices: nil,
      tokens: nil, explanationAr: "", accessibilityHint: "", speechText: nil,
      acceptableAnswers: ["Thanks"])
    XCTAssertTrue(exercise.isCorrect("Thanks!"))
  }
}
