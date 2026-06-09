import Foundation

actor ProgressRepository: ProgressRepositoryProtocol {
    private let store: FileStore
    private let key = "progress.json"
    private var cached: UserProgressSnapshot?

    init(store: FileStore) { self.store = store }

    func snapshot() async -> UserProgressSnapshot {
        if let cached { return cached }
        let value = (try? await store.read(UserProgressSnapshot.self, from: key)) ?? UserProgressSnapshot()
        cached = value
        return value
    }

    func progress(for lessonID: String) async -> LessonProgress? {
        await snapshot().lessons[lessonID]
    }

    func recordLesson(lessonID: String, score: Double, points: Int, minutes: Int) async {
        var value = await snapshot()
        var lesson = value.lessons[lessonID] ?? LessonProgress(
            lessonID: lessonID,
            completedAt: nil,
            bestScore: 0,
            attempts: 0,
            earnedPoints: 0
        )
        lesson.attempts += 1
        lesson.bestScore = max(lesson.bestScore, score)
        lesson.earnedPoints = max(lesson.earnedPoints, points)
        if score >= 0.7 { lesson.completedAt = .now }
        value.lessons[lessonID] = lesson
        recordActivity(in: &value, minutes: minutes, exercises: 1, points: points)
        await persist(value)
    }

    func recordSkill(_ skill: LanguageSkill, correct: Bool, at date: Date = .now) async {
        var value = await snapshot()
        var metric = value.skills[skill] ?? SkillProgress(skill: skill)
        metric.attempts += 1
        if correct { metric.correct += 1 }
        metric.lastPracticedAt = date
        value.skills[skill] = metric
        await persist(value)
    }

    func recordStory(storyID: String, score: Double, endingID: String) async {
        var value = await snapshot()
        var story = value.stories[storyID] ?? StoryProgress(storyID: storyID)
        story.completedAt = .now
        story.bestScore = max(story.bestScore, score)
        if !story.endingsReached.contains(endingID) { story.endingsReached.append(endingID) }
        value.stories[storyID] = story
        recordActivity(in: &value, minutes: 5, exercises: 1, points: Int(score * 25))
        await persist(value)
    }

    func savePlacementResult(_ result: PlacementResult) async {
        var value = await snapshot()
        value.lastPlacementResult = result
        await persist(value)
    }

    func recordPracticeSession(_ session: PracticeSessionRecord) async {
        var value = await snapshot()
        value.practiceSessions.insert(session, at: 0)
        value.practiceSessions = Array(value.practiceSessions.prefix(1_000))
        var metric = value.skills[session.domain.languageSkill] ?? SkillProgress(skill: session.domain.languageSkill)
        metric.attempts += 1
        if session.score >= 0.70 { metric.correct += 1 }
        metric.lastPracticedAt = session.createdAt
        value.skills[session.domain.languageSkill] = metric
        value.knowledgeStates[session.sourceID] = MasteryEngine.updatedState(
            current: value.knowledgeStates[session.sourceID],
            itemID: session.sourceID,
            score: session.score,
            now: session.createdAt
        )
        trimKnowledgeStates(&value.knowledgeStates)
        recordActivity(in: &value, minutes: session.minutes, exercises: 1, points: Int(session.score * 30), at: session.createdAt)
        await persist(value)
    }

    func recordKnowledge(itemID: String, score: Double, at date: Date = .now) async {
        var value = await snapshot()
        value.knowledgeStates[itemID] = MasteryEngine.updatedState(
            current: value.knowledgeStates[itemID],
            itemID: itemID,
            score: score,
            now: date
        )
        trimKnowledgeStates(&value.knowledgeStates)
        await persist(value)
    }

    func replace(with snapshot: UserProgressSnapshot) async {
        var safe = snapshot
        safe.practiceSessions = Array(snapshot.practiceSessions.prefix(1_000))
        trimKnowledgeStates(&safe.knowledgeStates)
        await persist(safe)
    }

    private func trimKnowledgeStates(_ states: inout [String: KnowledgeState]) {
        guard states.count > 5_000 else { return }
        let originalStates = states
        let recentKeys = originalStates.values
            .sorted { ($0.lastReviewedAt ?? .distantPast) > ($1.lastReviewedAt ?? .distantPast) }
            .prefix(5_000)
            .map(\.itemID)
        states = Dictionary(uniqueKeysWithValues: recentKeys.compactMap { key in
            originalStates[key].map { (key, $0) }
        })
    }

    private func recordActivity(
        in value: inout UserProgressSnapshot,
        minutes: Int,
        exercises: Int,
        points: Int,
        at date: Date = .now
    ) {
        let today = date.startOfDay
        if let index = value.activity.firstIndex(where: { $0.date.startOfDay == today }) {
            value.activity[index].minutes += max(0, minutes)
            value.activity[index].exercises += max(0, exercises)
            value.activity[index].points += max(0, points)
        } else {
            value.activity.append(DailyActivity(
                date: today,
                minutes: max(0, minutes),
                exercises: max(0, exercises),
                points: max(0, points)
            ))
        }
    }

    private func persist(_ value: UserProgressSnapshot) async {
        cached = value
        try? await store.write(value, to: key)
    }
}

