import Foundation

enum ConversationLibrary {
    static let scenarios: [ConversationScenario] = [
        scenario("cafe", .a0, "في المقهى", "At a Café", "أنت الزبون، والتطبيق موظف المقهى.", "Hello. What would you like?", "مرحبًا. ماذا ترغب؟", [
            ("اطلب مشروبًا بأدب.", ["tea", "coffee", "water", "please"], "I would like coffee, please.", "Certainly. Anything else?"),
            ("أجب هل تريد شيئًا آخر.", ["no", "thank", "yes"], "No, thank you.", "Great. Your order will be ready soon.")
        ]),
        scenario("introductions", .a0, "تعارف قصير", "A Short Introduction", "أنت طالب جديد، والتطبيق زميلك.", "Hi! What is your name?", "مرحبًا، ما اسمك؟", [
            ("عرّف باسمك.", ["my name", "I am"], "My name is Abdullah.", "Nice to meet you."),
            ("قل إنك سعيد بلقائه.", ["nice", "meet"], "Nice to meet you too.", "Welcome to the class!")
        ]),
        scenario("directions", .a1, "السؤال عن الطريق", "Asking for Directions", "أنت زائر، والتطبيق أحد السكان.", "Hello. Can I help you?", "مرحبًا. هل أستطيع مساعدتك؟", [
            ("اسأل عن أقرب صيدلية.", ["where", "pharmacy"], "Where is the nearest pharmacy?", "Go straight and turn left at the bank."),
            ("أكد أنك فهمت واشكر المتحدث.", ["understand", "thank"], "I understand. Thank you.", "You’re welcome.")
        ]),
        scenario("hotel", .a1, "تسجيل الدخول إلى فندق", "Hotel Check-in", "أنت النزيل، والتطبيق موظف الاستقبال.", "Welcome. Do you have a reservation?", "مرحبًا. هل لديك حجز؟", [
            ("قل إن لديك حجزًا لليلتين.", ["reservation", "two nights"], "Yes, I have a reservation for two nights.", "May I have your name, please?"),
            ("اذكر اسمك بطريقة مناسبة.", ["name", "is"], "My name is Abdullah Alrashidi.", "Thank you. Your room is ready.")
        ]),
        scenario("airport", .a2, "مشكلة في المطار", "Airport Problem", "أنت مسافر، والتطبيق موظف خدمة الأمتعة.", "How can I help you today?", "كيف أساعدك اليوم؟", [
            ("اشرح أن حقيبتك لم تصل.", ["bag", "did not", "arrive"], "My bag did not arrive.", "I’m sorry. Can you describe it?"),
            ("صف لون الحقيبة وحجمها.", ["black", "large", "small", "blue"], "It is a large black suitcase.", "We will check the baggage system.")
        ]),
        scenario("doctor", .a2, "زيارة الطبيب", "Visiting a Doctor", "أنت المريض، والتطبيق الطبيب.", "What seems to be the problem?", "ما المشكلة؟", [
            ("صف صداعًا بدأ منذ يومين.", ["headache", "two days"], "I have had a headache for two days.", "Do you have any other symptoms?"),
            ("قل إنك تشعر بالتعب ولا توجد حرارة.", ["tired", "fever", "no"], "I feel tired, but I do not have a fever.", "I will check your blood pressure.")
        ]),
        scenario("meeting", .b1, "اجتماع فريق", "Team Meeting", "أنت عضو فريق، والتطبيق مدير الاجتماع.", "Could you give us a quick update?", "هل يمكنك إعطاؤنا تحديثًا سريعًا؟", [
            ("اذكر أنك أنهيت المسودة وتحتاج إلى مراجعة.", ["finished", "draft", "review"], "I finished the draft, but it needs a final review.", "What do you need from the team?"),
            ("اطلب ملاحظات قبل نهاية اليوم.", ["feedback", "end of the day"], "Please send me your feedback by the end of the day.", "That sounds reasonable.")
        ]),
        scenario("job-interview", .b1, "مقابلة عمل", "Job Interview", "أنت المتقدم، والتطبيق مسؤول التوظيف.", "Tell me about yourself.", "حدثني عن نفسك.", [
            ("قدّم تعليمك وخبرتك بإيجاز.", ["graduated", "experience", "law", "work"], "I graduated in law and have experience in governance projects.", "Why are you interested in this role?"),
            ("اربط اهتمامك بمهاراتك.", ["skills", "contribute", "learn"], "The role matches my skills, and I want to contribute while continuing to learn.", "Thank you for the clear answer.")
        ]),
        scenario("complaint", .b2, "شكوى مهنية", "A Professional Complaint", "أنت العميل، والتطبيق مدير الخدمة.", "I understand there has been a problem. What happened?", "أفهم أن هناك مشكلة. ماذا حدث؟", [
            ("اشرح المشكلة دون انفعال.", ["ordered", "received", "however", "wrong"], "I ordered the standard package; however, I received a different item.", "What outcome would be acceptable to you?"),
            ("اطلب الاستبدال وتأكيد الموعد.", ["replacement", "confirm", "delivery"], "I would appreciate a replacement and confirmation of the delivery date.", "We can arrange that today.")
        ]),
        scenario("presentation", .b2, "عرض فكرة", "Presenting an Idea", "أنت مقدم العرض، والتطبيق أحد الحضور.", "What is the main benefit of your proposal?", "ما الفائدة الرئيسية من مقترحك؟", [
            ("لخص الفائدة مع دليل بسيط.", ["benefit", "because", "data", "reduce"], "The main benefit is lower processing time because the pilot data shows a clear reduction.", "What is the main risk?"),
            ("اذكر مخاطرة وخطة تخفيفها.", ["risk", "mitigate", "training", "monitor"], "The main risk is inconsistent adoption, which we can mitigate through training and monitoring.", "That addresses my concern.")
        ]),
        scenario("academic", .c1, "نقاش أكاديمي", "Academic Discussion", "أنت الباحث، والتطبيق مناقش علمي.", "How strong is the evidence for your conclusion?", "ما مدى قوة الدليل على استنتاجك؟", [
            ("استخدم لغة تحفظ علمي.", ["suggest", "may", "limited", "evidence"], "The findings suggest a relationship, although the limited sample means the conclusion should remain cautious.", "What would strengthen the study?"),
            ("اقترح تحسينًا منهجيًا.", ["larger sample", "comparison", "longitudinal"], "A larger sample and a longitudinal comparison would strengthen the study considerably.", "That is a well-qualified recommendation.")
        ]),
        scenario("negotiation", .c1, "تفاوض متقدم", "Advanced Negotiation", "أنت ممثل جهة، والتطبيق الطرف الآخر.", "Your proposal is promising, but the timeline is difficult.", "مقترحك واعد، لكن الجدول الزمني صعب.", [
            ("اعترف بالمخاوف واقترح حلًا مرحليًا.", ["understand", "concern", "phased", "milestone"], "I understand the concern. A phased delivery with measurable milestones could reduce the pressure.", "How would accountability be maintained?"),
            ("اشرح آلية متابعة واضحة.", ["weekly", "report", "responsibility", "review"], "Each milestone would have a named owner, a weekly report, and a joint review before approval.", "That framework could support an agreement.")
        ])
    ]

