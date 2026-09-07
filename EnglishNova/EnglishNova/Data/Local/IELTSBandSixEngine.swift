import Foundation

/// A conservative, offline-first IELTS Academic preparation engine.
///
/// It deliberately separates training estimates from official IELTS results.
/// Objective sections use published raw-score anchors; productive sections use
/// local rubric signals and therefore receive lower confidence.
enum IELTSBandSixEngine {
    static let targetBand = 6.0
    static let minimumDailyMinutes = 180
    static let evidenceWindowDays = 56
    static let minimumSessionsPerSection = 4

    static func phase(for level: CEFRLevel) -> IELTSPreparationPhase {
        switch level {
        case .a0, .a1: return .foundation
        case .a2: return .bridge
        case .b1: return .examSkills
        case .b2, .c1: return .bandSixSimulation
        }
    }

    static func effectiveDailyTarget(configuredMinutes: Int) -> Int {
        max(minimumDailyMinutes, configuredMinutes)
    }

    static func dailyBlocks(
        level: CEFRLevel,
        progress: UserProgressSnapshot,
        dueCardCount: Int,
        date: Date = .now
    ) -> [IELTSStudyBlock] {
        let phase = phase(for: level)
        let day = Calendar.current.component(.weekday, from: date)

        if phase == .bandSixSimulation && day == 7 {
            return mockDayBlocks(date: date)
        }

        let recent = recentDomainAverages(progress: progress, before: date)
        let weakest = IELTSSection.allCases.min { lhs, rhs in
            (recent[lhs] ?? -1) < (recent[rhs] ?? -1)
        }

        var blocks = baseBlocks(for: phase, dueCardCount: dueCardCount, day: day)
        if let weakest,
           let weakIndex = blocks.firstIndex(where: { $0.area.rawValue == weakest.rawValue }),
           let donorIndex = strongestTransferDonor(in: blocks, excluding: weakIndex) {
            let transfer = min(10, max(0, blocks[donorIndex].minutes - 20))
            if transfer > 0 {
                blocks[weakIndex] = replacingMinutes(blocks[weakIndex], with: blocks[weakIndex].minutes + transfer)
                blocks[donorIndex] = replacingMinutes(blocks[donorIndex], with: blocks[donorIndex].minutes - transfer)
            }
        }

        precondition(blocks.reduce(0) { $0 + $1.minutes } == minimumDailyMinutes)
        return blocks
    }

    static func makeDailyLearningPlan(
        level: CEFRLevel,
        progress: UserProgressSnapshot,
        dueCardCount: Int,
        configuredMinutes: Int,
        nextLesson: Lesson?,
        date: Date = .now
    ) -> DailyLearningPlan {
        var blocks = dailyBlocks(level: level, progress: progress, dueCardCount: dueCardCount, date: date)
        let target = effectiveDailyTarget(configuredMinutes: configuredMinutes)
        if target > minimumDailyMinutes, let final = blocks.indices.last {
            blocks[final] = replacingMinutes(blocks[final], with: blocks[final].minutes + target - minimumDailyMinutes)
        }

        let dayKey = Int(date.startOfDay.timeIntervalSince1970)
        let items = blocks.enumerated().map { index, block in
            let lessonTitle = nextLesson?.titleAr ?? block.titleAr
            return LearningPlanItem(
                id: "ielts-\(dayKey)-\(index)-\(block.area.rawValue)",
                kind: block.area.activityKind,
                titleAr: block.area == .course ? lessonTitle : block.titleAr,
                subtitleAr: block.detailAr,
                estimatedMinutes: block.minutes,
                referenceID: "ielts:\(block.area.rawValue)",
                isCompleted: false
            )
        }
        let logged = progress.activity
            .filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
            .reduce(0) { $0 + max(0, $1.minutes) }
        return DailyLearningPlan(date: date, targetMinutes: target, items: items, loggedMinutes: logged)
    }