actor LearningMemoryRepository: LearningMemoryRepositoryProtocol {
    private let store: FileStore
    private let key = "learning-memory.json"
    private var cached: LearnerMemorySnapshot?

    init(store: FileStore) {
        self.store = store
    }

    func snapshot() async -> LearnerMemorySnapshot {
        if let cached { return cached }
        let value = (try? await store.read(LearnerMemorySnapshot.self, from: key)) ?? LearnerMemorySnapshot()
        cached = sanitized(value)
        return cached ?? LearnerMemorySnapshot()
    }

    func recordPronunciation(_ report: PronunciationReport) async {
        var value = await snapshot()
        value.pronunciationReports.insert(report, at: 0)
        value.pronunciationReports = Array(value.pronunciationReports.prefix(300))
        await persist(value)
    }

    func recordMistake(_ mistake: LearningMistake) async {
        var value = await snapshot()
        if let index = value.mistakes.firstIndex(where: {
            $0.category == mistake.category &&
            $0.prompt.caseInsensitiveCompare(mistake.prompt) == .orderedSame &&
            !$0.resolved
        }) {
            value.mistakes[index].reviewCount += 1
            value.mistakes[index].resolved = false
        } else {
            value.mistakes.insert(mistake, at: 0)
        }
        value.mistakes = Array(value.mistakes.prefix(1_000))
        await persist(value)
    }

    func recordConversation(_ entry: ConversationMemoryEntry) async {
        var value = await snapshot()
        value.conversations.insert(entry, at: 0)
        value.conversations = Array(value.conversations.prefix(250))
        await persist(value)
    }

    func recordExamAttempt(_ attempt: ExamAttempt) async {
        var value = await snapshot()
        value.examAttempts.insert(attempt, at: 0)
        value.examAttempts = Array(value.examAttempts.prefix(200))
        await persist(value)
    }

    func recordInterviewAttempt(_ attempt: ExamAttempt) async {
        var value = await snapshot()
        value.interviewAttempts.insert(attempt, at: 0)
        value.interviewAttempts = Array(value.interviewAttempts.prefix(200))
        await persist(value)
    }

    func markMistakeResolved(id: String, resolved: Bool) async {
        var value = await snapshot()
        guard let index = value.mistakes.firstIndex(where: { $0.id == id }) else { return }
        value.mistakes[index].resolved = resolved
        value.mistakes[index].reviewCount += 1
        await persist(value)
    }

    func replace(with snapshot: LearnerMemorySnapshot) async {
        await persist(sanitized(snapshot))
    }

    private func sanitized(_ value: LearnerMemorySnapshot) -> LearnerMemorySnapshot {
        LearnerMemorySnapshot(
            pronunciationReports: Array(value.pronunciationReports.prefix(300)),
            mistakes: Array(value.mistakes.prefix(1_000)),
            conversations: Array(value.conversations.prefix(250)),
            examAttempts: Array(value.examAttempts.prefix(200)),
            interviewAttempts: Array(value.interviewAttempts.prefix(200))
        )
    }

    private func persist(_ value: LearnerMemorySnapshot) async {
        let safe = sanitized(value)
        cached = safe
        try? await store.write(safe, to: key)
    }
}
