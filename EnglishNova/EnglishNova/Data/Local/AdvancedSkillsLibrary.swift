import Foundation

enum AdvancedSkillsLibrary {
    private struct ReadingSeed {
        let id: String
        let level: CEFRLevel
        let title: String
        let titleAr: String
        let topicAr: String
        let text: String
        let mainIdea: String
        let detailQuestion: String
        let detailAnswer: String
        let word: String
        let meaning: String
    }

    private struct ListeningSeed {
        let id: String
        let level: CEFRLevel
        let titleAr: String
        let contextAr: String
        let transcript: String
        let firstQuestion: String
        let firstAnswer: String
        let secondQuestion: String
        let secondAnswer: String
    }

    private struct WritingSeed {
        let id: String
        let level: CEFRLevel
        let kind: WritingPromptKind
        let titleAr: String
        let prompt: String
        let promptAr: String
        let minimumWords: Int
        let suggestedWords: [String]
        let checklistAr: [String]
        let sample: String
    }

    static let readingPassages: [ReadingPassage] = readingSeeds.flatMap { seed in
        [
            makeReading(seed, variant: 1),
            makeReading(seed, variant: 2)
        ]
    }

    static let listeningPassages: [ListeningPassage] = listeningSeeds.flatMap { seed in
        [
            makeListening(seed, variant: 1),
            makeListening(seed, variant: 2)
        ]
    }

    static let writingPrompts: [WritingPrompt] = writingSeeds.flatMap { seed in
        [
            makeWriting(seed, variant: 1),
            makeWriting(seed, variant: 2)
        ]
    }

    static func readings(for level: CEFRLevel) -> [ReadingPassage] {
        let exact = readingPassages.filter { $0.level == level }
        return exact.isEmpty ? readingPassages : exact
    }

    static func listenings(for level: CEFRLevel) -> [ListeningPassage] {
        let exact = listeningPassages.filter { $0.level == level }
        return exact.isEmpty ? listeningPassages : exact
    }

    static func writings(for level: CEFRLevel) -> [WritingPrompt] {
        let exact = writingPrompts.filter { $0.level == level }
        return exact.isEmpty ? writingPrompts : exact
    }