    static func readiness(
        level: CEFRLevel,
        progress: UserProgressSnapshot,
        now: Date = .now
    ) -> IELTSReadinessSnapshot {
        let cutoff = Calendar.current.date(byAdding: .day, value: -evidenceWindowDays, to: now) ?? .distantPast
        let recentSessions = progress.practiceSessions.filter { $0.createdAt >= cutoff && $0.createdAt <= now }
        var estimates: [IELTSSectionEstimate] = []

        for section in IELTSSection.allCases {
            let sessions = recentSessions
                .filter { $0.domain == section.practiceDomain }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(8)
            let values = sessions.map { min(1, max(0, $0.score)) }
            let average = conservativeAverage(values)
            let activeDays = Set(sessions.map { $0.createdAt.startOfDay }).count
            let isRecent = sessions.first.map { now.timeIntervalSince($0.createdAt) <= 21 * 86_400 } ?? false
            let sufficient = values.count >= minimumSessionsPerSection && activeDays >= 2 && isRecent
            let band = average.map { trainingBand(for: section, performance: $0) }
            let stability = stabilityConfidence(values)
            let evidence = min(1, Double(values.count) / 8)
            let confidence = min(1, evidence * 0.65 + stability * 0.35) * (section == .writing || section == .speaking ? 0.82 : 1)
            estimates.append(IELTSSectionEstimate(
                section: section,
                estimatedBand: band,
                confidence: confidence,
                evidenceCount: values.count,
                recentAverage: average,
                isSufficient: sufficient
            ))
        }

        let complete = estimates.allSatisfy(\.isSufficient)
        let bands = estimates.compactMap(\.estimatedBand)
        let overall = complete && bands.count == IELTSSection.allCases.count
            ? officialOverallBand(sectionBands: bands)
            : nil
        var blockers: [String] = []
        for estimate in estimates where !estimate.isSufficient {
            let remaining = max(0, minimumSessionsPerSection - estimate.evidenceCount)
            blockers.append("\(estimate.section.titleAr): أكمل \(remaining) جلسات مقيسة إضافية في يومين مختلفين على الأقل.")
        }
        for estimate in estimates where estimate.isSufficient && (estimate.estimatedBand ?? 0) < 5.5 {
            blockers.append("\(estimate.section.titleAr): التقدير المحافظ أقل من 5.5؛ عالج أخطاء آخر أربع جلسات.")
        }
        if blockers.isEmpty, let overall, overall < targetBand {
            blockers.append("المتوسط التدريبي لم يصل إلى 6.0 بعد. ركّز على أضعف قسم قبل إعادة المحاكاة.")
        }

        let confidence = estimates.isEmpty ? 0 : estimates.map(\.confidence).reduce(0, +) / Double(estimates.count)
        let ready = complete
            && (overall ?? 0) >= targetBand
            && estimates.allSatisfy { ($0.estimatedBand ?? 0) >= 5.5 }
            && confidence >= 0.60
        return IELTSReadinessSnapshot(
            phase: phase(for: level),
            targetBand: targetBand,
            sectionEstimates: estimates,
            overallBand: overall,
            confidence: confidence,
            isReadyForBandSix: ready,
            blockersAr: blockers
        )
    }

    /// Published IELTS anchors are used for the whole-band thresholds. Half-band
    /// values between those anchors are conservative practice estimates.
    static func objectiveBand(correct: Int, section: IELTSSection) -> Double {
        let score = min(40, max(0, correct))
        let thresholds: [(Int, Double)]
        switch section {
        case .listening:
            thresholds = [(39, 9), (37, 8.5), (35, 8), (32, 7.5), (30, 7), (26, 6.5), (23, 6), (18, 5.5), (16, 5), (13, 4.5), (11, 4), (0, 0)]
        case .reading:
            thresholds = [(40, 9), (39, 8.5), (35, 8), (33, 7.5), (30, 7), (27, 6.5), (23, 6), (19, 5.5), (15, 5), (13, 4.5), (10, 4), (0, 0)]
        case .writing, .speaking:
            return 0
        }
        return thresholds.first(where: { score >= $0.0 })?.1 ?? 0
    }

    static func officialOverallBand(sectionBands: [Double]) -> Double? {
        guard sectionBands.count == 4, sectionBands.allSatisfy({ (0...9).contains($0) }) else { return nil }
        let average = sectionBands.reduce(0, +) / 4
        return (average * 2).rounded() / 2
    }