    static let dictationPrompts: [DictationPrompt] = [
        .init(id: "d-a0-1", level: .a0, sentence: "Hello, my name is Sara.", translationAr: "مرحبًا، اسمي سارة."),
        .init(id: "d-a0-2", level: .a0, sentence: "The phone is on the table.", translationAr: "الهاتف على الطاولة."),
        .init(id: "d-a1-1", level: .a1, sentence: "I usually wake up at seven.", translationAr: "أستيقظ عادةً الساعة السابعة."),
        .init(id: "d-a1-2", level: .a1, sentence: "Could I have the receipt, please?", translationAr: "هل يمكنني الحصول على الإيصال؟"),
        .init(id: "d-a2-1", level: .a2, sentence: "The train was delayed because of the weather.", translationAr: "تأخر القطار بسبب الطقس."),
        .init(id: "d-b1-1", level: .b1, sentence: "I finished the report, but it still needs a final review.", translationAr: "أنهيت التقرير، لكنه ما زال يحتاج إلى مراجعة نهائية."),
        .init(id: "d-b2-1", level: .b2, sentence: "The policy could improve flexibility without reducing accountability.", translationAr: "قد تحسن السياسة المرونة دون تقليل المساءلة."),
        .init(id: "d-c1-1", level: .c1, sentence: "The available evidence may indicate a gradual but significant shift.", translationAr: "قد تشير الأدلة المتاحة إلى تحول تدريجي لكنه مهم.")
    ]

    static func evaluate(_ response: String, for turn: ConversationTurn) -> ConversationEvaluation {
        let normalized = response.lowercased()
        let matched = turn.expectedIdeas.filter { idea in
            normalized.contains(idea.lowercased()) || StringSimilarity.score(idea, response) > 0.78
        }
        let score = min(1, Double(matched.count) / Double(max(1, min(2, turn.expectedIdeas.count))))
        let feedback: String
        if score >= 0.8 {
            feedback = "إجابة قوية ومناسبة للموقف. استخدمت الأفكار الأساسية بوضوح."
        } else if score >= 0.4 {
            feedback = "المعنى مفهوم. أضف فكرة أو عبارة أساسية ليصبح الرد أكثر اكتمالًا."
        } else {
            feedback = "جرّب جملة أقصر تذكر الفكرة المطلوبة مباشرة، ثم قارنها بالنموذج."
        }
        return ConversationEvaluation(score: score, matchedIdeas: matched, feedbackAr: feedback)
    }

