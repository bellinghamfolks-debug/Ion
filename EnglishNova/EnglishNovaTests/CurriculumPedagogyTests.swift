import XCTest
@testable import EnglishNova

final class CurriculumPedagogyTests: XCTestCase {
    func testEveryLessonHasProductiveWorkAfterEnhancement() throws {
        let catalog = try BundledContentLoader().loadCatalog()
        for level in catalog.levels {
            let snapshot = CurriculumQualityAudit.snapshot(for: level)
            XCTAssertGreaterThan(snapshot.lessonCount, 0)
            XCTAssertEqual(
                snapshot.lessonsWithProductiveWork,
                snapshot.lessonCount,
                "كل درس في \(level.level.rawValue) يجب أن يتضمن استخدامًا فعليًا للغة"
            )
        }
    }

    func testCurriculumStillCoversAllRuntimeCEFRLevels() throws {
        let catalog = try BundledContentLoader().loadCatalog()
        XCTAssertEqual(Set(catalog.levels.map(\.level)), Set(CEFRLevel.allCases))
    }

    func testArabicEditorialPassRemovesKnownMachinePatterns() {
        let samples = [
            "قم باختيار الإجابة الصحيحة من الخيارات التالية",
            "قم بالاستماع إلى الجملة",
            "قم بترجمة الجملة التالية إلى اللغة الإنجليزية",
            "إضغط ثم إستمع"
        ].map(ArabicLearningCopy.polish)

        for text in samples {
            XCTAssertFalse(text.contains("قم باختيار"))
            XCTAssertFalse(text.contains("قم بالاستماع"))
            XCTAssertFalse(text.contains("قم بترجمة"))
            XCTAssertFalse(text.contains("إضغط"))
            XCTAssertFalse(text.contains("إستمع"))
        }
    }

    func testAddedProductiveTaskIsStableAndUnique() {
        let exercise = Exercise(
            id: "x", type: .multipleChoice, promptAr: "اختر", promptEn: nil,
            answer: "Hello", choices: ["Hello", "Bye"], tokens: nil,
            explanationAr: "", accessibilityHint: "", speechText: nil,
            acceptableAnswers: nil
        )
        let word = VocabularyWord(
            id: "w", english: "hello", arabic: "مرحبًا",
            example: "Hello, Sara.", exampleArabic: "مرحبًا يا سارة.",
            partOfSpeech: "interjection", phonetic: nil
        )
        let lesson = Lesson(
            id: "lesson", order: 1, titleAr: "التحية", titleEn: "Greetings",
            objectiveAr: "استخدام التحية", estimatedMinutes: 5, points: 10,
            vocabulary: [word], exercises: [exercise]
        )
        let unit = CourseUnit(
            id: "unit", order: 1, titleAr: "وحدة", titleEn: "Unit",
            descriptionAr: "", icon: "book", lessons: [lesson]
        )
        let level = CourseLevel(
            id: "a0", level: .a0, titleAr: "تمهيدي", titleEn: "Starter",
            descriptionAr: "", units: [unit]
        )
        let input = CourseCatalog(version: 1, levels: [level])
        let once = CurriculumEnhancer.enhance(input)
        let twice = CurriculumEnhancer.enhance(once)
        let onceExercises = once.levels[0].units[0].lessons[0].exercises
        let twiceExercises = twice.levels[0].units[0].lessons[0].exercises
        XCTAssertEqual(onceExercises.count, 2)
        XCTAssertEqual(twiceExercises.count, 2)
        XCTAssertEqual(twiceExercises.last?.id, "lesson-productive-transfer")
    }
}
