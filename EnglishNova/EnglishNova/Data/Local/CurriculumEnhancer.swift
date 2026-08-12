import Foundation

/// Applies editorial and pedagogical improvements to the bundled curriculum at load time.
/// The source JSON remains immutable; learners receive the refined in-memory catalog.
enum CurriculumEnhancer {
    static func enhance(_ source: CourseCatalog) -> CourseCatalog {
        var catalog = source
        catalog.levels = source.levels.map(enhanceLevel)
        return catalog
    }

    private static func enhanceLevel(_ source: CourseLevel) -> CourseLevel {
        var level = source
        level.titleAr = ArabicLearningCopy.polish(source.titleAr)
        level.descriptionAr = ArabicLearningCopy.polish(source.descriptionAr)
        level.units = source.units.map { enhanceUnit($0, level: source.level) }
        return level
    }

    private static func enhanceUnit(_ source: CourseUnit, level: CEFRLevel) -> CourseUnit {
        var unit = source
        unit.titleAr = ArabicLearningCopy.polish(source.titleAr)
        unit.descriptionAr = ArabicLearningCopy.polish(source.descriptionAr)
        unit.lessons = source.lessons.map { enhanceLesson($0, level: level) }
        return unit
    }

    private static func enhanceLesson(_ source: Lesson, level: CEFRLevel) -> Lesson {
        var lesson = source
        lesson.titleAr = ArabicLearningCopy.polish(source.titleAr)
        lesson.objectiveAr = ArabicLearningCopy.polish(source.objectiveAr)
        lesson.vocabulary = source.vocabulary.map(enhanceWord)
        lesson.exercises = source.exercises.map(enhanceExercise)
        lesson.exercises = ensureProductiveTransfer(
            in: lesson.exercises,
            vocabulary: lesson.vocabulary,
            level: level,
            lessonID: lesson.id
        )
        return lesson
    }

    private static func enhanceWord(_ source: VocabularyWord) -> VocabularyWord {
        var word = source
        word.arabic = ArabicLearningCopy.polish(source.arabic)
        word.exampleArabic = ArabicLearningCopy.polish(source.exampleArabic)
        return word
    }

    private static func enhanceExercise(_ source: Exercise) -> Exercise {
        var exercise = source
        exercise.promptAr = ArabicLearningCopy.polish(source.promptAr)
        exercise.explanationAr = ArabicLearningCopy.polish(source.explanationAr)
        exercise.accessibilityHint = ArabicLearningCopy.polish(source.accessibilityHint)
        return exercise
    }

    /// Recognition alone does not demonstrate usable language. If an older lesson
    /// contains no output task, append one short transfer task using material that
    /// is already taught in the lesson. This remains deterministic and offline.
    private static func ensureProductiveTransfer(
        in exercises: [Exercise],
        vocabulary: [VocabularyWord],
        level: CEFRLevel,
        lessonID: String
    ) -> [Exercise] {
        let productiveTypes: Set<ExerciseType> = [.speak, .translation, .arrangeWords, .fillBlank]
        guard !exercises.contains(where: { productiveTypes.contains($0.type) }),
              let word = vocabulary.first
        else { return exercises }

        let id = "\(lessonID)-productive-transfer"
        guard !exercises.contains(where: { $0.id == id }) else { return exercises }

        let englishExample = word.example.trimmingCharacters(in: .whitespacesAndNewlines)
        let arabicExample = word.exampleArabic.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = englishExample.isEmpty ? word.english : englishExample

        let transfer: Exercise
        switch level {
        case .a0, .a1:
            transfer = Exercise(
                id: id,
                type: .speak,
                promptAr: "استمع إلى النموذج، ثم قل العبارة بصوتك.",
                promptEn: target,
                answer: target,
                choices: nil,
                tokens: nil,
                explanationAr: "هنا تستخدم العبارة بنفسك بدل الاكتفاء بالتعرّف عليها.",
                accessibilityHint: "استمع إلى النموذج، ثم ابدأ التسجيل وكرر العبارة.",
                speechText: target,
                acceptableAnswers: nil
            )
        case .a2, .b1, .b2, .c1:
            if !arabicExample.isEmpty && !englishExample.isEmpty {
                transfer = Exercise(
                    id: id,
                    type: .translation,
                    promptAr: "ترجم إلى الإنجليزية من ذاكرتك: \(arabicExample)",
                    promptEn: nil,
                    answer: englishExample,
                    choices: nil,
                    tokens: nil,
                    explanationAr: "حاول صياغة الجملة أولًا، ثم قارنها بالإجابة.",
                    accessibilityHint: "اكتب الجملة بالإنجليزية من ذاكرتك.",
                    speechText: nil,
                    acceptableAnswers: nil
                )
            } else {
                transfer = Exercise(
                    id: id,
                    type: .speak,
                    promptAr: "قل العبارة بطريقتك، مع الحفاظ على معناها.",
                    promptEn: target,
                    answer: target,
                    choices: nil,
                    tokens: nil,
                    explanationAr: "اهتم بالوضوح والإيقاع، ولا تحاول تقليد الصوت حرفيًا.",
                    accessibilityHint: "استمع إلى النموذج، ثم كرر العبارة بصوت واضح.",
                    speechText: target,
                    acceptableAnswers: nil
                )
            }
        }
        return exercises + [transfer]
    }
}

