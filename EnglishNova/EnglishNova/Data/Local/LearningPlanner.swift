import Foundation

enum LearningPlanner {
    static func makePlan(
        catalog: CourseCatalog,
        progress: UserProgressSnapshot,
        dueCards: [ReviewCard],
        level: CEFRLevel,
        targetMinutes: Int,
        reducePressure: Bool,
        studyMode: StudyMode = .balanced,
        pathway: LearningPathwayID = .foundations,
        date: Date = .now
    ) -> DailyLearningPlan {
        let effectiveTarget = reducePressure ? min(targetMinutes, 10) : targetMinutes
        let lessons = catalog.levels.first(where: { $0.level == level })?.units.flatMap(\.lessons) ?? []
        let incomplete = lessons.filter { progress.lessons[$0.id]?.completedAt == nil }
        let nextLesson = incomplete.first ?? lessons.first
        var items: [LearningPlanItem] = []

        if let nextLesson {
            items.append(LearningPlanItem(
                id: "lesson-\(nextLesson.id)",
                kind: .lesson,
                titleAr: nextLesson.titleAr,
                subtitleAr: "\(nextLesson.estimatedMinutes) دقائق، \(nextLesson.vocabulary.count) كلمات جديدة",
                estimatedMinutes: min(nextLesson.estimatedMinutes, effectiveTarget),
                referenceID: nextLesson.id,
                isCompleted: progress.lessons[nextLesson.id]?.completedAt != nil
            ))
        }

        if !dueCards.isEmpty && items.reduce(0, { $0 + $1.estimatedMinutes }) < effectiveTarget {
            let reviewMinutes = min(7, max(3, effectiveTarget / 3))
            items.append(LearningPlanItem(
                id: "review-\(date.startOfDay.timeIntervalSince1970)",
                kind: .review,
                titleAr: "راجع \(min(dueCards.count, 15)) كلمة مستحقة",
                subtitleAr: "مراجعة ذكية قصيرة لتثبيت الذاكرة",
                estimatedMinutes: reviewMinutes,
                referenceID: nil,
                isCompleted: false
            ))
        }

        let used = items.reduce(0) { $0 + $1.estimatedMinutes }
        if used < effectiveTarget {
            let kind = priorityActivity(
                mode: studyMode,
                pathway: pathway,
                progress: progress,
                date: date
            )
            items.append(LearningPlanItem(
                id: "skill-\(kind.rawValue)-\(date.startOfDay.timeIntervalSince1970)",
                kind: kind,
                titleAr: activityTitle(for: kind),
                subtitleAr: "اختير لمسار \(pathway.titleAr) ووضع \(studyMode.titleAr).",
                estimatedMinutes: min(8, max(2, effectiveTarget - used)),
                referenceID: nil,
                isCompleted: false
            ))
        }

        return DailyLearningPlan(date: date, targetMinutes: effectiveTarget, items: items)
    }

    private static func priorityActivity(
        mode: StudyMode,
        pathway: LearningPathwayID,
        progress: UserProgressSnapshot,
        date: Date
    ) -> LearningActivityKind {
        switch mode {
        case .exam:
            return Calendar.current.component(.day, from: date).isMultiple(of: 2) ? .reading : .exam
        case .conversation:
            return (progress.skills[.listening]?.accuracy ?? 0) < 0.70 ? .listening : .conversation
        case .career:
            return Calendar.current.component(.day, from: date).isMultiple(of: 2) ? .writing : .conversation
        case .calm:
            return .listening
        case .balanced:
            if pathway == .academicIELTS || pathway == .stepMastery { return .reading }
            if pathway == .careerEnglish || pathway == .legalGovernance { return .writing }
            return (progress.skills[.listening]?.accuracy ?? 0) > 0.65 ? .pronunciation : .listening
        }
    }

