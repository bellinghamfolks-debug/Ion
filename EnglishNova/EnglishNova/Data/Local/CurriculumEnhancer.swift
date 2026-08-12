import Foundation

/// Applies editorial and pedagogical improvements to the effective curriculum.
/// The transformation is deterministic, offline and level-aware: higher CEFR
/// levels require progressively more productive language evidence rather than
/// simply swapping in harder vocabulary.
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
        lesson.vocabulary = source.vocabulary
            .map(enhanceWord)
            .filter { !isWeakAdvancedVocabulary($0, level: level) }
        lesson.exercises = source.exercises.map(enhanceExercise)
        lesson.exercises = ensureLevelAppropriateTransfer(
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

    /// Removes obvious generator artefacts from advanced vocabulary without
    /// deleting legitimate function words used by a grammar lesson. We only
    /// remove entries whose Arabic gloss itself identifies them as filler.
    private static func isWeakAdvancedVocabulary(_ word: VocabularyWord, level: CEFRLevel) -> Bool {
        guard level == .b2 || level == .c1 else { return false }
        let gloss = word.arabic.lowercased()
        let generatorMarkers = [
            "كلمة من المثال", "كلمة في المثال", "بداية الجملة", "نهاية الجملة",
            "أداة من المثال", "جزء من المثال", "كلمة مستخدمة في المثال"
        ]
        return generatorMarkers.contains { gloss.contains($0) }
    }

    /// Required productive evidence rises with the level. A0/A1 need one short
    /// output task; A2/B1 need two; B2/C1 need three. This prevents advanced
    /// lessons from being mostly recognition exercises with harder vocabulary.
    private static func ensureLevelAppropriateTransfer(
        in exercises: [Exercise],
        vocabulary: [VocabularyWord],
        level: CEFRLevel,
        lessonID: String
    ) -> [Exercise] {
        let productiveTypes: Set<ExerciseType> = [.speak, .translation, .arrangeWords, .fillBlank]
        let required = CurriculumRigorAudit.requiredProductiveTasks(for: level)
        let existing = exercises.filter { productiveTypes.contains($0.type) }.count
        guard existing < required, !vocabulary.isEmpty else { return exercises }

        var result = exercises
        var missing = required - existing
        var slot = 0
        let candidates = vocabulary.filter {
            !$0.english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        while missing > 0 && slot < max(required * 2, candidates.count) {
            let word = candidates[slot % candidates.count]
            let id = "\(lessonID)-transfer-\(slot + 1)"
            slot += 1
            guard !result.contains(where: { $0.id == id }) else { continue }

            let englishExample = word.example.trimmingCharacters(in: .whitespacesAndNewlines)
            let arabicExample = word.exampleArabic.trimmingCharacters(in: .whitespacesAndNewlines)
            let target = englishExample.isEmpty ? word.english : englishExample

            let exercise: Exercise
            if slot.isMultiple(of: 2), !arabicExample.isEmpty, !englishExample.isEmpty {
                exercise = Exercise(
                    id: id,
                    type: .translation,
                    promptAr: transferTranslationPrompt(level: level, arabicExample: arabicExample),
                    promptEn: nil,
                    answer: englishExample,
                    choices: nil,
                    tokens: nil,
                    explanationAr: transferExplanation(level: level),
                    accessibilityHint: "اكتب إجابتك بالإنجليزية من دون الرجوع إلى المثال أولًا.",
                    speechText: nil,
                    acceptableAnswers: nil
                )
            } else {
                exercise = Exercise(
                    id: id,
                    type: .speak,
                    promptAr: transferSpeakingPrompt(level: level),
                    promptEn: target,
                    answer: target,
                    choices: nil,
                    tokens: nil,
                    explanationAr: transferExplanation(level: level),
                    accessibilityHint: "استمع عند الحاجة، ثم سجّل إجابتك بصوت واضح.",
                    speechText: target,
                    acceptableAnswers: nil
                )
            }
            result.append(exercise)
            missing -= 1
        }
        return result
    }

    private static func transferTranslationPrompt(level: CEFRLevel, arabicExample: String) -> String {
        switch level {
        case .a0, .a1:
            return "ترجم العبارة القصيرة إلى الإنجليزية: \(arabicExample)"
        case .a2:
            return "اكتب الجملة بالإنجليزية من ذاكرتك: \(arabicExample)"
        case .b1:
            return "عبّر عن المعنى التالي بالإنجليزية بجملة كاملة: \(arabicExample)"
        case .b2:
            return "صغ المعنى التالي بالإنجليزية بدقة، مع الحفاظ على العلاقة بين الأفكار: \(arabicExample)"
        case .c1:
            return "قدّم صياغة إنجليزية دقيقة وطبيعية للمعنى التالي، مع الانتباه إلى النبرة والدقة: \(arabicExample)"
        }
    }

    private static func transferSpeakingPrompt(level: CEFRLevel) -> String {
        switch level {
        case .a0, .a1: return "استمع إلى النموذج، ثم قل العبارة بصوتك."
        case .a2: return "قل الجملة بصوت واضح من دون قراءة كل كلمة حرفيًا إن استطعت."
        case .b1: return "قل الفكرة بطلاقة، وركّز على المعنى قبل تقليد النموذج حرفيًا."
        case .b2: return "قدّم العبارة بنبرة طبيعية وواضحة، ثم حاول قولها مرة ثانية بإيقاعك أنت."
        case .c1: return "قدّم العبارة كأنك تستخدمها في نقاش حقيقي، مع وضوح النبرة والترابط."
        }
    }

    private static func transferExplanation(level: CEFRLevel) -> String {
        switch level {
        case .a0, .a1: return "الهدف أن تنتقل من التعرّف على العبارة إلى استخدامها بنفسك."
        case .a2: return "استرجاع الجملة من الذاكرة أقوى من اختيارها من قائمة جاهزة."
        case .b1: return "يركز هذا الجزء على تحويل المعرفة إلى استخدام مستقل في جملة كاملة."
        case .b2: return "في هذا المستوى نحتاج إلى دقة في المعنى إلى جانب صحة الشكل."
        case .c1: return "المستوى المتقدم يتطلب استخدامًا دقيقًا وطبيعيًا للغة، لا مجرد التعرّف على الإجابة الصحيحة."
        }
    }
}

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
        ("قم باختيار", "اختر"), ("قم بإختيار", "اختر"), ("قم بترتيب", "رتّب"),
        ("قم بالاستماع إلى", "استمع إلى"), ("قم بالاستماع", "استمع"),
        ("قم بالنطق", "انطق"), ("قم بنطق", "انطق"),
        ("قم بملء الفراغ", "أكمل الفراغ"), ("قم بملء", "أكمل"),
        ("قم بترجمة", "ترجم"), ("قم بكتابة", "اكتب"),
        ("اختر الإجابة الصحيحة من الخيارات التالية", "اختر الإجابة الصحيحة"),
        ("اختر الخيار الصحيح من الخيارات التالية", "اختر الإجابة الصحيحة"),
        ("ترجم الجملة التالية إلى اللغة الإنجليزية", "ترجم الجملة التالية إلى الإنجليزية"),
        ("ترجم العبارة التالية إلى اللغة الإنجليزية", "ترجم العبارة التالية إلى الإنجليزية"),
        ("قل الجملة التالية بصوت عالٍ", "قل الجملة التالية بصوت واضح"),
        ("الهدف من هذا التمرين هو أن", "في هذا التمرين،"),
        ("الهدف من هذا التمرين هو", "هدف هذا التمرين"),
        ("هذا التمرين يساعدك على", "يساعدك هذا التمرين على"),
        ("يتم استخدام", "يُستخدم"), ("يتم استعمال", "يُستخدم"), ("من أجل أن", "لكي"),
        ("اللغة الانجليزية", "اللغة الإنجليزية"), ("اللغة العربيه", "اللغة العربية"),
        ("الإجابة الصحيح", "الإجابة الصحيحة"), ("إضغط", "اضغط"), ("إختار", "اختر"),
        ("إستمع", "استمع"), ("إستخدم", "استخدم"), ("إكتب", "اكتب"), ("جاري ", "جارٍ ")
    ]

    static func polish(_ input: String) -> String {
        guard !input.isEmpty else { return input }
        if let replacement = exact[input] { return replacement }
        var text = input
        for (bad, good) in phraseReplacements { text = text.replacingOccurrences(of: bad, with: good) }
        while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
        text = text.replacingOccurrences(of: " ،", with: "،")
        text = text.replacingOccurrences(of: " .", with: ".")
        text = text.replacingOccurrences(of: " ؟", with: "؟")
        text = text.replacingOccurrences(of: " !", with: "!")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

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
            lessonsWithProductiveWork: lessons.filter { lesson in lesson.exercises.contains { productive.contains($0.type) } }.count
        )
    }
}

enum CurriculumRigorAudit {
    static func requiredProductiveTasks(for level: CEFRLevel) -> Int {
        switch level {
        case .a0, .a1: return 1
        case .a2, .b1: return 2
        case .b2, .c1: return 3
        }
    }

    static func lessonsBelowProductiveFloor(in level: CourseLevel) -> [String] {
        let productive: Set<ExerciseType> = [.speak, .translation, .arrangeWords, .fillBlank]
        let required = requiredProductiveTasks(for: level.level)
        return level.units.flatMap(\.lessons).filter { lesson in
            lesson.exercises.filter { productive.contains($0.type) }.count < required
        }.map(\.id)
    }
}
