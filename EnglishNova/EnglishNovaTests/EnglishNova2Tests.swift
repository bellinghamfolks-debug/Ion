import XCTest
@testable import EnglishNova

@MainActor
final class EnglishNova2Tests: XCTestCase {

    // MARK: - Fixtures

    private func word(_ english: String, _ arabic: String, example: String = "") -> VocabularyWord {
        VocabularyWord(id: "w-\(english)", english: english, arabic: arabic, example: example,
                       exampleArabic: "", partOfSpeech: "noun", phonetic: nil)
    }

    private func exercise(_ id: String, _ type: ExerciseType, answer: String = "a", choices: [String]? = nil) -> Exercise {
        Exercise(id: id, type: type, promptAr: "سؤال", promptEn: nil, answer: answer, choices: choices,
                 tokens: nil, explanationAr: "", accessibilityHint: "", speechText: nil, acceptableAnswers: nil)
    }

    private func lesson(id: String = "a0-u1-l1", exercises: [Exercise], words: [VocabularyWord]) -> Lesson {
        Lesson(id: id, order: 1, titleAr: "درس", titleEn: "Lesson", objectiveAr: "", estimatedMinutes: 8,
               points: 20, vocabulary: words, exercises: exercises)
    }

    private var sampleWords: [VocabularyWord] {
        [word("apple", "تفاحة", example: "I eat an apple every day."),
         word("water", "ماء"), word("bread", "خبز"), word("milk", "حليب"), word("tea", "شاي")]
    }

    private var sampleExercises: [Exercise] {
        [exercise("e1", .explanation), exercise("e2", .flashcard), exercise("e3", .multipleChoice, choices: ["a", "b"]),
         exercise("e4", .fillBlank), exercise("e5", .translation), exercise("e6", .multipleChoice, choices: ["a", "b"]),
         exercise("e7", .explanation)]
    }

    // MARK: - ExerciseSynthesizer

    func testSynthesizerIsDeterministicAndBounded() {
        let item = lesson(exercises: sampleExercises, words: sampleWords)
        let first = ExerciseSynthesizer.exercises(for: item)
        let second = ExerciseSynthesizer.exercises(for: item)
        XCTAssertEqual(first, second)
        XCTAssertLessThanOrEqual(first.count, ExerciseSynthesizer.maximumPerLesson)
        XCTAssertEqual(Set(first.map(\.type)), [.matchPairs, .trueFalse, .listenType, .dictation])
        XCTAssertTrue(first.allSatisfy { $0.id.hasPrefix("syn-\(item.id)-") && $0.isSynthesized })
    }

    func testSynthesizerSkipsLessonsWithoutEnoughWords() {
        let item = lesson(exercises: sampleExercises, words: [word("one", "واحد")])
        XCTAssertTrue(ExerciseSynthesizer.exercises(for: item).isEmpty)
        XCTAssertEqual(ExerciseSynthesizer.sequence(for: item), item.exercises)
    }

    func testSequenceKeepsOriginalOrderAndClosingExplanation() {
        let item = lesson(exercises: sampleExercises, words: sampleWords)
        let sequence = ExerciseSynthesizer.sequence(for: item)
        XCTAssertEqual(sequence.filter { !$0.isSynthesized }.map(\.id), item.exercises.map(\.id))
        XCTAssertEqual(sequence.last?.id, "e7")
        XCTAssertEqual(sequence.first?.id, "e1")
        // Synthesized items come after the learner has met the words.
        let firstSynthesized = sequence.firstIndex { $0.isSynthesized } ?? 0
        XCTAssertGreaterThanOrEqual(firstSynthesized, 3)
    }