    /// Inverse of the productive-skill readiness anchors. This keeps a local
    /// writing estimate labelled Band 6 aligned with the Band 6 readiness
    /// threshold instead of accidentally lowering it during persistence.
    static func practicePerformance(forEstimatedBand band: Double) -> Double {
        let anchors: [(Double, Double)] = [(1, 0), (3.5, 0.30), (4.5, 0.45), (5.5, 0.58), (6, 0.68), (7, 0.80), (8, 0.90), (9, 1)]
        let clamped = min(9, max(1, band))
        for index in 1..<anchors.count where clamped <= anchors[index].0 {
            let lower = anchors[index - 1]
            let upper = anchors[index]
            let ratio = (clamped - lower.0) / max(0.001, upper.0 - lower.0)
            return min(1, max(0, lower.1 + ratio * (upper.1 - lower.1)))
        }
        return 1
    }

    static func evaluateWriting(text: String, task: IELTSWritingTask) -> IELTSWritingEvaluation {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = tokens(normalized)
        let lower = normalized.lowercased()
        let sentences = normalized.split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let paragraphs = normalized.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let connectors = ["however", "therefore", "although", "while", "whereas", "moreover", "in addition", "for example", "as a result", "on the other hand", "overall"]
        let complexMarkers = ["although", "because", "while", "whereas", "which", "that", "if", "when", "despite"]
        let connectorCount = connectors.filter { lower.contains($0) }.count
        let complexCount = complexMarkers.filter { lower.contains($0) }.count
        let focusMatches = task.focusWords.filter { lower.contains($0.lowercased()) }.count
        let lengthRatio = min(1, Double(words.count) / Double(task.type.minimumWords))
        let positionOrOverview: Bool
        switch task.type {
        case .academicTask1:
            positionOrOverview = ["overall", "in general", "the main", "the most", "the least"].contains { lower.contains($0) }
        case .task2:
            positionOrOverview = ["i believe", "i agree", "i disagree", "in my view", "this essay", "should"].contains { lower.contains($0) }
        }

        let taskResponse = min(1,
            lengthRatio * 0.58
            + min(1, Double(focusMatches) / Double(max(1, min(5, task.focusWords.count)))) * 0.22
            + (positionOrOverview ? 0.20 : 0)
        )
        let paragraphTarget = task.type == .academicTask1 ? 3.0 : 4.0
        let coherence = min(1,
            min(1, Double(paragraphs.count) / paragraphTarget) * 0.55
            + min(1, Double(connectorCount) / 5) * 0.45
        )

        let contentWords = words.filter { $0.count > 3 && !commonWords.contains($0) }
        let uniqueRatio = contentWords.isEmpty ? 0 : Double(Set(contentWords).count) / Double(contentWords.count)
        let repeated = Dictionary(grouping: contentWords, by: { $0 }).values.filter { $0.count >= 5 }.count
        let lexical = min(1, max(0, uniqueRatio * 0.78 + min(1, Double(contentWords.filter { $0.count >= 8 }.count) / 12) * 0.22 - Double(repeated) * 0.04))

        let capitalStarts = sentences.filter { $0.first?.isUppercase == true }.count
        let sentenceAccuracySignal = sentences.isEmpty ? 0 : Double(capitalStarts) / Double(sentences.count)
        let obviousErrors = obviousGrammarPatterns.filter { lower.contains($0) }.count
        let grammar = min(1, max(0,
            sentenceAccuracySignal * 0.48
            + min(1, Double(complexCount) / 5) * 0.32
            + min(1, Double(sentences.count) / 10) * 0.20
            - Double(obviousErrors) * 0.08
        ))

        let raw = (taskResponse + coherence + lexical + grammar) / 4
        var band = min(6.5, max(1, (raw * 6.2 + 1).rounded(toPlaces: 1)))
        if words.count < task.type.minimumWords { band = min(band, 5.0) }

        var strengths: [String] = []
        if lengthRatio >= 1 { strengths.append("وصلت إلى الحد الأدنى للكلمات.") }
        if positionOrOverview { strengths.append(task.type == .academicTask1 ? "أضفت نظرة عامة واضحة." : "قدمت موقفًا مباشرًا من السؤال.") }
        if coherence >= 0.68 { strengths.append("التقسيم والروابط يساعدان على متابعة الفكرة.") }
        if lexical >= 0.68 { strengths.append("لديك تنوع معجمي مناسب لمسودة تدريبية.") }
        if strengths.isEmpty { strengths.append("أنجزت مسودة يمكن قياسها وتحسينها بدل الاكتفاء بالتخطيط.") }

        var improvements: [String] = []
        if words.count < task.type.minimumWords { improvements.append("أضف \(task.type.minimumWords - words.count) كلمة على الأقل.") }
        if !positionOrOverview { improvements.append(task.type == .academicTask1 ? "أضف نظرة عامة تلخص الاتجاهات الرئيسية دون تفاصيل كثيرة." : "اذكر موقفك بوضوح وابقَ ثابتًا عليه حتى الخاتمة.") }
        if paragraphs.count < Int(paragraphTarget) { improvements.append("قسّم الإجابة إلى \(Int(paragraphTarget)) فقرات وظيفية على الأقل.") }
        if focusMatches < min(3, task.focusWords.count) { improvements.append("غطِّ عناصر السؤال والبيانات الرئيسية بدل الكتابة العامة.") }
        if complexCount < 2 { improvements.append("استخدم جملًا مركبة مضبوطة، مثل although وwhile وbecause.") }
        if obviousErrors > 0 { improvements.append("راجع أخطاء التطابق والزمن الظاهرة قبل اعتماد المسودة.") }
        if improvements.isEmpty { improvements.append("أعد الكتابة مرة واحدة مع أمثلة أدق وروابط أقل آلية.") }

        return IELTSWritingEvaluation(
            wordCount: words.count,
            taskResponse: taskResponse,
            coherenceAndCohesion: coherence,
            lexicalResource: lexical,
            grammaticalRangeAndAccuracy: grammar,
            estimatedBand: band,
            strengthsAr: strengths,
            improvementsAr: improvements,
            limitationsAr: "التقدير محلي ومحافظ، ولا يستطيع التحقق من كل دلالة أو خطأ نحوي مثل مصحح IELTS البشري. الحد الأعلى المحلي 6.5."
        )
    }