    private static func activityTitle(for kind: LearningActivityKind) -> String {
        switch kind {
        case .lesson: return "درس جديد"
        case .review: return "مراجعة ذكية"
        case .listening: return "استماع مركز"
        case .pronunciation: return "دقيقة نطق واضحة"
        case .story: return "قصة متدرجة"
        case .conversation: return "ردود محادثة فورية"
        case .reading: return "نص وفهم عميق"
        case .writing: return "مسودة كتابة قصيرة"
        case .exam: return "محاكاة اختبار مركزة"
        }
    }

    static func insights(
        progress: UserProgressSnapshot,
        dueCards: [ReviewCard],
        now: Date = .now
    ) -> LearningInsights {
        let lessons = Array(progress.lessons.values)
        let completed = lessons.filter { $0.completedAt != nil }
        let attempts = lessons.reduce(0) { $0 + $1.attempts }
        let score = lessons.isEmpty ? 0 : lessons.reduce(0) { $0 + $1.bestScore } / Double(lessons.count)
        let totalMinutes = progress.activity.reduce(0) { $0 + $1.minutes }
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -29, to: now.startOfDay) ?? now
        let activeDays = Set(progress.activity.filter { $0.date >= thirtyDaysAgo }.map { $0.date.startOfDay }).count
        let practiced = progress.skills.values.filter { $0.attempts > 0 }
        let strongest = practiced.max { $0.accuracy < $1.accuracy }
        let focus = practiced.min { $0.accuracy < $1.accuracy }

        var cards: [LearningInsight] = [
            LearningInsight(id: "consistency", titleAr: "الاستمرارية", valueAr: "\(activeDays) يومًا", detailAr: "عدد الأيام النشطة خلال آخر 30 يومًا.", systemImage: "calendar.badge.checkmark"),
            LearningInsight(id: "lessons", titleAr: "الدروس المكتملة", valueAr: "\(completed.count)", detailAr: "كل درس مكتمل هو لبنة في طلاقتك.", systemImage: "checkmark.seal.fill"),
            LearningInsight(id: "minutes", titleAr: "وقت التعلّم", valueAr: "\(totalMinutes) دقيقة", detailAr: "الوقت المسجل داخل الأنشطة التعليمية.", systemImage: "clock.fill")
        ]
        if let focus {
            cards.append(LearningInsight(id: "focus", titleAr: "بوصلة التركيز", valueAr: focus.skill.titleAr, detailAr: "دقتها الحالية \(Int(focus.accuracy * 100))٪، لذا تستحق نشاطًا إضافيًا قصيرًا.", systemImage: focus.skill.systemImage))
        }

        return LearningInsights(
            totalMinutes: totalMinutes,
            completedLessons: completed.count,
            totalAttempts: attempts,
            averageLessonScore: score,
            dueVocabulary: dueCards.count,
            strongestSkill: strongest,
            focusSkill: focus,
            activeDaysLast30: activeDays,
            insights: cards
        )
    }
}

// MARK: - Batch 3 personalization engine