/// Editorial pass for Arabic learning copy. It is intentionally conservative:
/// it fixes recurrent generated phrasing and spelling without touching English
/// answers, changing grammar rules, or inventing new teaching content.
enum ArabicLearningCopy {
    private static let exact: [String: String] = [
        "Hello تحية.": "Hello تعني «مرحبًا»، وتُستخدم للتحية.",
        "This للمفرد القريب.": "نستخدم This للإشارة إلى شيء مفرد قريب.",
        "How much تستخدم للسؤال عن السعر.": "نستخدم How much للسؤال عن السعر أو الكمية غير المعدودة.",
        "Yesterday يحتاج إلى الماضي.": "وجود Yesterday يدل عادةً على حدث وقع في الماضي.",
        "Interested in تركيب ثابت.": "تأتي Interested مع in في هذا الاستخدام.",
        "since مع نقطة بداية زمنية.": "نستخدم since مع نقطة بداية زمنية.",
        "faster صيغة المقارنة من fast.": "faster هي صيغة المقارنة من fast.",
        "deadline هو الموعد النهائي.": "deadline تعني الموعد النهائي.",
        "appointment تعني موعدًا محددًا.": "appointment تعني موعدًا محددًا مسبقًا.",
        "أجب هل تريد شيئًا آخر.": "أجب عن سؤال ما إذا كنت تريد شيئًا آخر.",
        "أداء جيد، وتستطيع أفضل": "جيد. راجع ما أخطأت فيه ثم حاول مرة أخرى.",
        "أداء جيد جدًا 👏": "جيد جدًا 👏",
        "أداء ممتاز! 🎉": "ممتاز! 🎉"
    ]

    private static let phraseReplacements: [(String, String)] = [
        ("قم باختيار", "اختر"),
        ("قم بإختيار", "اختر"),
        ("قم بترتيب", "رتّب"),
        ("قم بالاستماع إلى", "استمع إلى"),
        ("قم بالاستماع", "استمع"),
        ("قم بالنطق", "انطق"),
        ("قم بنطق", "انطق"),
        ("قم بملء الفراغ", "أكمل الفراغ"),
        ("قم بملء", "أكمل"),
        ("قم بترجمة", "ترجم"),
        ("قم بكتابة", "اكتب"),
        ("اختر الإجابة الصحيحة من الخيارات التالية", "اختر الإجابة الصحيحة"),
        ("اختر الخيار الصحيح من الخيارات التالية", "اختر الإجابة الصحيحة"),
        ("ترجم الجملة التالية إلى اللغة الإنجليزية", "ترجم الجملة التالية إلى الإنجليزية"),
        ("ترجم العبارة التالية إلى اللغة الإنجليزية", "ترجم العبارة التالية إلى الإنجليزية"),
        ("قل الجملة التالية بصوت عالٍ", "قل الجملة التالية بصوت واضح"),
        ("الهدف من هذا التمرين هو أن", "في هذا التمرين،"),
        ("الهدف من هذا التمرين هو", "هدف هذا التمرين"),
        ("هذا التمرين يساعدك على", "يساعدك هذا التمرين على"),
        ("يتم استخدام", "يُستخدم"),
        ("يتم استعمال", "يُستخدم"),
        ("من أجل أن", "لكي"),
        ("اللغة الانجليزية", "اللغة الإنجليزية"),
        ("اللغة العربيه", "اللغة العربية"),
        ("الإجابة الصحيح", "الإجابة الصحيحة"),
        ("إضغط", "اضغط"),
        ("إختار", "اختر"),
        ("إستمع", "استمع"),
        ("إستخدم", "استخدم"),
        ("إكتب", "اكتب"),
        ("جاري ", "جارٍ ")
    ]

    static func polish(_ input: String) -> String {
        guard !input.isEmpty else { return input }
        if let replacement = exact[input] { return replacement }

        var text = input
        for (bad, good) in phraseReplacements {
            text = text.replacingOccurrences(of: bad, with: good)
        }
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        text = text.replacingOccurrences(of: " ،", with: "،")
        text = text.replacingOccurrences(of: " .", with: ".")
        text = text.replacingOccurrences(of: " ؟", with: "؟")
        text = text.replacingOccurrences(of: " !", with: "!")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Lightweight quality metrics used by tests and diagnostics. These metrics do
/// not claim to measure CEFR certification; they catch curriculum regressions
/// such as a level becoming recognition-only or losing listening/output work.
struct CurriculumQualitySnapshot: Equatable {
    let lessonCount: Int
    let exerciseCount: Int
    let productiveExerciseCount: Int
    let listeningExerciseCount: Int
    let lessonsWithProductiveWork: Int

    var productiveShare: Double {
        guard exerciseCount > 0 else { return 0 }
        return Double(productiveExerciseCount) / Double(exerciseCount)
    }

    var productiveLessonCoverage: Double {
        guard lessonCount > 0 else { return 0 }
        return Double(lessonsWithProductiveWork) / Double(lessonCount)
    }
}

enum CurriculumQualityAudit {
    static func snapshot(for level: CourseLevel) -> CurriculumQualitySnapshot {
        let lessons = level.units.flatMap(\.lessons)
        let exercises = lessons.flatMap(\.exercises)
        let productive: Set<ExerciseType> = [.speak, .translation, .arrangeWords, .fillBlank]
        return CurriculumQualitySnapshot(
            lessonCount: lessons.count,
            exerciseCount: exercises.count,
            productiveExerciseCount: exercises.filter { productive.contains($0.type) }.count,
            listeningExerciseCount: exercises.filter { $0.type == .listenAndChoose }.count,
            lessonsWithProductiveWork: lessons.filter { lesson in
                lesson.exercises.contains { productive.contains($0.type) }
            }.count
        )
    }
}