    private static func scenario(
        _ id: String,
        _ level: CEFRLevel,
        _ titleAr: String,
        _ titleEn: String,
        _ roleAr: String,
        _ opening: String,
        _ openingAr: String,
        _ rawTurns: [(String, [String], String, String)]
    ) -> ConversationScenario {
        ConversationScenario(
            id: id,
            level: level,
            titleAr: titleAr,
            titleEn: titleEn,
            roleAr: roleAr,
            openingLine: opening,
            openingLineAr: openingAr,
            turns: rawTurns.enumerated().map { index, value in
                ConversationTurn(
                    id: "\(id)-turn-\(index + 1)",
                    promptAr: value.0,
                    expectedIdeas: value.1,
                    sampleAnswer: value.2,
                    responseOnSuccess: value.3,
                    responseOnRetry: "Let’s try that again with a clearer phrase."
                )
            }
        )
    }
}

// MARK: - Batch 3 advanced local coaching

enum PronunciationAnalyzer {
    private enum AlignmentStep {
        case pair(String, String)
        case omitted(String)
        case extra(String)
    }

    static func analyze(
        target: String,
        recognized: String,
        accent: AccentVariant,
        duration: TimeInterval,
        segments: [SpeechSegmentSnapshot]
    ) -> PronunciationReport {
        let expectedWords = tokens(target)
        let recognizedWords = tokens(recognized)
        let alignment = align(expected: expectedWords, actual: recognizedWords)
        var results: [WordPronunciationResult] = []
        var accuracyTotal = 0.0
        var matchedExpected = 0

        for (index, step) in alignment.enumerated() {
            switch step {
            case let .pair(expected, actual):
                let similarity = StringSimilarity.score(expected, actual)
                let issue: PronunciationIssueKind
                if similarity >= 0.90 { issue = .accurate }
                else if similarity >= 0.68 { issue = .close }
                else { issue = .substituted }
                accuracyTotal += similarity
                matchedExpected += 1
                results.append(.init(
                    id: "word-\(index)-\(expected)",
                    expected: expected,
                    recognized: actual,
                    similarity: similarity,
                    issue: issue,
                    tipAr: issue == .accurate ? nil : pronunciationTip(for: expected, accent: accent)
                ))
            case let .omitted(expected):
                results.append(.init(
                    id: "word-\(index)-\(expected)",
                    expected: expected,
                    recognized: nil,
                    similarity: 0,
                    issue: .omitted,
                    tipAr: pronunciationTip(for: expected, accent: accent)
                ))
            case let .extra(actual):
                results.append(.init(
                    id: "extra-\(index)-\(actual)",
                    expected: "",
                    recognized: actual,
                    similarity: 0,
                    issue: .extra,
                    tipAr: "هذه الكلمة لم تكن في الجملة المستهدفة. أعد الجملة ببطء مع وقفة قصيرة بين وحدات المعنى."
                ))
            }
        }

        let expectedCount = max(1, expectedWords.count)
        let accuracy = min(1, accuracyTotal / Double(expectedCount))
        let completeness = min(1, Double(matchedExpected) / Double(expectedCount))
        let safeDuration = max(duration, 0.8)
        let wordsPerMinute = Double(recognizedWords.count) / safeDuration * 60
        let paceScore = fluencyScore(wordsPerMinute: wordsPerMinute)
        let segmentConfidence = segments.isEmpty ? 0.72 : Double(segments.map(\.confidence).reduce(0, +)) / Double(segments.count)
        let longPausePenalty = pausePenalty(segments: segments)
        let fluency = min(1, max(0, paceScore * 0.65 + segmentConfidence * 0.35 - longPausePenalty))
        let overall = accuracy * 0.48 + completeness * 0.27 + fluency * 0.25
        var tips: [String] = []
        if wordsPerMinute < 70 { tips.append("السرعة منخفضة. كرر الجملة على مجموعات من كلمتين أو ثلاث، ثم صِل المجموعات معًا.") }
        if wordsPerMinute > 175 { tips.append("السرعة مرتفعة. خفف الإيقاع قليلًا حتى تبقى نهايات الكلمات واضحة.") }
        if completeness < 0.8 { tips.append("بعض الكلمات سقطت أثناء النطق. استمع للنموذج ثم كرر الجملة على مرحلتين.") }
        if accuracy < 0.75 { tips.append("ركّز على الكلمات المعلمة أدناه بدل إعادة الجملة كاملة مرات كثيرة.") }
        if tips.isEmpty { tips.append("النطق واضح ومتزن. جرّب الجملة في موقف جديد حتى تتحول من حفظ إلى استخدام طبيعي.") }

        return PronunciationReport(
            id: UUID().uuidString,
            target: target,
            recognized: recognized,
            accent: accent,
            createdAt: .now,
            accuracy: accuracy,
            completeness: completeness,
            fluency: fluency,
            overall: overall,
            wordsPerMinute: wordsPerMinute,
            words: results,
            tipsAr: tips
        )
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet.letters.union(CharacterSet(charactersIn: "' ")).inverted)
            .joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    private static func align(expected: [String], actual: [String]) -> [AlignmentStep] {
        let rows = expected.count + 1
        let columns = actual.count + 1
        var cost = Array(repeating: Array(repeating: 0.0, count: columns), count: rows)
        var operation = Array(repeating: Array(repeating: 0, count: columns), count: rows)
        for index in 1..<rows { cost[index][0] = Double(index); operation[index][0] = 1 }
        for index in 1..<columns { cost[0][index] = Double(index); operation[0][index] = 2 }

        if rows > 1 && columns > 1 {
            for row in 1..<rows {
                for column in 1..<columns {
                    let substitution = cost[row - 1][column - 1] + (1 - StringSimilarity.score(expected[row - 1], actual[column - 1]))
                    let deletion = cost[row - 1][column] + 1
                    let insertion = cost[row][column - 1] + 1
                    let minimum = min(substitution, deletion, insertion)
                    cost[row][column] = minimum
                    operation[row][column] = minimum == substitution ? 0 : (minimum == deletion ? 1 : 2)
                }
            }
        }

        var row = expected.count
        var column = actual.count
        var reversed: [AlignmentStep] = []
        while row > 0 || column > 0 {
            if row > 0 && column > 0 && operation[row][column] == 0 {
                reversed.append(.pair(expected[row - 1], actual[column - 1]))
                row -= 1
                column -= 1
            } else if row > 0 && (column == 0 || operation[row][column] == 1) {
                reversed.append(.omitted(expected[row - 1]))
                row -= 1
            } else if column > 0 {
                reversed.append(.extra(actual[column - 1]))
                column -= 1
            }
        }
        return reversed.reversed()
    }

