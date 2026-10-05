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
  func testSelectedDistractorCannotPassByTextSimilarity() {
    for type in [ExerciseType.multipleChoice, .listenAndChoose] {
      let correct = "The findings may apply to all customers."
      let wrong = "The findings may not apply to all customers."
      let exercise = Exercise(
        id: "choice", type: type, promptAr: "", answer: correct,
        choices: [correct, wrong], explanationAr: "", accessibilityHint: "")
      XCTAssertTrue(exercise.isCorrect(correct))
      XCTAssertFalse(exercise.isCorrect(wrong))
    }
  }
}