    private static let readingSeeds: [ReadingSeed] = [
        .init(
            id: "read-a0-morning", level: .a0, title: "My Morning", titleAr: "صباحي", topicAr: "الحياة اليومية",
            text: "I wake up at seven. I wash my face and drink water. Then I eat bread and cheese. I leave home at eight.",
            mainIdea: "a simple morning routine", detailQuestion: "What time does the person leave home?", detailAnswer: "at eight",
            word: "wake up", meaning: "stop sleeping"
        ),
        .init(
            id: "read-a0-cafe", level: .a0, title: "At the Café", titleAr: "في المقهى", topicAr: "الطعام",
            text: "Mona is at a small café. She asks for tea and a cheese sandwich. The tea is hot, and the sandwich is fresh. She pays ten riyals.",
            mainIdea: "ordering a simple meal", detailQuestion: "How much does Mona pay?", detailAnswer: "ten riyals",
            word: "fresh", meaning: "made recently"
        ),
        .init(
            id: "read-a1-bus", level: .a1, title: "The Bus to Work", titleAr: "الحافلة إلى العمل", topicAr: "المواصلات",
            text: "Sara takes bus number twelve to work. The trip usually takes twenty minutes, but today the road is busy. She arrives ten minutes late and calls her manager.",
            mainIdea: "Sara's delayed trip to work", detailQuestion: "Why is the trip slower today?", detailAnswer: "the road is busy",
            word: "arrives", meaning: "reaches a place"
        ),
        .init(
            id: "read-a1-library", level: .a1, title: "The Library Card", titleAr: "بطاقة المكتبة", topicAr: "الدراسة",
            text: "Noura visits the public library to get a library card. She shows her identification, writes her address, and chooses a password. Now she can borrow three books at a time.",
            mainIdea: "getting and using a library card", detailQuestion: "How many books can Noura borrow?", detailAnswer: "three books",
            word: "borrow", meaning: "take and return later"
        ),
        .init(
            id: "read-a2-return", level: .a2, title: "Returning a Product", titleAr: "إرجاع منتج", topicAr: "التسوق",
            text: "Lina bought headphones online, but the left side did not work. She contacted customer service, explained the problem, and received a prepaid return label. The company promised a replacement within five days.",
            mainIdea: "returning faulty headphones", detailQuestion: "What did the company promise?", detailAnswer: "a replacement within five days",
            word: "faulty", meaning: "not working correctly"
        ),
        .init(
            id: "read-a2-electricity", level: .a2, title: "Saving Electricity", titleAr: "توفير الكهرباء", topicAr: "المنزل",
            text: "The Al-Harbi family noticed that their electricity bill was rising. They replaced old bulbs with efficient ones, turned off unused lights, and adjusted the air conditioner. The next bill was lower.",
            mainIdea: "reducing electricity use", detailQuestion: "What happened to the next bill?", detailAnswer: "it was lower",
            word: "efficient", meaning: "working well without waste"
        ),
        .init(
            id: "read-b1-feedback", level: .b1, title: "Learning from Feedback", titleAr: "التعلم من الملاحظات", topicAr: "التطوير",
            text: "Maha felt disappointed when her presentation received several critical comments. Instead of defending every slide, she grouped the feedback into content, structure, and delivery. She revised one area at a time and gave a much clearer presentation the following week.",
            mainIdea: "using feedback to improve a presentation", detailQuestion: "How did Maha organize the feedback?", detailAnswer: "into content, structure, and delivery",
            word: "critical", meaning: "pointing out problems or weaknesses"
        ),
        .init(
            id: "read-b1-meeting", level: .b1, title: "A Better Meeting", titleAr: "اجتماع أفضل", topicAr: "الإدارة",
            text: "The weekly meeting used to last ninety minutes and end without clear decisions. The team introduced a written agenda, limited updates to two minutes, and recorded every action with an owner and deadline. Meetings now finish in forty minutes.",
            mainIdea: "making meetings shorter and clearer", detailQuestion: "How long do meetings last now?", detailAnswer: "forty minutes",
            word: "agenda", meaning: "a list of topics for a meeting"
        ),
        .init(
            id: "read-b2-plain-language", level: .b2, title: "The Value of Plain Language", titleAr: "قيمة اللغة الواضحة", topicAr: "القانون",
            text: "Legal and administrative documents often become difficult because writers mistake complexity for precision. Plain language does not mean removing necessary legal meaning. It means organizing information, defining technical terms, and expressing obligations so that the intended reader can act correctly.",
            mainIdea: "why clear drafting improves legal communication", detailQuestion: "What does plain language preserve?", detailAnswer: "necessary legal meaning",
            word: "obligations", meaning: "duties that must be performed"
        ),
        .init(
            id: "read-b2-access", level: .b2, title: "Public Transport and Access", titleAr: "النقل العام والإتاحة", topicAr: "المدن",
            text: "Accessible public transport requires more than ramps. Audio announcements, consistent platform design, staff training, readable signs, and reliable journey information all determine whether passengers with different disabilities can travel independently.",
            mainIdea: "the multiple elements of accessible transport", detailQuestion: "What is required in addition to ramps?", detailAnswer: "information, design, and trained staff",
            word: "reliable", meaning: "consistently trustworthy"
        ),
        .init(
            id: "read-c1-governance", level: .c1, title: "Governance Beyond Compliance", titleAr: "الحوكمة بعد الامتثال", topicAr: "الحوكمة",
            text: "Organizations sometimes treat governance as a collection of documents designed to satisfy regulators. Yet policies have little value when incentives reward contrary behavior or when leaders ignore inconvenient information. Effective governance aligns authority, accountability, evidence, and culture so that sound decisions remain possible under pressure.",
            mainIdea: "governance as behavior and decision architecture", detailQuestion: "Why can written policies have little value?", detailAnswer: "incentives and leaders may contradict them",
            word: "contrary", meaning: "opposite or conflicting"
        ),
        .init(
            id: "read-c1-risk", level: .c1, title: "Interpreting Risk Indicators", titleAr: "تفسير مؤشرات المخاطر", topicAr: "المخاطر",
            text: "A single risk indicator rarely proves that a control has failed. It may reflect seasonality, a change in reporting, or an unusual but legitimate event. Analysts should therefore examine trends, thresholds, corroborating evidence, and the operational context before recommending intervention.",
            mainIdea: "interpreting risk signals with context", detailQuestion: "What should analysts examine before intervening?", detailAnswer: "trends, evidence, thresholds, and context",
            word: "corroborating", meaning: "supporting with additional evidence"
        )
    ]

