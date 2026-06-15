#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/SemanticValidation.swift" <<'SWIFT'
import Foundation

@main
struct SemanticValidation {
    static func main() async throws {
        let root = ProcessInfo.processInfo.environment["ENGLISHNOVA_ROOT"]!
        let curriculumURL = URL(fileURLWithPath: root + "/EnglishNova/Resources/Curriculum/curriculum.json")
        let catalog = try JSONDecoder().decode(CourseCatalog.self, from: Data(contentsOf: curriculumURL))
        let lessons = catalog.levels.flatMap(\.units).flatMap(\.lessons)
        precondition(catalog.levels.count == 6)
        precondition(lessons.count == 152)
        precondition(PlacementQuestionBank.all.count == 48)
        precondition(ConversationLibrary.scenarios.count == 12)
        precondition(InteractiveStoryLibrary.stories.count == 12)
        precondition(AdvancedPracticeLibrary.ieltsSpeakingQuestions.count == 12)
        precondition(AdvancedPracticeLibrary.stepQuestions.count == 24)
        precondition(AdvancedPracticeLibrary.interviewQuestions.count == 18)
        precondition(AdvancedSkillsLibrary.readingPassages.count == 24)
        precondition(AdvancedSkillsLibrary.listeningPassages.count == 24)
        precondition(AdvancedSkillsLibrary.writingPrompts.count == 24)
        precondition(LearningPathwayCatalog.all.count == 6)

        for story in InteractiveStoryLibrary.stories {
            let sceneIDs = Set(story.scenes.map(\.id))
            precondition(sceneIDs.contains(story.startSceneID))
            precondition(story.scenes.compactMap(\.ending).count >= 2)
            precondition(story.scenes.flatMap(\.choices).allSatisfy { sceneIDs.contains($0.nextSceneID) })
        }

        var engine = AdaptivePlacementEngine(questions: PlacementQuestionBank.all)
        while !engine.shouldFinish, let question = engine.nextQuestion() {
            engine.submit(question: question, selectedAnswer: question.answer)
        }
        let placement = engine.result()
        precondition(placement.responses.count >= 12)
        precondition(placement.correctCount == placement.responses.count)
        precondition(placement.skills.count == LanguageSkill.allCases.count)

        let legacyProgress = #"{"lessons":{},"activity":[]}"#.data(using: .utf8)!
        let migratedProgress = try JSONDecoder().decode(UserProgressSnapshot.self, from: legacyProgress)
        precondition(migratedProgress.skills.isEmpty)
        precondition(migratedProgress.practiceSessions.isEmpty)
        precondition(migratedProgress.knowledgeStates.isEmpty)

        let legacyCardJSON = #"{"word":{"id":"hello","english":"Hello","arabic":"مرحبا","example":"Hello.","exampleArabic":"مرحبا.","partOfSpeech":"interjection","phonetic":null},"repetitions":1,"intervalDays":2,"easeFactor":2.5,"dueDate":"2026-06-08T00:00:00Z","lastReviewedAt":"2026-06-06T00:00:00Z"}"#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacyCard = try decoder.decode(ReviewCard.self, from: legacyCardJSON)
        precondition(legacyCard.tags.isEmpty && !legacyCard.isFavorite)
        precondition(legacyCard.stabilityDays == 2)
        precondition(legacyCard.difficulty == 5)
        precondition(legacyCard.lapses == 0)

        let reviewDate = ISO8601DateFormatter().date(from: "2026-06-09T12:00:00Z")!
        let remembered = AdaptiveReviewEngine.reviewed(legacyCard, grade: .good, now: reviewDate)
        precondition(remembered.repetitions == legacyCard.repetitions + 1)
        precondition(remembered.stabilityDays > legacyCard.stabilityDays)
        precondition(remembered.dueDate > reviewDate)
        precondition(remembered.lastGradeRaw == ReviewGrade.good.rawValue)
        let forgotten = AdaptiveReviewEngine.reviewed(legacyCard, grade: .again, now: reviewDate)
        precondition(forgotten.lapses == 1)
        precondition(forgotten.repetitions == 0)
        precondition(forgotten.stabilityDays < legacyCard.stabilityDays)

        let initialKnowledge = MasteryEngine.updatedState(current: nil, itemID: "read-a0-morning-v1", score: 0.90, now: reviewDate)
        precondition(initialKnowledge.successes == 1)
        precondition(initialKnowledge.lapses == 0)
        precondition(initialKnowledge.nextReviewAt > reviewDate)
        let weakenedKnowledge = MasteryEngine.updatedState(current: initialKnowledge, itemID: initialKnowledge.itemID, score: 0.20, now: reviewDate.addingTimeInterval(86_400))
        precondition(weakenedKnowledge.lapses == 1)
        precondition(weakenedKnowledge.stabilityDays < initialKnowledge.stabilityDays)
        let mastery = MasteryEngine.masteryScore(initialKnowledge, at: reviewDate)
        precondition((0...1).contains(mastery))

        let writingPrompt = AdvancedSkillsLibrary.writingPrompts.first!
        let writing = WritingEvaluator.evaluate(
            text: "First, I wake up early because I have work. Then I eat breakfast. Finally, I leave home on time.",
            prompt: writingPrompt
        )
        precondition((0...1).contains(writing.overall))
        precondition(writing.wordCount > 10)
        precondition(!writing.detectedConnectors.isEmpty)

        let session = PracticeSessionRecord(
            id: "semantic-session",
            domain: .reading,
            sourceID: "read-a0-morning-v1",
            titleAr: "اختبار دلالي",
            level: .a0,
            score: 0.85,
            minutes: 6,
            createdAt: reviewDate,
            details: ["نجح"]
        )
        let progress = UserProgressSnapshot(
            activity: [DailyActivity(date: reviewDate.startOfDay, minutes: 6, exercises: 1, points: 25)],
            practiceSessions: [session],
            knowledgeStates: [initialKnowledge.itemID: initialKnowledge]
        )
        let pathway = LearningPathwayCatalog.progress(for: .foundations, snapshot: progress)
        precondition(pathway.totalMilestones == 5)
        precondition((0...1).contains(pathway.overallProgress))
        precondition((0...1).contains(pathway.currentMilestoneProgress))

        let report = AdvancedAnalyticsEngine.weeklyReport(progress: progress, dueReviewCount: 4, now: reviewDate)
        precondition(report.practiceSessions == 1)
        precondition(report.dueReviewCount == 4)
        precondition(!report.nextWeekActions.isEmpty)

        let exact = PronunciationAnalyzer.analyze(
            target: "I would like coffee please",
            recognized: "I would like coffee please",
            accent: .american,
            duration: 3,
            segments: []
        )
        precondition(exact.accuracy > 0.95)
        precondition(exact.completeness > 0.95)

        let memory = try JSONDecoder().decode(LearnerMemorySnapshot.self, from: Data("{}".utf8))
        precondition(memory.mistakes.isEmpty && memory.pronunciationReports.isEmpty)

        let repository = ProgressRepository(store: FileStore())
        await repository.recordPracticeSession(session)
        let storedProgress = await repository.snapshot()
        precondition(storedProgress.practiceSessions.contains { $0.id == session.id })
        precondition(storedProgress.knowledgeStates[session.sourceID] != nil)

        let plan = LearningPlanner.makePlan(
            catalog: catalog,
            progress: migratedProgress,
            dueCards: [],
            level: .a0,
            targetMinutes: 15,
            reducePressure: false,
            studyMode: .balanced,
            pathway: .foundations
        )
        precondition(plan.items.first?.kind == .lesson)
        precondition(plan.items.first?.referenceID == "a0-u1-l1")

        print("نجح الفحص الدلالي لنواة EnglishNova 0.4.0.")
        print("- فك ترميز 152 درسًا وترحيل بيانات قديمة")
        print("- 24 قراءة و24 استماع و24 كتابة")
        print("- ستة مسارات تعلم وخطة يومية متوافقة")
        print("- مراجعة تكيفية بالصعوبة والثبات والانتكاسات واحتمال التذكر")
        print("- محرك إتقان وتقرير أسبوعي وتقييم كتابة محلي")
        print("- حفظ جلسة مهارة وحالة إتقان فعليًا")
        print("- استمرار فحوص تحديد المستوى والنطق والمحتوى المتقدم")
    }
}
SWIFT

