import XCTest
@testable import EnglishNova

final class LessonReviewEngineTests: XCTestCase {
    func testWeakReviewReturnsSoonAndStrongRecallExpandsInterval() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let weak = LessonReviewEngine.updatedState(
            lessonID: "a1-review",
            current: nil,
            score: 0.42,
            now: now
        )
        XCTAssertEqual(weak.intervalDays, 1)
        XCTAssertEqual(weak.lapses, 1)

        let current = LessonReviewState(
            lessonID: "b2-review",
            repetitions: 3,
            intervalDays: 7,
            dueDate: now,
            lastReviewedAt: now.addingTimeInterval(-7 * 86_400),
            lastScore: 0.88,
            bestScore: 0.94,
            lapses: 0,
            successfulStreak: 3
        )
        let strong = LessonReviewEngine.updatedState(
            lessonID: current.lessonID,
            current: current,
            score: 0.98,
            now: now
        )
        XCTAssertGreaterThan(strong.intervalDays, current.intervalDays)
        XCTAssertLessThanOrEqual(strong.intervalDays, 90)
        XCTAssertEqual(strong.successfulStreak, 4)
    }

    func testLegacyCompletedLessonAutomaticallyEntersReviewQueue() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let completed = now.addingTimeInterval(-2 * 86_400)
        let lesson = makeLesson(id: "a2-legacy", productive: 2, controlled: 2, receptive: 2)
        let catalog = CourseCatalog(
            version: 1,
            levels: [CourseLevel(
                id: "a2",
                level: .a2,
                titleAr: "A2",
                titleEn: "A2",
                descriptionAr: "",
                units: [CourseUnit(
                    id: "u1",
                    order: 1,
                    titleAr: "",
                    titleEn: "",
                    descriptionAr: "",
                    icon: "book",
                    lessons: [lesson]
                )]
            )]
        )
        let snapshot = UserProgressSnapshot(
            lessons: [lesson.id: LessonProgress(
                lessonID: lesson.id,
                completedAt: completed,
                bestScore: 0.78,
                attempts: 1,
                earnedPoints: 10
            )]
        )

        let candidates = LessonReviewEngine.allCandidates(catalog: catalog, snapshot: snapshot, now: now)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertTrue(candidates[0].isDue)
        XCTAssertNil(candidates[0].state)
    }

    func testAdvancedReviewPrioritizesProductiveTasks() {
        let lesson = makeLesson(id: "c1-argument", productive: 4, controlled: 3, receptive: 3)
        let selected = LessonReviewEngine.reviewExercises(for: lesson, reviewCount: 0, limit: 6)
        let productiveCount = selected.filter { $0.type == .translation || $0.type == .speak }.count
        XCTAssertEqual(selected.count, 6)
        XCTAssertGreaterThanOrEqual(productiveCount, 3)
    }

    func testRepeatedReviewRotatesTheSample() {
        let lesson = makeLesson(id: "b1-rotation", productive: 4, controlled: 4, receptive: 4)
        let first = LessonReviewEngine.reviewExercises(for: lesson, reviewCount: 0, limit: 6).map(\.id)
        let second = LessonReviewEngine.reviewExercises(for: lesson, reviewCount: 1, limit: 6).map(\.id)
        XCTAssertNotEqual(first, second)
    }

    private func makeLesson(id: String, productive: Int, controlled: Int, receptive: Int) -> Lesson {
        var exercises: [Exercise] = []
        for index in 0..<productive {
            exercises.append(makeExercise(id: "p-\(index)", type: index.isMultiple(of: 2) ? .translation : .speak))
        }
        for index in 0..<controlled {
            exercises.append(makeExercise(id: "c-\(index)", type: index.isMultiple(of: 2) ? .fillBlank : .arrangeWords))
        }
        for index in 0..<receptive {
            exercises.append(makeExercise(id: "r-\(index)", type: index.isMultiple(of: 2) ? .multipleChoice : .listenAndChoose))
        }
        return Lesson(
            id: id,
            order: 1,
            titleAr: "درس",
            titleEn: "Lesson",
            objectiveAr: "",
            estimatedMinutes: 10,
            points: 20,
            vocabulary: [],
            exercises: exercises
        )
    }

    private func makeExercise(id: String, type: ExerciseType) -> Exercise {
        Exercise(
            id: id,
            type: type,
            promptAr: "سؤال",
            promptEn: "Prompt",
            answer: "answer",
            choices: ["answer", "other"],
            tokens: ["answer"],
            explanationAr: "",
            accessibilityHint: "",
            speechText: "answer",
            acceptableAnswers: nil
        )
    }
}