    private static let listeningSeeds: [ListeningSeed] = [
        .init(id: "listen-a0-bakery", level: .a0, titleAr: "طلب في مخبز", contextAr: "محادثة شراء قصيرة", transcript: "Hello. Can I have two brown rolls and one small cake, please? Of course. That is twelve riyals.", firstQuestion: "How many rolls does the customer want?", firstAnswer: "two", secondQuestion: "What is the total price?", secondAnswer: "twelve riyals"),
        .init(id: "listen-a0-hotel", level: .a0, titleAr: "رقم الغرفة", contextAr: "استقبال فندق", transcript: "Welcome to the hotel. Your room is number two hundred and six on the second floor. Breakfast starts at seven.", firstQuestion: "What is the room number?", firstAnswer: "206", secondQuestion: "When does breakfast start?", secondAnswer: "at seven"),
        .init(id: "listen-a1-clinic", level: .a1, titleAr: "تغيير موعد", contextAr: "مكالمة من عيادة", transcript: "Good morning. This is the dental clinic. Your appointment on Tuesday has moved from ten o'clock to eleven thirty. Please call us if the new time is not suitable.", firstQuestion: "What is the new appointment time?", firstAnswer: "eleven thirty", secondQuestion: "What should the listener do if the time is unsuitable?", secondAnswer: "call the clinic"),
        .init(id: "listen-a1-delivery", level: .a1, titleAr: "تعليمات توصيل", contextAr: "تعليمات لمندوب", transcript: "Please leave the package with the security guard if no one answers the door. Do not leave it outside because it may rain.", firstQuestion: "Where should the package be left?", firstAnswer: "with the security guard", secondQuestion: "Why should it not be left outside?", secondAnswer: "it may rain"),
        .init(id: "listen-a2-train", level: .a2, titleAr: "تأخر قطار", contextAr: "إعلان سفر", transcript: "The train to Dammam is delayed by approximately twenty-five minutes because of a technical inspection. Passengers should remain near gate six for further information.", firstQuestion: "How long is the delay?", firstAnswer: "about twenty-five minutes", secondQuestion: "Why is the train delayed?", secondAnswer: "a technical inspection"),
        .init(id: "listen-a2-task", level: .a2, titleAr: "مهمة عمل", contextAr: "تعليمات في العمل", transcript: "Could you update the sales table before lunch and send the final version to Huda? You can use last month's report as a guide, but check the new prices carefully.", firstQuestion: "What should be updated?", firstAnswer: "the sales table", secondQuestion: "Who should receive the final version?", secondAnswer: "Huda"),
        .init(id: "listen-b1-meeting", level: .b1, titleAr: "ملخص اجتماع", contextAr: "ملخص اجتماع مهني", transcript: "We agreed to test the new booking system with one branch first. Rania will train the staff on Sunday, and I will collect feedback after two weeks. We have not yet decided when to expand the trial.", firstQuestion: "Where will the system be tested first?", firstAnswer: "one branch", secondQuestion: "When will feedback be collected?", secondAnswer: "after two weeks"),
        .init(id: "listen-b1-customer", level: .b1, titleAr: "حل مشكلة عميل", contextAr: "خدمة عملاء", transcript: "I understand that the replacement arrived damaged as well. I can issue a full refund today, or arrange a different model with express delivery at no extra charge.", firstQuestion: "What two solutions are offered?", firstAnswer: "a refund or another model", secondQuestion: "What is free?", secondAnswer: "express delivery"),
        .init(id: "listen-b2-risk", level: .b2, titleAr: "تقرير مخاطر", contextAr: "عرض مخاطر", transcript: "The number of late approvals increased this quarter, but the rise was concentrated in two departments during a system migration. We recommend monitoring the indicator for another month before changing the control design.", firstQuestion: "Where was the increase concentrated?", firstAnswer: "two departments", secondQuestion: "Why wait before changing controls?", secondAnswer: "the system migration may explain the rise"),
        .init(id: "listen-b2-writing", level: .b2, titleAr: "تعليق أكاديمي", contextAr: "ملاحظة على كتابة", transcript: "Your argument is relevant, but the evidence is presented as a list rather than a connected analysis. Explain how each source supports the claim and address at least one credible counterargument.", firstQuestion: "What is the main structural problem?", firstAnswer: "evidence is listed without analysis", secondQuestion: "What additional element is requested?", secondAnswer: "a counterargument"),
        .init(id: "listen-c1-governance", level: .c1, titleAr: "مداخلة حوكمة", contextAr: "مداخلة متقدمة", transcript: "A policy exception is not inherently a governance failure. The concern arises when exceptions are undocumented, repeatedly approved by the same interested party, or never reviewed to determine whether the underlying rule remains appropriate.", firstQuestion: "When do exceptions become concerning?", firstAnswer: "when they lack independent documentation and review", secondQuestion: "What may need reconsideration?", secondAnswer: "the underlying rule"),
        .init(id: "listen-c1-decision", level: .c1, titleAr: "تحليل قرار", contextAr: "تحليل قانوني", transcript: "The committee's conclusion may be defensible, but its reasoning is too compressed for an affected person to understand which evidence was decisive. A fuller explanation would improve both accountability and the quality of any appeal.", firstQuestion: "What is wrong with the reasoning?", firstAnswer: "it does not show decisive evidence", secondQuestion: "What would a fuller explanation improve?", secondAnswer: "accountability and appeal quality")
    ]