    static let roadmap: [IELTSRoadmapStage] = [
        .init(id: "weeks-1-6", weekRangeAr: "الأسابيع 1–6", titleAr: "A0: لغة النجاة", outcomeAr: "جمل صحيحة قصيرة و600 كلمة عالية التكرار وفهم تعليمات بسيطة.", checkpointAr: "اختبار A0/A1 بنسبة 75٪ في جلستين."),
        .init(id: "weeks-7-12", weekRangeAr: "الأسابيع 7–12", titleAr: "A1: الحياة اليومية", outcomeAr: "سرد الروتين والماضي القريب وقراءة نصوص قصيرة دون ترجمة كل كلمة.", checkpointAr: "كتابة 100 كلمة وتحدث دقيقتين مع بقاء المعنى واضحًا."),
        .init(id: "weeks-13-18", weekRangeAr: "الأسابيع 13–18", titleAr: "A2: الجسر الأكاديمي", outcomeAr: "فقرات مترابطة واستماع أطول ومفردات التعليم والعمل والمجتمع.", checkpointAr: "أربع مهارات بمتوسط تدريبي 65٪ أو أعلى."),
        .init(id: "weeks-19-26", weekRangeAr: "الأسابيع 19–26", titleAr: "B1: مهارات IELTS", outcomeAr: "إتقان أنواع الأسئلة وبناء Task 1 وTask 2 وأجزاء Speaking الثلاثة.", checkpointAr: "23 من 40 في قراءة واستماع تدريبيين مع كتابة مكتملة الطول."),
        .init(id: "weeks-27-32", weekRangeAr: "الأسابيع 27–32", titleAr: "B1+ إلى B2", outcomeAr: "العمل تحت الوقت ورفع الدقة والترابط بدل حفظ قوالب جامدة.", checkpointAr: "تقدير محافظ 5.5 أو أعلى في كل قسم."),
        .init(id: "weeks-33-36", weekRangeAr: "الأسابيع 33–36", titleAr: "تثبيت Band 6", outcomeAr: "محاكاة كاملة أسبوعيًا وتحليل كل خطأ وإعادة المهمة الأضعف.", checkpointAr: "تقدير 6.0 عام مع 5.5 على الأقل في كل قسم وأدلة حديثة كافية.")
    ]