    private static func fluencyScore(wordsPerMinute: Double) -> Double {
        switch wordsPerMinute {
        case 95...155: return 1
        case 75..<95: return 0.82
        case 155...180: return 0.80
        case 55..<75: return 0.62
        case 180...210: return 0.58
        default: return 0.42
        }
    }

    private static func pausePenalty(segments: [SpeechSegmentSnapshot]) -> Double {
        guard segments.count > 1 else { return 0 }
        let sorted = segments.sorted { $0.timestamp < $1.timestamp }
        var penalty = 0.0
        for pair in zip(sorted, sorted.dropFirst()) {
            let gap = pair.1.timestamp - (pair.0.timestamp + pair.0.duration)
            if gap > 1.5 { penalty += min(0.12, gap * 0.025) }
        }
        return min(0.25, penalty)
    }

    private static func pronunciationTip(for word: String, accent: AccentVariant) -> String {
        let lower = word.lowercased()
        let special: [String: String] = [
            "the": "ابدأ بصوت ذال خفيف مع طرف اللسان بين الأسنان، ثم انتقل سريعًا إلى صوت قصير.",
            "three": "أخرج طرف اللسان قليلًا بين الأسنان لصوت th، ثم انتقل مباشرة إلى r دون إضافة تاء.",
            "think": "صوت th هنا مهموس، والهواء يمر بين اللسان والأسنان دون اهتزاز قوي.",
            "would": "لا تنطق حرف l. الكلمة قريبة من وُد، مع صوت قصير ومغلق.",
            "could": "لا تنطق حرف l. ابدأ بصوت ك ثم صوت قصير قريب من أُ.",
            "comfortable": "قسّمها إلى ثلاث وحدات صوتية تقريبًا: comf-ta-ble، ولا تحاول نطق كل حرف مكتوب.",
            "world": "ابدأ بـ w، ثم r واضحة، وأنهِ بصوت ld دون فصل زائد.",
            "work": "حافظ على صوت r داخل الكلمة، ثم أنهِ بصوت k واضح.",
            "law": "مدّ صوت aw قليلًا، ولا تضف r في النهاية.",
            "schedule": accent == .british ? "في النطق البريطاني تبدأ غالبًا بصوت ش: shed-yool." : "في النطق الأمريكي تبدأ غالبًا بصوت sk: sked-jool."
        ]
        if let tip = special[lower] { return tip }
        if lower.contains("th") { return "ضع طرف اللسان برفق بين الأسنان لصوت th، ولا تستبدله بتاء أو سين." }
        if lower.hasSuffix("ed") { return "انتبه لنهاية ed؛ قد تُنطق ت أو د أو مقطعًا إضافيًا بحسب الصوت السابق." }
        if lower.hasSuffix("s") { return "اجعل نهاية الجمع أو الفعل مسموعة دون مبالغة، وقد تكون س أو ز بحسب الصوت السابق." }
        if lower.contains("r") && accent == .american { return "في اللكنة الأمريكية يكون صوت r مسموعًا بوضوح دون لمس طرف اللسان لسقف الفم." }
        return "استمع للكلمة وحدها، ثم انطقها ببطء، وبعدها أعدها داخل الجملة دون فصل مصطنع."
    }
}