    private static let writingSeeds: [WritingSeed] = [
        .init(id: "write-a0-self", level: .a0, kind: .sentence, titleAr: "عرّف بنفسك", prompt: "Write three short sentences about your name, city, and study or work.", promptAr: "اكتب ثلاث جمل قصيرة عن اسمك ومدينتك ودراستك أو عملك.", minimumWords: 15, suggestedWords: ["name", "live", "study", "work"], checklistAr: ["ابدأ كل جملة بحرف كبير.", "استخدم I am أو I live أو I study."], sample: "My name is Sami. I live in Riyadh. I study English every day."),
        .init(id: "write-a0-arrival", level: .a0, kind: .message, titleAr: "رسالة وصول", prompt: "Write a short message saying that you arrived safely and will call later.", promptAr: "اكتب رسالة قصيرة تقول فيها إنك وصلت بسلام وستتصل لاحقًا.", minimumWords: 12, suggestedWords: ["arrived", "safe", "call", "later"], checklistAr: ["اذكر الوصول.", "اذكر ما ستفعله لاحقًا."], sample: "I arrived safely. I am at the hotel now. I will call you later."),
        .init(id: "write-a1-appointment", level: .a1, kind: .email, titleAr: "تأكيد موعد", prompt: "Write a short email confirming an appointment on Monday at ten.", promptAr: "اكتب بريدًا قصيرًا تؤكد فيه موعدًا يوم الاثنين الساعة العاشرة.", minimumWords: 35, suggestedWords: ["confirm", "appointment", "Monday", "ten"], checklistAr: ["ابدأ بتحية.", "أكد اليوم والوقت.", "اختم بالشكر."], sample: "Hello, I am writing to confirm my appointment on Monday at ten o'clock. Please let me know if anything changes. Thank you."),
        .init(id: "write-a1-place", level: .a1, kind: .paragraph, titleAr: "مكان تحبه", prompt: "Describe a place you like and explain why you enjoy it.", promptAr: "صف مكانًا تحبه واشرح لماذا تستمتع به.", minimumWords: 45, suggestedWords: ["quiet", "because", "visit", "feel"], checklistAr: ["اذكر المكان.", "أضف سببين.", "استخدم because."], sample: "I like the park near my home because it is quiet and clean. I visit it in the evening with my family. I feel relaxed when I walk there."),
        .init(id: "write-a2-replacement", level: .a2, kind: .email, titleAr: "طلب استبدال منتج", prompt: "Write an email asking a store to replace a product that does not work.", promptAr: "اكتب بريدًا تطلب فيه استبدال منتج لا يعمل.", minimumWords: 70, suggestedWords: ["purchased", "problem", "replace", "receipt"], checklistAr: ["اذكر تاريخ الشراء.", "صف المشكلة بدقة.", "اطلب حلًا واضحًا."], sample: "Dear Customer Service, I purchased these headphones three days ago, but the left side does not work. I have attached the receipt. Could you please replace the item or explain the return process? Kind regards."),
        .init(id: "write-a2-incident", level: .a2, kind: .report, titleAr: "تقرير حادث بسيط", prompt: "Write a short factual report about a minor problem in an office.", promptAr: "اكتب تقريرًا واقعيًا قصيرًا عن مشكلة بسيطة في مكتب.", minimumWords: 80, suggestedWords: ["occurred", "noticed", "action", "resolved"], checklistAr: ["اذكر الوقت والمكان.", "افصل الوقائع عن الرأي.", "اذكر الإجراء المتخذ."], sample: "At 9:20 a.m., employees noticed water near the kitchen door. The area was closed temporarily, and facilities staff inspected the sink. They found a loose pipe and repaired it at 10:05 a.m. No one was injured."),
        .init(id: "write-b1-remote", level: .b1, kind: .opinion, titleAr: "العمل عن بُعد", prompt: "Do the benefits of remote work outweigh the disadvantages? Give your view with examples.", promptAr: "هل تتفوق فوائد العمل عن بُعد على عيوبه؟ اذكر رأيك مع أمثلة.", minimumWords: 120, suggestedWords: ["however", "because", "for example", "overall"], checklistAr: ["قدم موقفًا واضحًا.", "ناقش فائدة وعيبًا.", "اختم باستنتاج."], sample: "Remote work offers valuable flexibility because employees can avoid long commutes and organize focused tasks more easily. However, communication may become weaker if teams rely only on messages. For example, a short weekly video meeting can prevent misunderstandings. Overall, the benefits are greater when expectations and boundaries are clear."),
        .init(id: "write-b1-project", level: .b1, kind: .email, titleAr: "تحديث مشروع", prompt: "Write a project update explaining progress, one risk, and the next action.", promptAr: "اكتب تحديثًا لمشروع يشرح التقدم وخطرًا واحدًا والخطوة التالية.", minimumWords: 110, suggestedWords: ["completed", "risk", "deadline", "next"], checklistAr: ["ابدأ بملخص.", "اذكر الخطر وتأثيره.", "حدد الخطوة التالية."], sample: "Hello team, we have completed the first testing stage and resolved eight of the ten reported issues. The main risk is a delay in receiving the security review, which could affect Friday's deadline. Next, I will contact the review team today and provide a confirmed schedule tomorrow."),
        .init(id: "write-b2-plain", level: .b2, kind: .opinion, titleAr: "اللغة الواضحة في الأنظمة", prompt: "Argue for or against requiring public institutions to use plain language in important notices.", promptAr: "اكتب حجة مع أو ضد إلزام الجهات العامة باللغة الواضحة في الإشعارات المهمة.", minimumWords: 180, suggestedWords: ["although", "therefore", "access", "obligation"], checklistAr: ["عرّف موقفك.", "عالج اعتراضًا معقولًا.", "ميّز بين التبسيط وفقدان الدقة."], sample: "Public institutions should use plain language in important notices because rights are ineffective when people cannot understand how to exercise them. Although technical terms may sometimes be necessary, they can be defined rather than left unexplained. Clear structure and direct obligations improve access without removing legal precision. Therefore, plain-language review should be part of quality assurance."),
        .init(id: "write-b2-indicator", level: .b2, kind: .report, titleAr: "تحليل مؤشر أداء", prompt: "Write a short report interpreting a performance indicator that improved but may be misleading.", promptAr: "اكتب تقريرًا قصيرًا يفسر مؤشر أداء تحسن لكنه قد يكون مضللًا.", minimumWords: 180, suggestedWords: ["indicator", "however", "context", "recommend"], checklistAr: ["اذكر التحسن الرقمي.", "قدم تفسيرًا بديلًا.", "اقترح تحققًا قبل القرار."], sample: "The average response time fell from four days to two days during the quarter. However, the result coincided with a temporary reduction in new cases, so the indicator may overstate operational improvement. The team should compare similar workload periods and review the age of unresolved cases. I recommend delaying any staffing decision until these checks are complete."),
        .init(id: "write-c1-governance", level: .c1, kind: .report, titleAr: "مذكرة حوكمة", prompt: "Prepare an executive memorandum on repeated policy exceptions and recommend governance controls.", promptAr: "أعد مذكرة تنفيذية عن تكرار الاستثناءات من سياسة واقترح ضوابط حوكمة.", minimumWords: 260, suggestedWords: ["exception", "authority", "trend", "independent", "recommendation"], checklistAr: ["حدد المشكلة وآثارها.", "فرّق بين الاستثناء المشروع والتحايل.", "اقترح ملكية ومراجعة وشفافية."], sample: "Executive summary: policy exceptions have increased across three business units, with most approvals concentrated under a single authority. Exceptions can be legitimate, but repeated approvals without trend analysis may weaken the control environment. I recommend a central register, documented justification, expiry dates, independent approval for high-risk cases, and quarterly review by the governance committee."),
        .init(id: "write-c1-fairness", level: .c1, kind: .opinion, titleAr: "المساواة والتكييف المعقول", prompt: "Discuss why identical treatment may fail to produce procedural fairness.", promptAr: "ناقش لماذا قد لا تحقق المعاملة المتطابقة عدالة إجرائية.", minimumWords: 250, suggestedWords: ["identical", "barrier", "reasonable", "participation", "fairness"], checklistAr: ["ميز بين المساواة الشكلية والفعلية.", "قدم مثالًا.", "ضع حدًا للتكييف المعقول."], sample: "Identical treatment can preserve formal consistency while ignoring barriers that prevent meaningful participation. A person who cannot access a standard document is not given an equal opportunity merely because everyone received the same format. Reasonable adjustments should remove the barrier without changing the substantive standard or imposing disproportionate burdens. Procedural fairness therefore concerns the real ability to understand and respond, not ritual uniformity.")
    ]