    static let writingTasks: [IELTSWritingTask] = [
        .init(
            id: "ielts-w1-transport",
            type: .academicTask1,
            prompt: "The table shows the percentage of commuters using four forms of transport in a city in 2005, 2015 and 2025. Summarise the information by selecting and reporting the main features, and make comparisons where relevant.",
            accessibleSourceDescription: "Percent of commuters. Car: 2005 58%, 2015 49%, 2025 41%. Bus: 2005 22%, 2015 24%, 2025 26%. Rail: 2005 12%, 2015 17%, 2025 22%. Bicycle: 2005 8%, 2015 10%, 2025 11%.",
            focusWords: ["car", "bus", "rail", "bicycle", "percentage", "increase", "decrease"],
            checklistAr: ["مقدمة تعيد صياغة السؤال.", "نظرة عامة تذكر أكبر اتجاهين.", "مقارنات مدعومة بأرقام دقيقة.", "لا تذكر أسبابًا غير موجودة في البيانات."]
        ),
        .init(
            id: "ielts-w1-energy",
            type: .academicTask1,
            prompt: "The table compares household electricity sources in three regions in 2010 and 2025. Summarise the main features and make relevant comparisons.",
            accessibleSourceDescription: "Share of household electricity. North: renewable 28% in 2010 and 52% in 2025; fossil fuel 72% and 48%. Central: renewable 18% and 35%; fossil fuel 82% and 65%. South: renewable 41% and 67%; fossil fuel 59% and 33%.",
            focusWords: ["renewable", "fossil", "north", "central", "south", "rose", "fell"],
            checklistAr: ["اذكر الاتجاه العام أولًا.", "قارن المناطق بدل سرد كل رقم منفصلًا.", "استخدم الماضي لوصف 2010 و2025.", "تحقق من جميع النسب."]
        ),
        .init(
            id: "ielts-w1-library",
            type: .academicTask1,
            prompt: "The table gives the number of visits to a public library by age group in four months. Summarise the information and compare the main features.",
            accessibleSourceDescription: "Visits. Ages 16–24: January 1,200; April 1,450; July 1,900; October 1,500. Ages 25–44: 1,600; 1,700; 1,850; 1,920. Ages 45 and over: 1,050; 1,100; 980; 1,140.",
            focusWords: ["visits", "age group", "highest", "lowest", "increased", "declined"],
            checklistAr: ["حدد الأعلى والأدنى.", "اذكر التغير عبر الزمن.", "اجمع التفاصيل المتشابهة في فقرة.", "لا تعطِ رأيًا شخصيًا."]
        ),
        .init(
            id: "ielts-w1-water",
            type: .academicTask1,
            prompt: "The table shows average daily household water use per person in four countries in 2000 and 2020. Summarise the information and make comparisons.",
            accessibleSourceDescription: "Litres per person per day. Country A: 310 in 2000 and 270 in 2020. Country B: 220 and 235. Country C: 180 and 160. Country D: 140 and 205.",
            focusWords: ["litres", "daily", "household", "higher", "lower", "increase", "decrease"],
            checklistAr: ["استخدم وحدة القياس الصحيحة.", "قدم نظرة عامة واضحة.", "قارن البداية والنهاية.", "لا تفسر أسباب التغير."]
        ),
        .init(
            id: "ielts-w1-employment",
            type: .academicTask1,
            prompt: "The table compares employment in five sectors in a town in 2000 and 2025. Summarise the main features and make relevant comparisons.",
            accessibleSourceDescription: "Number of workers. Manufacturing: 8,400 in 2000 and 5,100 in 2025. Healthcare: 3,200 and 6,700. Retail: 5,600 and 5,900. Technology: 1,100 and 4,800. Agriculture: 2,700 and 1,400.",
            focusWords: ["employment", "workers", "sector", "manufacturing", "healthcare", "technology"],
            checklistAr: ["حدد أكبر تغيرين.", "قارن القطاعات الصاعدة والهابطة.", "استخدم أرقامًا مختارة لا جميع الأرقام آليًا.", "اختم دون رأي."]
        ),
        .init(
            id: "ielts-w1-recycling",
            type: .academicTask1,
            prompt: "The table shows recycling rates for paper, glass and plastic in one country from 2010 to 2025. Summarise the information by selecting and reporting the main features.",
            accessibleSourceDescription: "Recycling rate. Paper: 62% in 2010, 68% in 2015, 74% in 2020, 78% in 2025. Glass: 48%, 55%, 63%, 69%. Plastic: 12%, 17%, 23%, 31%.",
            focusWords: ["recycling", "paper", "glass", "plastic", "rate", "trend"],
            checklistAr: ["اذكر أن الأنواع الثلاثة ارتفعت.", "بين الفجوة بين الأعلى والأدنى.", "استخدم لغة اتجاهات متنوعة.", "راجع دقة السنوات والنسب."]
        ),
        .init(
            id: "ielts-w2-remote-work",
            type: .task2,
            prompt: "Some people believe working from home benefits employees and employers, while others think it creates more problems than it solves. Discuss both views and give your own opinion.",
            accessibleSourceDescription: nil,
            focusWords: ["employees", "employers", "productivity", "communication", "flexibility", "opinion"],
            checklistAr: ["ناقش الرأيين.", "اذكر موقفك بوضوح.", "ادعم كل فكرة بسبب ومثال.", "اكتب خاتمة تجيب عن السؤال."]
        ),
        .init(
            id: "ielts-w2-university",
            type: .task2,
            prompt: "Universities should focus more on practical employment skills than on theoretical knowledge. To what extent do you agree or disagree?",
            accessibleSourceDescription: nil,
            focusWords: ["universities", "practical", "employment", "theoretical", "knowledge", "agree"],
            checklistAr: ["حدد درجة موافقتك.", "ابنِ حجتين مختلفتين.", "استخدم مثالًا محددًا.", "لا تغيّر موقفك في الخاتمة."]
        ),
        .init(
            id: "ielts-w2-cities",
            type: .task2,
            prompt: "Many cities are becoming more crowded. What problems does this cause, and what measures could governments take to address them?",
            accessibleSourceDescription: nil,
            focusWords: ["cities", "crowded", "housing", "transport", "government", "measures"],
            checklistAr: ["اشرح مشكلتين على الأقل.", "اربط كل حل بالمشكلة المناسبة.", "قدم تفاصيل قابلة للتطبيق.", "تجنب القوائم غير المترابطة."]
        ),
        .init(
            id: "ielts-w2-technology",
            type: .task2,
            prompt: "Technology has made people less socially connected despite making communication easier. Do the advantages outweigh the disadvantages?",
            accessibleSourceDescription: nil,
            focusWords: ["technology", "communication", "connected", "advantages", "disadvantages", "relationships"],
            checklistAr: ["قارن وزن المزايا والعيوب.", "اذكر معيار المقارنة.", "استخدم أمثلة ذات صلة.", "أجب عن outweigh مباشرة."]
        ),
        .init(
            id: "ielts-w2-environment",
            type: .task2,
            prompt: "Environmental problems should be solved by international organisations rather than individual countries. To what extent do you agree or disagree?",
            accessibleSourceDescription: nil,
            focusWords: ["environmental", "international", "countries", "cooperation", "policy", "responsibility"],
            checklistAr: ["وضح دور كل مستوى.", "اختر موقفًا قابلًا للدفاع.", "أضف مثالًا واقعيًا دون اختلاق إحصاءات.", "اربط الخاتمة بالمقدمة."]
        ),
        .init(
            id: "ielts-w2-public-transport",
            type: .task2,
            prompt: "Some people think public transport should be free for everyone. Discuss the advantages and disadvantages and give your opinion.",
            accessibleSourceDescription: nil,
            focusWords: ["public transport", "free", "cost", "traffic", "access", "opinion"],
            checklistAr: ["غطِّ المزايا والعيوب.", "ميّز بين المجانية والدعم.", "ادعم الرأي بسبب واضح.", "راجع تكرار الكلمات."]
        )
    ]

