import Foundation

enum AdaptiveReviewEngine {
    static let targetRetention = 0.90

    static func retrievability(for card: ReviewCard, at date: Date = .now) -> Double {
        guard let last = card.lastReviewedAt else { return 0 }
        let elapsedDays = max(0, date.timeIntervalSince(last) / 86_400)
        let stability = max(0.15, card.stabilityDays)
        return exp(log(targetRetention) * elapsedDays / stability)
    }

    static func reviewed(_ original: ReviewCard, grade: ReviewGrade, now: Date = .now) -> ReviewCard {
        var card = original
        let priorRetrievability = retrievability(for: card, at: now)
        let gradeAdjustment: Double
        switch grade {
        case .again: gradeAdjustment = 1.2
        case .hard: gradeAdjustment = 0.35
        case .good: gradeAdjustment = -0.20
        case .easy: gradeAdjustment = -0.75
        }

        card.difficulty = min(10, max(1, card.difficulty + gradeAdjustment))
        if grade == .again {
            card.repetitions = 0
            card.lapses += 1
            card.stabilityDays = max(0.20, card.stabilityDays * 0.34)
        } else {
            let baseMultiplier: Double
            switch grade {
            case .again: baseMultiplier = 0.34
            case .hard: baseMultiplier = 1.25
            case .good: baseMultiplier = 1.90
            case .easy: baseMultiplier = 2.75
            }
            let memoryBonus = 1 + max(0, 1 - priorRetrievability) * 0.55
            let difficultyPenalty = 1 - ((card.difficulty - 5) * 0.035)
            card.stabilityDays = max(0.25, card.stabilityDays * baseMultiplier * memoryBonus * difficultyPenalty)
            card.repetitions += 1
        }

        let interval: Double
        switch grade {
        case .again: interval = 10.0 / 1_440.0
        case .hard: interval = max(0.5, card.stabilityDays * 0.72)
        case .good: interval = max(1, card.stabilityDays)
        case .easy: interval = max(3, card.stabilityDays * 1.32)
        }

        card.scheduledIntervalDays = min(365, interval)
        card.intervalDays = max(0, Int(interval.rounded()))
        card.lastReviewedAt = now
        card.dueDate = now.addingTimeInterval(interval * 86_400)
        card.lastGradeRaw = grade.rawValue
        card.easeFactor = max(1.3, min(3.2, 3.05 - card.difficulty * 0.17))
        card.confidence = min(1, max(0, 0.20 + Double(card.repetitions) * 0.075 - Double(card.lapses) * 0.045 + card.stabilityDays / 90))
        return card
    }
}

enum MasteryEngine {
    static func updatedState(
        current: KnowledgeState?,
        itemID: String,
        score: Double,
        now: Date = .now
    ) -> KnowledgeState {
        var state = current ?? KnowledgeState(itemID: itemID)
        let normalized = min(1, max(0, score))
        if normalized >= 0.70 {
            state.successes += 1
            state.difficulty = max(1, state.difficulty - (normalized - 0.65) * 0.8)
            state.stabilityDays = max(1, state.stabilityDays * (1.35 + normalized * 0.75))
        } else {
            state.lapses += 1
            state.difficulty = min(10, state.difficulty + (0.75 - normalized) * 1.4)
            state.stabilityDays = max(0.35, state.stabilityDays * (0.45 + normalized * 0.30))
        }
        state.lastReviewedAt = now
        state.nextReviewAt = now.addingTimeInterval(min(180, state.stabilityDays) * 86_400)
        return state
    }

    static func masteryScore(_ state: KnowledgeState, at date: Date = .now) -> Double {
        guard let last = state.lastReviewedAt else { return 0 }
        let elapsed = max(0, date.timeIntervalSince(last) / 86_400)
        let retention = exp(log(0.9) * elapsed / max(0.2, state.stabilityDays))
        let experience = min(1, Double(state.successes) / 8)
        let lapsePenalty = min(0.35, Double(state.lapses) * 0.04)
        return min(1, max(0, retention * 0.65 + experience * 0.35 - lapsePenalty))
    }
}

enum LearningPathwayCatalog {
    static let all: [LearningPathwayDefinition] = LearningPathwayID.allCases.map(definition)

    static func definition(for id: LearningPathwayID) -> LearningPathwayDefinition {
        switch id {
        case .foundations:
            return pathway(id, "من الحروف والعبارات الأساسية إلى استخدام جمل A2 بثقة.", .a2, 24, [.vocabulary, .grammar, .listening, .speaking])
        case .dailyFluency:
            return pathway(id, "استماع وردود سريعة ومواقف الحياة اليومية حتى مستوى B1.", .b1, 20, [.listening, .speaking, .vocabulary, .reading])
        case .academicIELTS:
            return pathway(id, "قراءة أكاديمية وكتابة منظمة وتحدث ممتد حتى B2 أو C1.", .c1, 36, [.reading, .writing, .listening, .speaking])
        case .stepMastery:
            return pathway(id, "تثبيت القواعد والمفردات والقراءة تحت ضغط الوقت.", .b2, 24, [.grammar, .vocabulary, .reading, .listening])
        case .careerEnglish:
            return pathway(id, "البريد والاجتماعات والعروض والمقابلات المهنية.", .b2, 28, [.writing, .speaking, .listening, .reading])
        case .legalGovernance:
            return pathway(id, "صياغة قانونية وحوكمة ومخاطر وامتثال باللغة الإنجليزية.", .c1, 32, [.reading, .writing, .speaking, .vocabulary])
        }
    }