    private static func makeReading(_ seed: ReadingSeed, variant: Int) -> ReadingPassage {
        let mainDistractors = variant == 1
            ? ["a shopping advertisement", "a travel timetable"]
            : ["a personal complaint only", "instructions for a machine"]
        let detailDistractors = variant == 1
            ? ["not mentioned", "the opposite happened"]
            : ["a different person", "at another time"]
        let vocabularyDistractors = variant == 1
            ? ["a place", "a number"]
            : ["the opposite meaning", "an unrelated action"]
        let id = "\(seed.id)-v\(variant)"
        return ReadingPassage(
            id: id,
            level: seed.level,
            title: variant == 1 ? seed.title : "Close Reading: \(seed.title)",
            titleAr: variant == 1 ? seed.titleAr : "قراءة دقيقة: \(seed.titleAr)",
            text: seed.text,
            estimatedMinutes: variant == 1 ? 3 : 5,
            topicAr: seed.topicAr,
            questions: [
                .init(id: "\(id)-main", prompt: "What is the main idea of the passage?", promptAr: "ما الفكرة الرئيسة للنص؟", choices: stableShuffle([seed.mainIdea] + mainDistractors, seed: "\(id)-main"), answer: seed.mainIdea, explanationAr: "اختر العبارة التي تغطي النص كله، لا تفصيلًا واحدًا فقط."),
                .init(id: "\(id)-detail", prompt: seed.detailQuestion, promptAr: "سؤال تفصيلي من النص", choices: stableShuffle([seed.detailAnswer] + detailDistractors, seed: "\(id)-detail"), answer: seed.detailAnswer, explanationAr: "الإجابة مذكورة أو مستدل عليها مباشرة من النص."),
                .init(id: "\(id)-word", prompt: "What does ‘\(seed.word)’ mean in this passage?", promptAr: "ما معنى \(seed.word) في السياق؟", choices: stableShuffle([seed.meaning] + vocabularyDistractors, seed: "\(id)-word"), answer: seed.meaning, explanationAr: "استدل على المعنى من الجملة المحيطة بالكلمة.")
            ]
        )
    }