    func testMatchPairsAnswerIsSelfConsistentForBundledCurriculum() throws {
        let catalog = try BundledContentLoader().loadCatalog()
        let lessons = catalog.levels.flatMap { $0.units.flatMap(\.lessons) }
        XCTAssertFalse(lessons.isEmpty)
        for item in lessons {
            let extra = ExerciseSynthesizer.exercises(for: item)
            XCTAssertFalse(extra.isEmpty, "No synthesized items for \(item.id)")
            for generated in extra {
                XCTAssertTrue(generated.isCorrect(generated.answer), "\(generated.id) rejects its own answer")
                if generated.type == .matchPairs {
                    let pairs = Exercise.pairs(from: generated.answer)
                    XCTAssertEqual(pairs.count, generated.tokens?.count, generated.id)
                    XCTAssertEqual(Set(pairs.values), Set(generated.choices ?? []), generated.id)
                }
                if generated.type == .dictation {
                    XCTAssertNil(generated.answer.range(of: #"[؀-ۿ]"#, options: .regularExpression), generated.id)
                }
            }
        }
    }

    // MARK: - Grading

    func testMatchPairsGradingIgnoresOrderAndRejectsSwaps() {
        var item = exercise("m", .matchPairs, answer: "apple=تفاحة|water=ماء")
        item.tokens = ["apple", "water"]
        XCTAssertTrue(item.isCorrect("water=ماء|apple=تفاحة"))
        XCTAssertFalse(item.isCorrect("apple=ماء|water=تفاحة"))
        XCTAssertFalse(item.isCorrect("apple=تفاحة"))
        XCTAssertTrue(ExerciseRenderer.canSubmit(item, selectedAnswer: "apple=تفاحة|water=ماء", arrangedTokens: []))
        XCTAssertFalse(ExerciseRenderer.canSubmit(item, selectedAnswer: "apple=تفاحة", arrangedTokens: []))
    }

    func testTrueFalseIsExact() {
        let item = exercise("t", .trueFalse, answer: "false", choices: ["true", "false"])
        XCTAssertTrue(item.isCorrect("false"))
        XCTAssertFalse(item.isCorrect("true"))
    }

    func testNewTypesFeedTheRightEvidenceGroups() {
        let receptiveOnly = LessonAssessmentEngine.evaluate(level: .a0, evidence: [
            LessonExerciseEvidence(type: .matchPairs, wasCorrect: true, choiceCount: 24),
            LessonExerciseEvidence(type: .trueFalse, wasCorrect: true, choiceCount: 2)
        ])
        XCTAssertNotNil(receptiveOnly.receptiveScore)
        XCTAssertNil(receptiveOnly.controlledScore)

        let controlled = LessonAssessmentEngine.evaluate(level: .a0, evidence: [
            LessonExerciseEvidence(type: .listenType, wasCorrect: true, choiceCount: 0),
            LessonExerciseEvidence(type: .dictation, wasCorrect: false, choiceCount: 0)
        ])
        XCTAssertNotNil(controlled.controlledScore)
        XCTAssertNil(controlled.productiveScore)
        XCTAssertEqual(ExerciseType.dictation.practicedSkill, .listening)
        XCTAssertEqual(ExerciseType.matchPairs.practicedSkill, .vocabulary)
    }

    // MARK: - Lesson player retry round

    func testRetryRoundReplaysMissesWithoutChangingTheScore() {
        let items = [exercise("q1", .fillBlank, answer: "cat"), exercise("q2", .fillBlank, answer: "dog")]
        let model = LessonPlayerViewModel(lesson: lesson(exercises: items, words: []), includeSynthesized: false)
        var mistakes: [String] = []
        model.onMistake = { item, _ in mistakes.append(item.id) }

        model.submit(response: "cat")
        model.continueNext()
        model.submit(response: "horse")
        XCTAssertEqual(mistakes, ["q2"])
        model.continueNext()

        // The missed item comes back once, flagged as a retry.
        XCTAssertEqual(model.phase, .lesson)
        XCTAssertTrue(model.isRetry)
        XCTAssertEqual(model.current.id, "q2")
        XCTAssertNotNil(model.retryPosition)
        XCTAssertNil(model.questionPosition)

        model.submit(response: "dog")
        XCTAssertTrue(model.recoveredIDs.contains("q2"))
        model.continueNext()

        XCTAssertEqual(model.phase, .result)
        XCTAssertEqual(model.evidence.count, 2, "Retry answers must not add evidence")
        XCTAssertEqual(model.correctCount, 1)
        XCTAssertEqual(mistakes, ["q2"], "A retry miss or hit must not record another mistake")
    }

    func testNoRetryRoundWhenEverythingIsRight() {
        let items = [exercise("q1", .fillBlank, answer: "cat")]
        let model = LessonPlayerViewModel(lesson: lesson(exercises: items, words: []), includeSynthesized: false)
        XCTAssertEqual(model.questionPosition?.index, 1)
        XCTAssertEqual(model.questionPosition?.total, 1)
        model.submit(response: "cat")
        model.continueNext()
        XCTAssertEqual(model.phase, .result)
        XCTAssertFalse(model.retryRoundStarted)
    }

    func testMatchPairsChanceBaselineUsesFactorial() {
        var item = exercise("m", .matchPairs)
        item.tokens = ["a", "b", "c", "d"]
        XCTAssertEqual(LessonPlayerViewModel.choiceCount(for: item), 24)
        XCTAssertEqual(LessonPlayerViewModel.choiceCount(for: exercise("t", .trueFalse)), 2)
    }

    // MARK: - Daily session

    private func input(next: Bool = true, doneToday: Bool = false, due: Int = 0, mistakes: Int = 0,
                       planned: Set<DailyStepKind> = [], completed: Set<DailyStepKind> = [], goal: Int = 15) -> DailySessionInput {
        DailySessionInput(hasNextLesson: next, lessonMinutes: 8, lessonCompletedToday: doneToday,
                          dueReviewCount: due, openMistakeCount: mistakes, plannedToday: planned,
                          completedToday: completed, dailyGoalMinutes: goal)
    }

    func testDailySessionOrdersStepsAndSkipsEmptyOnes() {
        let full = DailySessionEngine.makeSession(input(due: 6, mistakes: 3))
        XCTAssertEqual(full.steps.map(\.kind), [.review, .lesson, .mistakes, .speaking])
        XCTAssertEqual(full.nextStep?.kind, .review)
        XCTAssertFalse(full.isComplete)

        let light = DailySessionEngine.makeSession(input())
        XCTAssertEqual(light.steps.map(\.kind), [.lesson, .speaking])
    }

    func testPlannedStepStaysVisibleAndCompletesWhenItsWorkIsDone() {
        let session = DailySessionEngine.makeSession(input(due: 0, mistakes: 0, planned: [.review, .mistakes]))
        XCTAssertEqual(session.steps.map(\.kind), [.review, .lesson, .mistakes, .speaking])
        XCTAssertTrue(session.steps[0].isDone)
        XCTAssertTrue(session.steps[2].isDone)
        XCTAssertEqual(session.nextStep?.kind, .lesson)
    }

    func testSessionCompletesWhenEveryStepIsDone() {
        let session = DailySessionEngine.makeSession(input(doneToday: true, completed: [.speaking]))
        XCTAssertTrue(session.isComplete)
        XCTAssertEqual(session.progress, 1)
        XCTAssertNil(session.nextStep)
        XCTAssertEqual(session.remainingMinutes, 0)
    }

    func testFiveMinuteGoalDropsSpeakingOnFullDays() {
        let session = DailySessionEngine.makeSession(input(due: 4, mistakes: 2, goal: 5))
        XCTAssertEqual(session.steps.map(\.kind), [.review, .lesson, .mistakes])
    }

    func testDailyStoreResetsOnANewDay() {
        let defaults = UserDefaults(suiteName: "EnglishNova2Tests-\(UUID().uuidString)")!
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let store = DailySessionStore(defaults: defaults, now: { clock })
        store.markDone(.lesson)
        XCTAssertEqual(store.completed, [.lesson])
        XCTAssertTrue(store.planned.contains(.lesson))

        clock = clock.addingTimeInterval(86_400 * 2)
        store.reload()
        XCTAssertTrue(store.completed.isEmpty)
        XCTAssertTrue(store.planned.isEmpty)
    }

    // MARK: - Remedial practice

    func testLessonMistakeReferenceRoundTrips() {
        let item = exercise("a0-u1-l1-e4", .fillBlank, answer: "cat")
        let mistake = LessonMistakeFactory.make(lessonID: "a0-u1-l1", source: "Lesson", exercise: item, response: "car")
        let ref = LessonMistakeFactory.reference(from: mistake.id)
        XCTAssertEqual(ref?.lessonID, "a0-u1-l1")
        XCTAssertEqual(ref?.exerciseID, "a0-u1-l1-e4")
        XCTAssertNil(LessonMistakeFactory.reference(from: UUID().uuidString))
        XCTAssertEqual(mistake.correction, "cat")
        XCTAssertFalse(mistake.resolved)
    }

    func testRemedialItemsReplayOriginalExercisesAndSkipResolved() throws {
        let catalog = try BundledContentLoader().loadCatalog()
        let first = try XCTUnwrap(catalog.levels.first?.units.first?.lessons.first)
        let graded = try XCTUnwrap(first.exercises.first { $0.type.isGraded })
        let open = LessonMistakeFactory.make(lessonID: first.id, source: "L", exercise: graded, response: "x")
        var resolved = LessonMistakeFactory.make(lessonID: first.id, source: "L", exercise: graded, response: "y")
        resolved.resolved = true
        let other = LearningMistake(id: "w1", category: "Writing", source: "Coach", prompt: "I am agree",
                                    learnerAnswer: "I am agree", correction: "I agree", explanationAr: "",
                                    createdAt: .now, reviewCount: 0, resolved: false)
        let arabicOnly = LearningMistake(id: "p1", category: "Pron", source: "Lab", prompt: "x",
                                         learnerAnswer: "", correction: "كلمة", explanationAr: "",
                                         createdAt: .now, reviewCount: 0, resolved: false)

        let items = RemedialPracticeEngine.items(mistakes: [open, resolved, other, arabicOnly], catalog: catalog)
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.contains { $0.exercise.id == graded.id && $0.mistakeID == open.id })
        XCTAssertTrue(items.contains { $0.mistakeID == "w1" && $0.exercise.answer == "I agree" })
    }
}