cd "$ROOT"
swiftc -parse-as-library -o "$TMP/validate" \
  EnglishNova/Domain/Models/CEFRLevel.swift \
  EnglishNova/Core/Utilities/Date+StartOfDay.swift \
  EnglishNova/Core/Utilities/StringSimilarity.swift \
  EnglishNova/Domain/Models/Exercise.swift \
  EnglishNova/Domain/Models/CurriculumModels.swift \
  EnglishNova/Domain/Models/PlacementModels.swift \
  EnglishNova/Domain/Models/LearningModels.swift \
  EnglishNova/Domain/Models/AdvancedLearningModels.swift \
  EnglishNova/Domain/Models/ProgressModels.swift \
  EnglishNova/Domain/Models/PracticeModels.swift \
  EnglishNova/Domain/Models/InteractiveStoryModels.swift \
  EnglishNova/Domain/Models/ReferenceModels.swift \
  EnglishNova/Domain/Models/TutorModels.swift \
  EnglishNova/Domain/Protocols/Repositories.swift \
  EnglishNova/Core/Persistence/FileStore.swift \
  EnglishNova/Data/Local/MasteryEngine.swift \
  EnglishNova/Data/Local/AdvancedSkillsLibrary.swift \
  EnglishNova/Data/Repositories/ProgressRepository.swift \
  EnglishNova/Data/Local/PlacementQuestionBank.swift \
  EnglishNova/Data/Local/AdaptivePlacementEngine.swift \
  EnglishNova/Data/Local/LearningPlanner.swift \
  EnglishNova/Data/Local/ConversationLibrary.swift \
  EnglishNova/Data/Local/InteractiveStoryLibrary.swift \
  "$TMP/SemanticValidation.swift"
mkdir -p "$TMP/home"
HOME="$TMP/home" ENGLISHNOVA_ROOT="$ROOT" "$TMP/validate"
