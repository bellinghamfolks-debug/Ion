import XCTest
@testable import EnglishNova

final class EnglishNovaPhase3Tests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        return value
    }

    private func day(_ offset: Int, hour: Int = 10) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: hour))!
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    // MARK: - Streak freezes

    func testConsecutiveDaysGrowTheStreak() {
        var state = StreakCalculator.State(streak: 0, freezes: 0, lastStudyDate: nil)
        for offset in 0..<3 { state = StreakCalculator.recordStudy(state, on: day(offset), calendar: calendar).state }
        XCTAssertEqual(state.streak, 3)
        let sameDay = StreakCalculator.recordStudy(state, on: day(2, hour: 22), calendar: calendar)
        XCTAssertEqual(sameDay.state, state)
    }

    func testFreezeIsEarnedAtSevenAndCoversAMissedDay() {
        var state = StreakCalculator.State(streak: 6, freezes: 0, lastStudyDate: day(0))
        let seventh = StreakCalculator.recordStudy(state, on: day(1), calendar: calendar)
        XCTAssertTrue(seventh.freezeEarned)
        XCTAssertEqual(seventh.state.freezes, 1)
        state = seventh.state

        let afterGap = StreakCalculator.recordStudy(state, on: day(3), calendar: calendar) // missed day 2
        XCTAssertEqual(afterGap.freezesUsed, 1)
        XCTAssertEqual(afterGap.state.streak, 8)
        XCTAssertEqual(afterGap.state.freezes, 0)
    }

    func testStreakResetsWhenGapExceedsFreezes() {
        let state = StreakCalculator.State(streak: 10, freezes: 1, lastStudyDate: day(0))
        let outcome = StreakCalculator.recordStudy(state, on: day(3), calendar: calendar) // missed two days
        XCTAssertEqual(outcome.state.streak, 1)
        XCTAssertEqual(outcome.state.freezes, 1, "Freezes are kept when they could not save the streak")
    }

    func testFreezesAreCapped() {
        let state = StreakCalculator.State(streak: 13, freezes: 2, lastStudyDate: day(0))
        let outcome = StreakCalculator.recordStudy(state, on: day(1), calendar: calendar)
        XCTAssertFalse(outcome.freezeEarned)
        XCTAssertEqual(outcome.state.freezes, StreakCalculator.maximumFreezes)
    }

    func testOldSessionSnapshotsDecodeWithoutFreezes() throws {
        let json = #"{"hasCompletedOnboarding":true,"displayName":"A","selectedLevel":"A1","points":5,"streak":2}"#
        let snapshot = try JSONDecoder().decode(SessionSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(snapshot.streakFreezes)
    }

    // MARK: - Reminders

    private func context(studied: Bool = false, streak: Int = 0, due: Int = 0, mistakes: Int = 0) -> ReminderPlanner.Context {
        .init(hour: 19, minute: 0, studiedToday: studied, streak: streak, dueReviews: due, openMistakes: mistakes, nextLessonTitle: "Greetings")
    }

    func testRemindersSkipTodayAfterStudyAndStopAfterTwoWeeks() {
        let morning = day(0, hour: 9)
        let notStudied = ReminderPlanner.plan(context(), now: morning, calendar: calendar)
        XCTAssertEqual(notStudied.count, ReminderPlanner.horizonDays)
        XCTAssertTrue(calendar.isDate(notStudied[0].date, inSameDayAs: morning))

        let studied = ReminderPlanner.plan(context(studied: true), now: morning, calendar: calendar)
        XCTAssertEqual(studied.count, ReminderPlanner.horizonDays - 1)
        XCTAssertFalse(calendar.isDate(studied[0].date, inSameDayAs: morning))
    }

    func testReminderAfterTheHourStartsTomorrow() {
        let evening = day(0, hour: 21)
        let plan = ReminderPlanner.plan(context(), now: evening, calendar: calendar)
        XCTAssertTrue(plan.allSatisfy { $0.date > evening })
        XCTAssertEqual(plan.count, ReminderPlanner.horizonDays - 1)
    }

    func testFirstReminderIsPersonalizedByPriority() {
        let streak = ReminderPlanner.personalized(context(streak: 5, due: 3))
        let due = ReminderPlanner.personalized(context(due: 3, mistakes: 2))
        let lesson = ReminderPlanner.personalized(context())
        XCTAssertTrue(streak.title.contains("5"))
        XCTAssertTrue(due.body.contains("3"))
        XCTAssertEqual(lesson.body, "Greetings")
    }

    // MARK: - Mock exam

    func testMockExamUsesAllFortyQuestionsAndGradesBand() {
        let listening = MockExamSection.ielts(.listening)
        XCTAssertEqual(listening.questions.count, 40)
        XCTAssertEqual(listening.minutes(extraTime: false), 30)
        XCTAssertEqual(listening.minutes(extraTime: true), 38)

        var answers: [String: String] = [:]
        for question in listening.questions.prefix(23) { answers[question.id] = question.answer }
        let result = MockExamEngine.grade(listening, answers: answers, minutesUsed: 25)
        XCTAssertEqual(result.correct, 23)
        XCTAssertEqual(result.answered, 23)
        XCTAssertEqual(result.band, 6.0)
        XCTAssertEqual(result.modules.reduce(0) { $0 + $1.total }, 40)
        XCTAssertTrue(result.sessionID(day: .now).hasPrefix("ielts-full-listening-"))
    }

    func testEmptyMockScoresZero() {
        let reading = MockExamSection.ielts(.reading)
        let result = MockExamEngine.grade(reading, answers: [:], minutesUsed: 0)
        XCTAssertEqual(result.correct, 0)
        XCTAssertEqual(result.minutesUsed, 1)
        XCTAssertEqual(result.band, 0)
    }

    // MARK: - Skills and CEFR

    func testSkillScoresNeedEvidence() {
        var progress = UserProgressSnapshot()
        progress.skills[.vocabulary] = SkillProgress(skill: .vocabulary, attempts: 10, correct: 8, lastPracticedAt: nil)
        progress.skills[.grammar] = SkillProgress(skill: .grammar, attempts: 2, correct: 2, lastPracticedAt: nil)
        let scores = SkillsDashboardEngine.scores(progress: progress)
        XCTAssertEqual(scores.count, 6)
        XCTAssertEqual(scores.first { $0.skill == .vocabulary }?.value ?? 0, 0.8, accuracy: 0.001)
        XCTAssertNil(scores.first { $0.skill == .grammar }?.value)
        XCTAssertNil(scores.first { $0.skill == .writing }?.value)
    }

    func testCEFREstimateFollowsCompletedLevels() throws {
        let catalog = try BundledContentLoader().loadCatalog()
        var progress = UserProgressSnapshot()
        XCTAssertEqual(SkillsDashboardEngine.estimate(catalog: catalog, progress: progress, selectedLevel: .a0).level, .a0)

        let a0 = try XCTUnwrap(catalog.levels.first { $0.level == .a0 }).units.flatMap(\.lessons)
        for lesson in a0 {
            progress.lessons[lesson.id] = LessonProgress(lessonID: lesson.id, completedAt: .now, bestScore: 0.85, attempts: 1, earnedPoints: 10)
        }
        let estimate = SkillsDashboardEngine.estimate(catalog: catalog, progress: progress, selectedLevel: .a0)
        XCTAssertEqual(estimate.level, .a1)
        XCTAssertEqual(estimate.confidence, .high)
    }

    func testFocusPicksWeakestKnownSkill() {
        let scores = [
            SkillScore(skill: .vocabulary, value: 0.9, evidence: 20),
            SkillScore(skill: .listening, value: 0.5, evidence: 10),
            SkillScore(skill: .writing, value: nil, evidence: 0)
        ]
        XCTAssertEqual(SkillsDashboardEngine.focus(scores), .listening)
    }

    // MARK: - Word of the day

    func testWordOfTheDayIsStableWithinADayAndChanges() throws {
        let catalog = try BundledContentLoader().loadCatalog()
        let first = DailyContentEngine.wordOfTheDay(catalog: catalog, level: .a1, date: day(0, hour: 8), calendar: calendar)
        let later = DailyContentEngine.wordOfTheDay(catalog: catalog, level: .a1, date: day(0, hour: 20), calendar: calendar)
        XCTAssertNotNil(first)
        XCTAssertEqual(first, later)
        let week = Set((0..<7).compactMap { DailyContentEngine.wordOfTheDay(catalog: catalog, level: .a1, date: day($0), calendar: calendar)?.id })
        XCTAssertGreaterThan(week.count, 3)
        XCTAssertNil(DailyContentEngine.wordOfTheDay(catalog: nil, level: .a1))
    }
}