enum SpeakingResponseAnalyzer {
    static func evaluate(answer: String, question: ExamQuestion) -> InterviewEvaluation {
        let normalized = answer.lowercased()
        let words = normalized.split(whereSeparator: { $0.isWhitespace })
        let matched = question.keywords.filter { normalized.contains($0.lowercased()) }
        let relevance = min(1, Double(matched.count) / Double(max(1, min(3, question.keywords.count))))
        let connectors = ["because", "however", "for example", "therefore", "although", "first", "finally"]
        let connectorCount = connectors.filter { normalized.contains($0) }.count
        let structure = min(1, Double(connectorCount) * 0.22 + (words.count >= 35 ? 0.45 : Double(words.count) / 80))
        let language = min(1, 0.35 + Double(Set(words).count) / Double(max(20, words.count)) * 0.45 + (answer.contains(".") ? 0.15 : 0))
        let overall = relevance * 0.4 + structure * 0.3 + language * 0.3
        var feedback: [String] = []
        if relevance < 0.65 { feedback.append("ابدأ بإجابة مباشرة على السؤال قبل إضافة التفاصيل.") }
        if structure < 0.65 { feedback.append("رتب الإجابة إلى فكرة، سبب، ثم مثال قصير.") }
        if words.count < 25 { feedback.append("الإجابة قصيرة. أضف سببًا أو مثالًا واحدًا بدل تكرار الفكرة نفسها.") }
        if connectorCount == 0 { feedback.append("استخدم رابطًا طبيعيًا مثل because أو however لزيادة الترابط.") }
        if feedback.isEmpty { feedback.append("الإجابة مترابطة ومباشرة. جرّبها مرة أخرى بصوت طبيعي دون قراءة.") }
        return .init(relevance: relevance, structure: structure, language: language, overall: overall, matchedIdeas: matched, feedbackAr: feedback)
    }

    static func evaluateInterview(answer: String, question: InterviewQuestion) -> InterviewEvaluation {
        let proxy = ExamQuestion(
            id: question.id,
            track: .workplace,
            level: question.level,
            kind: .speaking,
            prompt: question.question,
            promptAr: question.questionAr,
            choices: [],
            answer: nil,
            keywords: question.expectedIdeas,
            explanationAr: question.coachingPointsAr.joined(separator: " ")
        )
        return evaluate(answer: answer, question: proxy)
    }
}

enum AdvancedPracticeLibrary {
    static let ieltsSpeakingQuestions: [ExamQuestion] = [
        speaking("ielts-1", .a2, "Describe a place where you feel relaxed.", "صف مكانًا تشعر فيه بالراحة.", ["place", "because", "feel", "usually"]),
        speaking("ielts-2", .b1, "Talk about a skill you would like to learn.", "تحدث عن مهارة ترغب في تعلمها.", ["skill", "learn", "because", "future"]),
        speaking("ielts-3", .b1, "Describe a person who influenced you positively.", "صف شخصًا أثّر فيك إيجابيًا.", ["person", "helped", "learned", "example"]),
        speaking("ielts-4", .b2, "Do you think technology makes people more independent?", "هل تجعل التقنية الناس أكثر استقلالًا؟", ["technology", "independent", "however", "example"]),
        speaking("ielts-5", .b2, "What are the advantages and disadvantages of working from home?", "ما مزايا وعيوب العمل من المنزل؟", ["advantage", "disadvantage", "work", "balance"]),
        speaking("ielts-6", .c1, "How should cities balance economic growth with quality of life?", "كيف توازن المدن بين النمو الاقتصادي وجودة الحياة؟", ["balance", "growth", "quality", "policy"]),
        speaking("ielts-7", .a2, "Describe your usual weekend.", "صف عطلة نهاية الأسبوع المعتادة.", ["usually", "weekend", "family", "enjoy"]),
        speaking("ielts-8", .b1, "Talk about a difficult decision you made.", "تحدث عن قرار صعب اتخذته.", ["decision", "because", "result", "learned"]),
        speaking("ielts-9", .b2, "Should universities focus more on practical skills?", "هل ينبغي للجامعات التركيز أكثر على المهارات العملية؟", ["universities", "practical", "skills", "example"]),
        speaking("ielts-10", .c1, "Why do some public policies fail despite good intentions?", "لماذا تفشل بعض السياسات العامة رغم حسن النية؟", ["policy", "implementation", "evidence", "stakeholders"]),
        speaking("ielts-11", .b1, "Describe a useful piece of advice you received.", "صف نصيحة مفيدة تلقيتها.", ["advice", "received", "helped", "because"]),
        speaking("ielts-12", .b2, "How can communities become more inclusive for people with disabilities?", "كيف تصبح المجتمعات أكثر شمولًا للأشخاص ذوي الإعاقة؟", ["accessibility", "inclusion", "services", "participation"])
    ]