    // MARK: - Internal helpers

    private static let commonWords: Set<String> = ["this", "that", "with", "from", "have", "will", "would", "there", "their", "about", "which", "when", "were", "been", "into", "than", "then", "also", "some", "more"]
    private static let obviousGrammarPatterns = ["i is ", "i are ", "he have ", "she have ", "they is ", "people is ", "did not went", "more better"]

    private static func baseBlocks(for phase: IELTSPreparationPhase, dueCardCount: Int, day: Int) -> [IELTSStudyBlock] {
        switch phase {
        case .foundation:
            return [
                block("course", .course, "الدرس المتسلسل", "تعلم قاعدة ومفردات في سياق ثم أجب عن جميع تمارين الدرس.", 45),
                block("vocabulary", .vocabulary, "مفردات عالية التكرار", dueCardCount > 0 ? "راجع الكلمات المستحقة ثم أضف خمس كلمات من درس اليوم." : "تعلم كلمات اليوم داخل جمل، لا كترجمة منفصلة.", 25),
                block("listening", .listening, "استماع تأسيسي", "استمع مرة للمعنى، ثم مرة للتفاصيل، ثم تحقق من النص.", 30),
                block("speaking", .speaking, "نطق وإجابة قصيرة", "كرر النموذج ثم أجب بجمل كاملة وسجل محاولة واحدة على الأقل.", 25),
                block("reading", .reading, "قراءة موجهة", "اقرأ نصًا مناسبًا لمستواك وحدد الفكرة والكلمات الدالة.", 25),
                block("writing", .writing, "بناء الجملة والفقرة", "اكتب جملًا من إنتاجك مستخدمًا قاعدة اليوم.", 20),
                block("correction", .correction, "إغلاق أخطاء اليوم", "صحح الأخطاء بصوتك أو بكتابة الجملة الصحيحة من الذاكرة.", 10, breakAfter: 0)
            ]
        case .bridge:
            return [
                block("course", .course, "درس A2 المتسلسل", "ثبّت الأزمنة والروابط التي تحتاجها قبل مهام IELTS الطويلة.", 30),
                block("reading", .reading, "قراءة وفهم", "تدرب على الفكرة والتفاصيل ومعنى الكلمة من السياق.", 30),
                block("listening", .listening, "استماع مع تدوين", "دوّن الكلمات المفتاحية ثم أجب دون كشف النص أولًا.", 30),
                block("writing", .writing, "فقرة أكاديمية", day.isMultiple(of: 2) ? "اكتب فقرة رأي مع سبب ومثال." : "صف بيانات نصية بمقارنات واضحة.", 30),
                block("speaking", .speaking, "تحدث ممتد", "أجب ثم أضف السبب والمثال والنتيجة في دقيقتين.", 30),
                block("vocabulary", .vocabulary, "قواعد ومفردات", "راجع التراكيب المتكررة والكلمات المستحقة.", 20),
                block("correction", .correction, "دفتر الأخطاء", "اختر ثلاثة أخطاء وأنتج الصيغة الصحيحة دون نسخ.", 10, breakAfter: 0)
            ]
        case .examSkills:
            return [
                block("reading", .reading, "IELTS Reading", "حل تحت وقت محدد ثم اشرح الدليل النصي لكل إجابة.", 35),
                block("listening", .listening, "IELTS Listening", "أجب من استماع واحد وراجع التهجئة وصيغة الإجابة.", 35),
                block("writing", .writing, day.isMultiple(of: 2) ? "Writing Task 2" : "Academic Writing Task 1", "اكتب تحت الوقت ثم أعد فقرة واحدة بعد التقييم.", 40),
                block("speaking", .speaking, "IELTS Speaking", "تدرب على الأجزاء الثلاثة دون حفظ إجابة كاملة.", 30),
                block("vocabulary", .vocabulary, "لغة أكاديمية دقيقة", "راجع collocations وتصحيح الكلمات المستخدمة في غير موضعها.", 20),
                block("correction", .correction, "تحليل الأخطاء", "صنف الخطأ وحدد سببه واكتب قاعدة تمنع تكراره.", 20, breakAfter: 0)
            ]
        case .bandSixSimulation:
            return [
                block("reading", .reading, "قراءة تحت الوقت", "استهدف 23 إجابة صحيحة من 40 ثم راجع الدليل، لا الحرف فقط.", 35),
                block("listening", .listening, "استماع تحت الوقت", "استهدف 23 من 40 مع تدقيق المفرد والجمع والتهجئة.", 35),
                block("writing", .writing, day.isMultiple(of: 2) ? "Writing Task 2" : "Academic Writing Task 1", "نفذ مهمة كاملة ثم راجع المعايير الأربعة.", 45),
                block("speaking", .speaking, "محاكاة Speaking", "سجل جلسة كاملة ثم أعد أضعف إجابة فقط.", 35),
                block("vocabulary", .vocabulary, "مفردات من الأخطاء", "راجع الكلمات والتراكيب التي أخفقت فيها هذا الأسبوع.", 10),
                block("correction", .correction, "سجل الخطأ والتحسين", "حوّل أخطاء اليوم إلى خطة الجلسة التالية.", 20, breakAfter: 0)
            ]
        }
    }