    private static func makeListening(_ seed: ListeningSeed, variant: Int) -> ListeningPassage {
        let id = "\(seed.id)-v\(variant)"
        return ListeningPassage(
            id: id,
            level: seed.level,
            titleAr: variant == 1 ? seed.titleAr : "استماع دقيق: \(seed.titleAr)",
            transcript: seed.transcript,
            contextAr: seed.contextAr,
            recommendedReplays: variant == 1 ? 2 : 1,
            questions: [
                .init(id: "\(id)-q1", prompt: seed.firstQuestion, promptAr: "السؤال الأول", choices: listeningChoices(correct: seed.firstAnswer, seed: "\(id)-q1"), answer: seed.firstAnswer, explanationAr: "استمع للكلمات المرتبطة بالزمن أو المكان أو الإجراء المطلوب."),
                .init(id: "\(id)-q2", prompt: seed.secondQuestion, promptAr: "السؤال الثاني", choices: listeningChoices(correct: seed.secondAnswer, seed: "\(id)-q2"), answer: seed.secondAnswer, explanationAr: "راجع المعنى العام ثم استبعد الإجابات التي لم تُذكر.")
            ]
        )
    }

    private static func makeWriting(_ seed: WritingSeed, variant: Int) -> WritingPrompt {
        WritingPrompt(
            id: "\(seed.id)-v\(variant)",
            level: seed.level,
            kind: seed.kind,
            titleAr: variant == 1 ? seed.titleAr : "إعادة صياغة: \(seed.titleAr)",
            prompt: variant == 1 ? seed.prompt : "Rewrite the task with clearer organization, more precise vocabulary, and at least one connector. \(seed.prompt)",
            promptAr: variant == 1 ? seed.promptAr : "أعد تنفيذ المهمة بتنظيم أوضح ومفردات أدق وأداة ربط واحدة على الأقل. \(seed.promptAr)",
            minimumWords: variant == 1 ? seed.minimumWords : Int(Double(seed.minimumWords) * 1.15),
            suggestedWords: seed.suggestedWords,
            checklistAr: variant == 1 ? seed.checklistAr : seed.checklistAr + ["قارن الصياغة الجديدة بالمسودة الأولى.", "احذف عبارة عامة واستبدلها بتفصيل أدق."],
            sampleAnswer: seed.sample
        )
    }

    private static func listeningChoices(correct: String, seed: String) -> [String] {
        let generic = ["not mentioned", "a different time", "a different person", "because of the weather"]
        let distractors = generic.filter { $0.caseInsensitiveCompare(correct) != .orderedSame }
        return stableShuffle([correct] + Array(distractors.prefix(2)), seed: seed)
    }

    private static func stableShuffle(_ values: [String], seed: String) -> [String] {
        values.sorted { lhs, rhs in
            stableNumber("\(seed)-\(lhs)") < stableNumber("\(seed)-\(rhs)")
        }
    }

    private static func stableNumber(_ value: String) -> UInt64 {
        value.utf8.reduce(14_695_981_039_346_656_037) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}