    static let stepQuestions: [ExamQuestion] = [
        choice("step-1", .a1, "She ___ to work every morning.", "اختر الفعل الصحيح.", ["go", "goes", "going", "gone"], "goes", "مع she نضيف s إلى الفعل في المضارع البسيط."),
        choice("step-2", .a1, "I have lived here ___ 2022.", "اختر حرف الجر المناسب.", ["for", "since", "from", "during"], "since", "نستخدم since مع نقطة بداية محددة."),
        choice("step-3", .a2, "The report ___ yesterday.", "اختر صيغة المبني للمجهول.", ["completed", "was completed", "is complete", "has completing"], "was completed", "حدث في الماضي والمفعول هو محور الجملة، لذلك نستخدم was completed."),
        choice("step-4", .a2, "If it rains, we ___ the meeting online.", "اختر نتيجة الشرط الحقيقية.", ["hold", "held", "will hold", "would hold"], "will hold", "الشرط الأول: if + present، ثم will + verb."),
        choice("step-5", .b1, "The word 'reliable' is closest in meaning to:", "اختر أقرب معنى.", ["expensive", "dependable", "temporary", "unclear"], "dependable", "Reliable تعني جديرًا بالاعتماد."),
        choice("step-6", .b1, "Neither the manager nor the employees ___ satisfied.", "اختر الفعل الصحيح.", ["was", "is", "were", "be"], "were", "يتبع الفعل الاسم الأقرب إليه، وهو employees الجمع."),
        choice("step-7", .b1, "By the time we arrived, the session ___.", "اختر الزمن المناسب.", ["starts", "started", "had started", "has started"], "had started", "حدث البدء قبل وصولنا، لذلك نستخدم الماضي التام."),
        choice("step-8", .b2, "The policy was revised ___ several concerns raised by users.", "اختر الرابط الأنسب.", ["despite", "because of", "unless", "whereas"], "because of", "بعدها اسم، والمعنى سببي: بسبب مخاوف عدة."),
        choice("step-9", .b2, "Had I known about the deadline, I ___ earlier.", "اختر جواب الشرط الثالث.", ["apply", "would apply", "would have applied", "had applied"], "would have applied", "الشرط الثالث يعبر عن ماضٍ لم يحدث."),
        choice("step-10", .b2, "The evidence is insufficient; ___, further research is required.", "اختر أداة الربط.", ["therefore", "although", "meanwhile", "otherwise"], "therefore", "الجملة الثانية نتيجة للأولى."),
        choice("step-11", .c1, "The committee's decision was described as arbitrary. 'Arbitrary' most nearly means:", "اختر المعنى الأدق.", ["based on clear rules", "made without fair reasoning", "widely supported", "legally binding"], "made without fair reasoning", "Arbitrary تعني اعتباطيًا أو بلا أساس منصف واضح."),
        choice("step-12", .c1, "No sooner ___ the announcement than the system crashed.", "اختر التركيب الصحيح.", ["did they publish", "they published", "had they published", "they had published"], "had they published", "بعد No sooner يحدث قلب: had + subject + past participle."),
        choice("step-13", .a1, "Could you ___ me the way to the station?", "اختر الفعل المناسب.", ["say", "tell", "speak", "talk"], "tell", "نقول tell someone the way."),
        choice("step-14", .a2, "This book is ___ than the other one.", "اختر صيغة المقارنة.", ["interesting", "more interesting", "most interesting", "interest"], "more interesting", "الصفة الطويلة تأخذ more في المقارنة."),
        choice("step-15", .b1, "We need to ___ the issue before it becomes serious.", "اختر الفعل الأنسب.", ["address", "deliver", "attend", "perform"], "address", "Address an issue تعني التعامل معه أو معالجته."),
        choice("step-16", .b2, "The proposal is feasible, ___ it requires additional funding.", "اختر الرابط الأنسب.", ["because", "but", "so", "unless"], "but", "يوجد تضاد بين إمكان التنفيذ والحاجة إلى تمويل."),
        choice("step-17", .c1, "The findings should be interpreted with caution due to the study's limited ___.", "اختر الاسم الأنسب.", ["sample", "example", "edition", "schedule"], "sample", "العينة المحدودة سبب شائع للتحفظ في تفسير النتائج."),
        choice("step-18", .a2, "He apologized ___ being late.", "اختر حرف الجر.", ["to", "for", "with", "at"], "for", "Apologize for + noun or gerund."),
        choice("step-19", .b1, "The meeting has been ___ until next week.", "اختر الكلمة المناسبة.", ["postponed", "prevented", "avoided", "refused"], "postponed", "Postponed تعني مؤجلًا."),
        choice("step-20", .b2, "It is essential that every applicant ___ the form accurately.", "اختر صيغة الفعل.", ["completes", "complete", "completed", "will complete"], "complete", "بعد It is essential that نستخدم الصيغة المجردة في الأسلوب الرسمي."),
        choice("step-21", .a1, "There ___ two chairs in the room.", "اختر الفعل الصحيح.", ["is", "are", "was", "be"], "are", "الاسم بعد there جمع."),
        choice("step-22", .a2, "I am interested ___ learning more.", "اختر حرف الجر.", ["in", "on", "at", "for"], "in", "Interested in تركيب ثابت."),
        choice("step-23", .b1, "The manager asked whether the task ___ completed.", "اختر الزمن المناسب.", ["has been", "had been", "is", "will"], "had been", "السؤال غير المباشر في الماضي يشير إلى حدث أسبق."),
        choice("step-24", .c1, "The regulation may have unintended ___ for small businesses.", "اختر الاسم الأنسب.", ["consequences", "conversations", "conveniences", "constructions"], "consequences", "Unintended consequences تعني آثارًا أو عواقب غير مقصودة.")
    ]