    static func progress(
        for id: LearningPathwayID,
        snapshot: UserProgressSnapshot
    ) -> LearningPathwayProgress {
        let pathway = definition(for: id)
        let sessions = snapshot.practiceSessions
        var completed = 0
        var currentProgress = 0.0
        var current: LearningPathwayMilestone?
        for milestone in pathway.milestones {
            let relevant = sessions.filter { milestone.requiredDomains.contains($0.domain) }
            let countProgress = min(1, Double(relevant.count) / Double(max(1, milestone.requiredSessions)))
            let average = relevant.isEmpty ? 0 : relevant.map(\.score).reduce(0, +) / Double(relevant.count)
            let scoreProgress = min(1, average / max(0.01, milestone.requiredAverageScore))
            let value = countProgress * 0.65 + scoreProgress * 0.35
            if value >= 0.999 {
                completed += 1
            } else if current == nil {
                current = milestone
                currentProgress = value
            }
        }
        return LearningPathwayProgress(
            pathway: pathway,
            completedMilestones: completed,
            totalMilestones: pathway.milestones.count,
            overallProgress: Double(completed) / Double(max(1, pathway.milestones.count)),
            currentMilestone: current,
            currentMilestoneProgress: currentProgress
        )
    }

    private static func pathway(
        _ id: LearningPathwayID,
        _ detail: String,
        _ target: CEFRLevel,
        _ weeks: Int,
        _ domains: [AdvancedSkillDomain]
    ) -> LearningPathwayDefinition {
        let titles = ["إرساء الأساس", "الاستخدام الموجّه", "الأداء المستقل", "محاكاة الهدف", "مرحلة الإتقان"]
        let sessions = [8, 18, 35, 55, 80]
        let scores = [0.58, 0.66, 0.74, 0.80, 0.86]
        let milestones = titles.indices.map { index in
            LearningPathwayMilestone(
                id: "\(id.rawValue)-m\(index + 1)",
                titleAr: titles[index],
                detailAr: "أكمل أنشطة متنوعة في \(domains.map(\.titleAr).joined(separator: "، ")) بمتوسط متصاعد.",
                requiredSessions: sessions[index],
                requiredAverageScore: scores[index],
                requiredDomains: domains
            )
        }
        return LearningPathwayDefinition(
            id: id,
            titleAr: id.titleAr,
            detailAr: detail,
            targetLevel: target,
            estimatedWeeks: weeks,
            milestones: milestones
        )
    }
}

enum WritingEvaluator {
    private static let connectors = ["because", "however", "therefore", "although", "first", "second", "finally", "while", "moreover", "in addition", "for example", "on the other hand"]

    static func evaluate(text: String, prompt: WritingPrompt) -> WritingEvaluation {
        let words = tokenize(text)
        let sentences = text.split(whereSeparator: { ".!?".contains($0) }).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let lower = text.lowercased()
        let foundConnectors = connectors.filter { lower.contains($0) }
        let frequencies = Dictionary(grouping: words.filter { $0.count > 3 }, by: { $0 }).mapValues(\.count)
        let repeated = frequencies.filter { $0.value >= 4 }.sorted { $0.value > $1.value }.prefix(5).map(\.key)
        let wordTarget = min(1, Double(words.count) / Double(max(1, prompt.minimumWords)))
        let keywordMatches = prompt.suggestedWords.filter { lower.contains($0.lowercased()) }.count
        let task = min(1, wordTarget * 0.75 + min(1, Double(keywordMatches) / Double(max(1, min(4, prompt.suggestedWords.count)))) * 0.25)
        let organization = min(1, Double(sentences.count) / 5 * 0.55 + Double(foundConnectors.count) / 4 * 0.45)
        let uniqueRatio = words.isEmpty ? 0 : Double(Set(words).count) / Double(words.count)
        let averageWordLength = words.isEmpty ? 0 : Double(words.map(\.count).reduce(0, +)) / Double(words.count)
        let range = min(1, uniqueRatio * 0.75 + min(1, averageWordLength / 6) * 0.25)
        let startsCapital = sentences.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).first?.isUppercase == true }.count
        let mechanics = sentences.isEmpty ? 0 : min(1, Double(startsCapital) / Double(sentences.count) * 0.7 + (text.last.map { ".!?".contains($0) } == true ? 0.3 : 0))
        let overall = task * 0.35 + organization * 0.25 + range * 0.25 + mechanics * 0.15

        var strengths: [String] = []
        if task >= 0.75 { strengths.append("استجبت للمهمة بطول ومحتوى مناسبين.") }
        if organization >= 0.70 { strengths.append("استخدمت انتقالات تساعد القارئ على متابعة الفكرة.") }
        if range >= 0.72 { strengths.append("التنوع المعجمي جيد بالنسبة إلى طول النص.") }
        if mechanics >= 0.80 { strengths.append("علامات نهاية الجمل والحروف الكبيرة منضبطة غالبًا.") }
        if strengths.isEmpty { strengths.append("بدأت مسودة قابلة للتحسين، وهذا أهم من انتظار الصياغة المثالية.") }

        var improvements: [String] = []
        if words.count < prompt.minimumWords { improvements.append("أضف \(prompt.minimumWords - words.count) كلمة تقريبًا لتغطية المهمة.") }
        if foundConnectors.count < 2 { improvements.append("اربط الأفكار بكلمات مثل because وhowever وfinally.") }
        if sentences.count < 3 { improvements.append("قسّم الفكرة إلى ثلاث جمل واضحة على الأقل.") }
        if !repeated.isEmpty { improvements.append("قلّل تكرار: \(repeated.joined(separator: "، ")).") }
        if mechanics < 0.70 { improvements.append("راجع الحرف الكبير في بداية الجملة وعلامة النهاية.") }
        if improvements.isEmpty { improvements.append("جرّب إعادة الكتابة بصياغة أكثر اختصارًا ثم قارن النسختين.") }

        return WritingEvaluation(
            wordCount: words.count,
            taskAchievement: task,
            organization: organization,
            languageRange: range,
            mechanics: mechanics,
            overall: min(1, max(0, overall)),
            strengthsAr: strengths,
            improvementsAr: improvements,
            detectedConnectors: foundConnectors,
            repeatedWords: repeated
        )
    }

    private static func tokenize(_ value: String) -> [String] {
        value.lowercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "'" }
            .map(String.init)
    }
}