    private static func mockDayBlocks(date: Date) -> [IELTSStudyBlock] {
        [
            block("mock-listening", .listening, "محاكاة Listening", "أكمل قسمًا تجريبيًا من 40 سؤالًا دون إيقاف التسجيل.", 40),
            block("mock-reading", .reading, "محاكاة Academic Reading", "أكمل 40 سؤالًا تحت الوقت وسجل الإجابات قبل المراجعة.", 60),
            block("mock-writing", .writing, "محاكاة Writing", "نفذ مهمة محددة تحت الوقت ثم راجعها بالمعايير الأربعة.", 45),
            block("mock-speaking", .speaking, "محاكاة Speaking", "أكمل الأجزاء الثلاثة بتسجيل صوتي واحد.", 20),
            block("mock-review", .correction, "تقرير المحاكاة", "سجل الدرجة وسبب كل خطأ وأولوية الأسبوع القادم.", 15, breakAfter: 0)
        ]
    }

    private static func block(_ id: String, _ area: IELTSStudyArea, _ title: String, _ detail: String, _ minutes: Int, breakAfter: Int = 5) -> IELTSStudyBlock {
        IELTSStudyBlock(id: id, area: area, titleAr: title, detailAr: detail, minutes: minutes, breakAfterMinutes: breakAfter)
    }