enum PersonalizationEngine {
    static func recommendations(
        progress: UserProgressSnapshot,
        memory: LearnerMemorySnapshot,
        dueCards: [ReviewCard]
    ) -> [PersonalizedRecommendation] {
        var items: [PersonalizedRecommendation] = []

        let recentReports = memory.pronunciationReports.prefix(10)
        if !recentReports.isEmpty {
            let average = recentReports.map(\.overall).reduce(0, +) / Double(recentReports.count)
            let weakWords = frequentWeakWords(in: Array(recentReports))
            if average < 0.76 {
                let detail = weakWords.isEmpty
                    ? "متوسط وضوح النطق في المحاولات الأخيرة أقل من الهدف."
                    : "ركّز اليوم على: \(weakWords.prefix(3).joined(separator: "، "))."
                items.append(.init(
                    id: "pronunciation-focus",
                    titleAr: "جلسة نطق مركزة",
                    detailAr: detail,
                    systemImage: "waveform.and.mic",
                    destination: .pronunciation,
                    priority: 100
                ))
            }
        }

        let unresolved = memory.mistakes.filter { !$0.resolved }
        if !unresolved.isEmpty {
            let category = mostFrequent(unresolved.map(\.category)) ?? "اللغة"
            items.append(.init(
                id: "mistakes-focus",
                titleAr: "دفتر الأخطاء",
                detailAr: "لديك \(unresolved.count) ملاحظة غير محسومة، وأكثرها في \(category).",
                systemImage: "exclamationmark.bubble.fill",
                destination: .mistakes,
                priority: 95
            ))
        }

        if dueCards.count >= 5 {
            items.append(.init(
                id: "review-focus",
                titleAr: "مراجعة متباعدة",
                detailAr: "هناك \(dueCards.count) كلمة مستحقة اليوم. مراجعتها الآن تمنع تسربها من الذاكرة.",
                systemImage: "rectangle.stack.fill",
                destination: .review,
                priority: 85
            ))
        }

        let practical = progress.skills[.practicalCommunication]
        if practical == nil || (practical?.attempts ?? 0) < 5 || (practical?.accuracy ?? 0) < 0.7 {
            items.append(.init(
                id: "conversation-focus",
                titleAr: "محادثة واقعية",
                detailAr: "تدريب قصير على الرد الفوري سيحوّل المعرفة من حفظ إلى استخدام.",
                systemImage: "person.2.wave.2.fill",
                destination: .conversation,
                priority: 75
            ))
        }

        if memory.examAttempts.isEmpty {
            items.append(.init(
                id: "exam-baseline",
                titleAr: "اختبار تدريبي قصير",
                detailAr: "نفّذ جلسة STEP أو IELTS لتكوين خط أساس أدق لخطة التعلم.",
                systemImage: "doc.text.magnifyingglass",
                destination: .exam,
                priority: 55
            ))
        }

        if items.isEmpty {
            items.append(.init(
                id: "continue-learning",
                titleAr: "استمر في المسار الحالي",
                detailAr: "لا تظهر فجوة حرجة الآن. واصل الدرس التالي ثم أجرِ محادثة قصيرة لتثبيت ما تعلمته.",
                systemImage: "graduationcap.fill",
                destination: .lesson,
                priority: 40
            ))
        }

        return items.sorted { $0.priority > $1.priority }
    }

    static func weaknessSummary(memory: LearnerMemorySnapshot) -> [String] {
        var lines: [String] = []
        let unresolved = memory.mistakes.filter { !$0.resolved }
        for category in groupedCounts(unresolved.map(\.category)).prefix(3) {
            lines.append("\(category.0): \(category.1) ملاحظات")
        }
        let words = frequentWeakWords(in: Array(memory.pronunciationReports.prefix(20)))
        if !words.isEmpty { lines.append("كلمات نطق متكررة: \(words.prefix(5).joined(separator: "، "))") }
        if let latest = memory.examAttempts.first {
            lines.append("آخر نتيجة \(latest.track.titleAr): \(Int(latest.score * 100))٪")
        }
        return lines
    }

    private static func frequentWeakWords(in reports: [PronunciationReport]) -> [String] {
        let words = reports.flatMap { report in
            report.words.filter { $0.issue == .substituted || $0.issue == .omitted || $0.issue == .close }.map(\.expected)
        }.filter { !$0.isEmpty }
        return groupedCounts(words).map(\.0)
    }

    private static func mostFrequent(_ values: [String]) -> String? {
        groupedCounts(values).first?.0
    }

    private static func groupedCounts(_ values: [String]) -> [(String, Int)] {
        Dictionary(grouping: values, by: { $0 })
            .map { ($0.key, $0.value.count) }
            .sorted { lhs, rhs in
                lhs.1 == rhs.1 ? lhs.0 < rhs.0 : lhs.1 > rhs.1
            }
    }
}