enum AdvancedAnalyticsEngine {
    static func weeklyReport(
        progress: UserProgressSnapshot,
        dueReviewCount: Int,
        now: Date = .now
    ) -> WeeklyLearningReport {
        let end = now.startOfDay
        let start = Calendar.current.date(byAdding: .day, value: -6, to: end) ?? end
        let activity = progress.activity.filter { $0.date.startOfDay >= start && $0.date.startOfDay <= end }
        let sessions = progress.practiceSessions.filter { $0.createdAt >= start && $0.createdAt < end.addingTimeInterval(86_400) }
        let activeDays = Set(activity.map { $0.date.startOfDay } + sessions.map { $0.createdAt.startOfDay }).count
        let average = sessions.isEmpty ? 0 : sessions.map(\.score).reduce(0, +) / Double(sessions.count)
        let grouped = Dictionary(grouping: sessions, by: \.domain).mapValues { values in
            values.map(\.score).reduce(0, +) / Double(values.count)
        }
        let strongest = grouped.max { $0.value < $1.value }?.key
        let focus = grouped.min { $0.value < $1.value }?.key
        let completedLessons = progress.lessons.values.filter { lesson in
            guard let date = lesson.completedAt else { return false }
            return date >= start && date < end.addingTimeInterval(86_400)
        }.count
        let narrative: String
        if activeDays >= 5 {
            narrative = "أسبوع ثابت وقوي. الاستمرارية هنا أهم من جلسة طويلة منفردة."
        } else if activeDays >= 3 {
            narrative = "الإيقاع جيد، ويحتاج يومين قصيرين إضافيين حتى تصبح اللغة عادة أسبوعية."
        } else {
            narrative = "النشاط متقطع. ثلاث جلسات من عشر دقائق ستكون أكثر فائدة من انتظار يوم مثالي."
        }
        var actions: [String] = []
        if let focus { actions.append("نفّذ جلستين في مهارة \(focus.titleAr).") }
        if dueReviewCount > 0 { actions.append("راجع \(min(dueReviewCount, 25)) بطاقة مستحقة على دفعتين.") }
        if sessions.filter({ $0.domain == .writing }).isEmpty { actions.append("اكتب مسودة واحدة ثم أعد كتابتها بعد قراءة التقييم.") }
        if sessions.filter({ $0.domain == .listening }).isEmpty { actions.append("نفّذ مقطعي استماع، الأول دون نص والثاني مع كشف النص في النهاية.") }
        if actions.count < 3 { actions.append("حافظ على أربع جلسات قصيرة موزعة بدل جلسة واحدة ثقيلة.") }

        let activityMinutes = activity.reduce(0) { $0 + $1.minutes }
        let sessionMinutes = sessions.reduce(0) { $0 + $1.minutes }
        return WeeklyLearningReport(
            startDate: start,
            endDate: end,
            activeDays: activeDays,
            totalMinutes: max(activityMinutes, sessionMinutes),
            completedLessons: completedLessons,
            practiceSessions: sessions.count,
            averagePracticeScore: average,
            dueReviewCount: dueReviewCount,
            strongestDomain: strongest,
            focusDomain: focus,
            narrativeAr: narrative,
            nextWeekActions: Array(actions.prefix(4))
        )
    }
}