    private static func replacingMinutes(_ block: IELTSStudyBlock, with minutes: Int) -> IELTSStudyBlock {
        IELTSStudyBlock(id: block.id, area: block.area, titleAr: block.titleAr, detailAr: block.detailAr, minutes: minutes, breakAfterMinutes: block.breakAfterMinutes)
    }

    private static func strongestTransferDonor(in blocks: [IELTSStudyBlock], excluding excluded: Int) -> Int? {
        blocks.indices
            .filter { $0 != excluded && blocks[$0].minutes > 20 && blocks[$0].area != .correction }
            .max { blocks[$0].minutes < blocks[$1].minutes }
    }

    private static func recentDomainAverages(progress: UserProgressSnapshot, before date: Date) -> [IELTSSection: Double] {
        var output: [IELTSSection: Double] = [:]
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: date) ?? .distantPast
        for section in IELTSSection.allCases {
            let values = progress.practiceSessions
                .filter { $0.domain == section.practiceDomain && $0.createdAt >= cutoff && $0.createdAt <= date }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(6)
                .map(\.score)
            if !values.isEmpty { output[section] = values.reduce(0, +) / Double(values.count) }
        }
        return output
    }

    private static func conservativeAverage(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let weights = values.indices.map { pow(0.86, Double($0)) }
        let weighted = zip(values, weights).reduce(0) { $0 + $1.0 * $1.1 } / weights.reduce(0, +)
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return min(1, max(0, weighted - min(0.08, sqrt(variance) * 0.18)))
    }

    private static func stabilityConfidence(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 0.2 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return max(0, min(1, 1 - sqrt(variance) * 2.4))
    }

    private static func trainingBand(for section: IELTSSection, performance: Double) -> Double {
        if section == .listening || section == .reading {
            return objectiveBand(correct: Int((performance * 40).rounded(.down)), section: section)
        }
        let anchors: [(Double, Double)] = [(0, 1), (0.30, 3.5), (0.45, 4.5), (0.58, 5.5), (0.68, 6), (0.80, 7), (0.90, 8), (1, 9)]
        for index in 1..<anchors.count where performance <= anchors[index].0 {
            let lower = anchors[index - 1]
            let upper = anchors[index]
            let ratio = (performance - lower.0) / max(0.001, upper.0 - lower.0)
            let value = lower.1 + ratio * (upper.1 - lower.1)
            return (value * 2).rounded(.down) / 2
        }
        return 9
    }

    private static func tokens(_ value: String) -> [String] {
        value.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map(String.init)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