    static let interviewQuestions: [InterviewQuestion] = [
        interview("int-1", .introduction, .a2, "Tell me about yourself.", "حدثني عن نفسك.", ["education", "experience", "skills"], "I graduated in law and developed practical experience through governance and research projects. I am organized, eager to learn, and interested in work that combines analysis with public value.", ["ابدأ بخلفيتك الحالية، ثم خبرة مرتبطة، ثم سبب ملاءمتك للدور.", "لا تحوّل الإجابة إلى سيرة ذاتية كاملة."]),
        interview("int-2", .introduction, .b1, "Why are you interested in this role?", "لماذا تهتم بهذه الوظيفة؟", ["role", "skills", "contribute", "learn"], "This role matches my analytical and communication skills. It would allow me to contribute to meaningful work while continuing to learn from an experienced team.", ["اربط بين احتياج الوظيفة ومهارة حقيقية لديك.", "اذكر ما ستقدمه، لا ما ستحصل عليه فقط."]),
        interview("int-3", .introduction, .b1, "What is one of your main strengths?", "ما إحدى أبرز نقاط قوتك؟", ["strength", "example", "result"], "One of my main strengths is careful analysis. In a university project, I reviewed complex requirements, organized them into clear steps, and helped the team deliver an accurate final report.", ["اختر قوة واحدة مع مثال ونتيجة."]),
        interview("int-4", .difficult, .b1, "What is a weakness you are working on?", "ما نقطة الضعف التي تعمل على تحسينها؟", ["weakness", "improve", "step", "progress"], "I used to spend too much time perfecting early drafts. I now set review stages and deadlines, which helps me maintain quality without slowing the work.", ["اختر ضعفًا حقيقيًا قابلًا للتحسين.", "اشرح الإجراء الذي اتخذته والنتيجة الحالية."]),
        interview("int-5", .behavioral, .b1, "Tell me about a time you solved a difficult problem.", "حدثني عن موقف حللت فيه مشكلة صعبة.", ["situation", "task", "action", "result"], "During a team project, information was scattered across several sources. I created a structured checklist, assigned verification tasks, and reviewed the final evidence. We completed the project accurately and on time.", ["استخدم تسلسل STAR: الموقف، المهمة، الإجراء، النتيجة."]),
        interview("int-6", .behavioral, .b2, "Describe a disagreement with a teammate and how you handled it.", "صف خلافًا مع زميل وكيف تعاملت معه.", ["disagreement", "listened", "evidence", "agreement"], "A teammate and I disagreed about the project structure. I asked each of us to explain the reasons behind our approach, compared both options against the requirements, and proposed a combined structure. We reached agreement without delaying the project.", ["لا تهاجم الطرف الآخر.", "أظهر الاستماع والاعتماد على معيار موضوعي."]),
        interview("int-7", .behavioral, .b2, "Tell me about a mistake you made.", "حدثني عن خطأ ارتكبته.", ["mistake", "responsibility", "corrected", "learned"], "I once underestimated the time needed for a detailed review. I informed the team early, corrected the schedule, and created a review checklist. Since then, my estimates have become more realistic.", ["تحمل المسؤولية بوضوح.", "اختم بما تغير في سلوكك بعد الخطأ."]),
        interview("int-8", .behavioral, .b1, "How do you manage multiple deadlines?", "كيف تدير عدة مواعيد نهائية؟", ["prioritize", "deadline", "calendar", "review"], "I list every deadline, divide each task into smaller steps, and prioritize by urgency and impact. I also reserve time for review so that speed does not reduce accuracy.", ["اذكر نظامًا عمليًا لا صفة عامة فقط."]),
        interview("int-9", .legalGovernance, .b2, "What does good governance mean to you?", "ماذا تعني لك الحوكمة الجيدة؟", ["accountability", "transparency", "roles", "decisions"], "Good governance means clear responsibilities, transparent decision-making, effective oversight, and accountability for results. It also requires procedures that are practical and consistently applied.", ["اجمع بين المبادئ والتطبيق."]),
        interview("int-10", .legalGovernance, .b2, "How would you review a policy for compliance?", "كيف تراجع سياسة للتحقق من الامتثال؟", ["requirements", "evidence", "gaps", "recommendations"], "I would identify the applicable requirements, map each requirement to the policy and supporting evidence, document any gaps, assess their risk, and propose clear corrective actions.", ["قدم خطوات مرتبة وقابلة للتنفيذ."]),
        interview("int-11", .legalGovernance, .c1, "How do you balance legal risk with operational needs?", "كيف توازن بين المخاطر القانونية والاحتياجات التشغيلية؟", ["risk", "objective", "options", "controls"], "I first clarify the operational objective and the legal constraint. Then I compare lawful options, assess the remaining risk, and recommend proportionate controls that protect compliance without creating unnecessary complexity.", ["تجنب تصوير القانون بوصفه عائقًا منفصلًا عن العمل."]),
        interview("int-12", .legalGovernance, .c1, "How would you communicate a complex legal issue to a non-lawyer?", "كيف تشرح مسألة قانونية معقدة لغير المتخصص؟", ["plain language", "impact", "options", "recommendation"], "I would begin with the practical impact, explain the rule in plain language, separate confirmed facts from uncertainty, and present the available options with a clear recommendation.", ["ابدأ بالأثر العملي لا بالمصطلح القانوني."]),
        interview("int-13", .difficult, .b2, "Why should we hire you?", "لماذا ينبغي أن نوظفك؟", ["skills", "evidence", "role", "value"], "You should hire me because I combine legal training with structured analysis and a strong commitment to accessibility and clear communication. My projects show that I can turn complex requirements into reliable practical work.", ["قدم قيمة مرتبطة بالدور مع دليل مختصر."]),
        interview("int-14", .difficult, .b2, "Where do you see yourself in five years?", "أين ترى نفسك بعد خمس سنوات؟", ["develop", "responsibility", "expertise", "team"], "In five years, I hope to have developed deep expertise, taken responsibility for larger projects, and become someone the team can rely on for careful analysis and practical solutions.", ["اظهر طموحًا مرتبطًا بالنمو لا بمنصب محدد فقط."]),
        interview("int-15", .difficult, .b2, "Why did you leave your previous role?", "لماذا تركت عملك السابق؟", ["growth", "positive", "next", "opportunity"], "I valued what I learned in my previous role, but I am now looking for broader responsibilities and an environment where I can develop further and contribute at a higher level.", ["حافظ على نبرة إيجابية ولا تنتقد جهة سابقة."]),
        interview("int-16", .difficult, .c1, "How would you respond if a manager asked you to overlook a compliance concern?", "كيف تتصرف إذا طلب منك مدير تجاهل ملاحظة امتثال؟", ["clarify", "document", "risk", "escalate"], "I would clarify the facts and explain the risk respectfully, document the concern, suggest a compliant alternative, and follow the approved escalation process if the issue remained unresolved.", ["أظهر المهنية والثبات دون لهجة صدامية."]),
        interview("int-17", .behavioral, .b2, "Describe a time you worked under pressure.", "صف موقفًا عملت فيه تحت ضغط.", ["pressure", "prioritize", "communicate", "result"], "When several deadlines overlapped, I ranked tasks by urgency, communicated realistic milestones, and used a checklist to protect quality. The essential work was delivered on time without hidden errors.", ["وضح كيف حميت الجودة أثناء السرعة."]),
        interview("int-18", .introduction, .b1, "What motivates you at work?", "ما الذي يحفزك في العمل؟", ["impact", "learning", "quality", "team"], "I am motivated by work that has a clear impact, requires continuous learning, and allows me to improve quality with a collaborative team.", ["اربط الدافع بطبيعة العمل لا بالشعارات العامة."])
    ]

    private static func speaking(_ id: String, _ level: CEFRLevel, _ prompt: String, _ promptAr: String, _ keywords: [String]) -> ExamQuestion {
        .init(id: id, track: .ieltsSpeaking, level: level, kind: .speaking, prompt: prompt, promptAr: promptAr, choices: [], answer: nil, keywords: keywords, explanationAr: "أجب مباشرة، ثم قدم سببًا ومثالًا واضحًا.")
    }

    private static func choice(_ id: String, _ level: CEFRLevel, _ prompt: String, _ promptAr: String, _ choices: [String], _ answer: String, _ explanation: String) -> ExamQuestion {
        .init(id: id, track: .step, level: level, kind: .multipleChoice, prompt: prompt, promptAr: promptAr, choices: choices, answer: answer, keywords: [], explanationAr: explanation)
    }

    private static func interview(_ id: String, _ category: InterviewCategory, _ level: CEFRLevel, _ question: String, _ questionAr: String, _ ideas: [String], _ sample: String, _ points: [String]) -> InterviewQuestion {
        .init(id: id, category: category, level: level, question: question, questionAr: questionAr, expectedIdeas: ideas, sampleAnswer: sample, coachingPointsAr: points)
    }
}
