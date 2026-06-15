import Foundation

enum InteractiveStoryLibrary {
    static let stories: [InteractiveStory] = [
        build(
            id: "new-class", level: .a0,
            titleAr: "الطالب الجديد", titleEn: "The New Student",
            summaryAr: "تختار عبارات التحية والتعارف في أول يوم دراسي.",
            opening: "You enter a new class. A student smiles and says, ‘Hello!’",
            openingAr: "تدخل فصلًا جديدًا. يبتسم طالب ويقول: مرحبًا!",
            goodChoice: ("Hello! My name is Ali.", "مرحبًا! اسمي علي."),
            weakChoice: ("Goodbye, table.", "مع السلامة أيتها الطاولة."),
            middle: "The student says, ‘Nice to meet you, Ali. Do you need help?’",
            middleAr: "يقول الطالب: سعيد بلقائك يا علي. هل تحتاج مساعدة؟",
            finalGood: ("Yes, please. Where is my desk?", "نعم، من فضلك. أين مكتبي؟"),
            finalOther: ("No, thank you. I am ready.", "لا، شكرًا. أنا مستعد."),
            endingGood: ("confident", "بداية واثقة", "تعارفت وطلبت المساعدة بوضوح."),
            endingOther: ("independent", "بداية مستقلة", "أجبت بأدب وبدأت يومك بهدوء."),
            words: [("class","فصل"),("desk","مكتب"),("ready","مستعد")]
        ),
        build(
            id: "lost-key", level: .a0,
            titleAr: "المفتاح المفقود", titleEn: "The Lost Key",
            summaryAr: "تستخدم كلمات المكان لتبحث عن مفتاحك في المنزل.",
            opening: "Your key is not in your bag. Your sister asks, ‘Where is it?’",
            openingAr: "مفتاحك ليس في الحقيبة. تسأل أختك: أين هو؟",
            goodChoice: ("It may be on the table.", "قد يكون على الطاولة."),
            weakChoice: ("The key is hungry.", "المفتاح جائع."),
            middle: "You check the table. The key is not there, but you see it under a chair.",
            middleAr: "تفحص الطاولة. المفتاح ليس هناك، لكنك تراه تحت كرسي.",
            finalGood: ("The key is under the chair!", "المفتاح تحت الكرسي!"),
            finalOther: ("Please help me pick it up.", "من فضلك ساعدني في التقاطه."),
            endingGood: ("found", "وجدت المفتاح", "استخدمت under وحددت الموقع الصحيح."),
            endingOther: ("teamwork", "مساعدة لطيفة", "حددت المكان وطلبت المساعدة بأدب."),
            words: [("key","مفتاح"),("under","تحت"),("chair","كرسي")]
        ),
        build(
            id: "morning-bus", level: .a1,
            titleAr: "حافلة الصباح", titleEn: "The Morning Bus",
            summaryAr: "تقرر ما ستفعله عندما تتأخر عن الحافلة.",
            opening: "You wake up late. The bus leaves in ten minutes.",
            openingAr: "تستيقظ متأخرًا. ستغادر الحافلة بعد عشر دقائق.",
            goodChoice: ("I will get dressed quickly and leave now.", "سأرتدي ملابسي بسرعة وأغادر الآن."),
            weakChoice: ("Yesterday I am sleep tomorrow.", "أمس أنا أنام غدًا."),
            middle: "You reach the stop, but the bus has just left. A taxi is nearby.",
            middleAr: "تصل إلى الموقف، لكن الحافلة غادرت للتو. توجد سيارة أجرة قريبة.",
            finalGood: ("I will take the taxi to work.", "سأستقل سيارة الأجرة إلى العمل."),
            finalOther: ("I will call my manager and explain the delay.", "سأتصل بمديري وأشرح التأخير."),
            endingGood: ("on-time", "وصلت في الوقت", "اتخذت قرارًا سريعًا ووصلت إلى العمل."),
            endingOther: ("honest", "تواصل مسؤول", "أبلغت مديرك بالمشكلة بوضوح."),
            words: [("late","متأخر"),("leave","يغادر"),("delay","تأخير")]
        ),
        build(
            id: "wrong-order", level: .a1,
            titleAr: "الطلب الخطأ", titleEn: "The Wrong Order",
            summaryAr: "تعالج خطأ في طلب مطعم بعبارات مهذبة.",
            opening: "The waiter brings tea, but you ordered coffee.",
            openingAr: "يحضر النادل شايًا، لكنك طلبت قهوة.",
            goodChoice: ("Excuse me, I ordered coffee, not tea.", "عذرًا، طلبت قهوة لا شايًا."),
            weakChoice: ("This is terrible! Go away.", "هذا فظيع! اذهب بعيدًا."),
            middle: "The waiter apologizes and offers to change the drink.",
            middleAr: "يعتذر النادل ويعرض تغيير المشروب.",
            finalGood: ("Yes, please. Thank you for changing it.", "نعم، من فضلك. شكرًا لتغييره."),
            finalOther: ("Tea is fine. I can keep it.", "الشاي مناسب. يمكنني الاحتفاظ به."),
            endingGood: ("corrected", "تم تصحيح الطلب", "شرحت الخطأ بوضوح وأدب."),
            endingOther: ("flexible", "قرار مرن", "قبلت بديلًا مناسبًا دون مشكلة."),
            words: [("ordered","طلب"),("waiter","نادل"),("change","يغيّر")]
        ),
        build(
            id: "airport-gate", level: .a2,
            titleAr: "تغيير بوابة الرحلة", titleEn: "The Gate Change",
            summaryAr: "تفهم إعلانًا وتسأل عن اتجاه البوابة الجديدة.",
            opening: "An announcement says your flight now leaves from gate 24 instead of gate 12.",
            openingAr: "يعلن المطار أن رحلتك ستغادر من البوابة 24 بدلًا من 12.",
            goodChoice: ("Excuse me, how can I get to gate 24?", "عذرًا، كيف أصل إلى البوابة 24؟"),
            weakChoice: ("My gate is yesterday twelve.", "بوابتي أمس اثنا عشر."),
            middle: "The employee says, ‘Go straight, then take the elevator to the second floor.’",
            middleAr: "يقول الموظف: اذهب مستقيمًا، ثم خذ المصعد إلى الطابق الثاني.",
            finalGood: ("Thank you. Is it far from here?", "شكرًا. هل هي بعيدة من هنا؟"),
            finalOther: ("Could you repeat the directions slowly?", "هل يمكنك تكرار الاتجاهات ببطء؟"),
            endingGood: ("gate", "وصلت إلى البوابة", "أكدت المسافة وتبعت الاتجاهات."),
            endingOther: ("clarity", "طلبت توضيحًا", "طلب التكرار منعك من الذهاب في الاتجاه الخطأ."),
            words: [("announcement","إعلان"),("instead","بدلًا من"),("elevator","مصعد")]
        ),
        build(
            id: "doctor-visit", level: .a2,
            titleAr: "موعد الطبيب", titleEn: "The Doctor’s Appointment",
            summaryAr: "تشرح عرضًا صحيًا ومدته وتتلقى تعليمات بسيطة.",
            opening: "The doctor asks, ‘How long have you had this cough?’",
            openingAr: "يسأل الطبيب: منذ متى لديك هذا السعال؟",
            goodChoice: ("I have had it for three days.", "لدي السعال منذ ثلاثة أيام."),
            weakChoice: ("Three days coughs me yesterday.", "ثلاثة أيام يسعلني أمس."),
            middle: "The doctor says your lungs sound clear and asks about fever.",
            middleAr: "يقول الطبيب إن الرئتين تبدوان سليمتين ويسأل عن الحرارة.",
            finalGood: ("I do not have a fever, but I feel tired.", "ليست لدي حرارة، لكنني أشعر بالتعب."),
            finalOther: ("Should I take this medicine after food?", "هل آخذ هذا الدواء بعد الطعام؟"),
            endingGood: ("diagnosis", "وصف واضح", "قدمت معلومات تساعد الطبيب على التقييم."),
            endingOther: ("instructions", "تعليمات آمنة", "تأكدت من طريقة استخدام الدواء."),
            words: [("cough","سعال"),("fever","حرارة"),("medicine","دواء")]
        ),
        build(
            id: "team-deadline", level: .b1,
            titleAr: "موعد تسليم الفريق", titleEn: "The Team Deadline",
            summaryAr: "تقدم تحديثًا وتطلب دعمًا قبل موعد التسليم.",
            opening: "Your manager asks whether the report will be ready by Thursday.",
            openingAr: "يسأل مديرك هل سيكون التقرير جاهزًا بحلول الخميس.",
            goodChoice: ("The draft is complete, but the data section needs a final review.", "المسودة مكتملة، لكن قسم البيانات يحتاج مراجعة نهائية."),
            weakChoice: ("Maybe report yes no Thursday.", "ربما التقرير نعم لا الخميس."),
            middle: "A colleague offers to review the data this afternoon.",
            middleAr: "يعرض زميل مراجعة البيانات هذا المساء.",
            finalGood: ("That would help. Please send your comments by four.", "سيساعد ذلك. أرسل ملاحظاتك قبل الرابعة."),
            finalOther: ("I can finish alone, but I may need one extra day.", "يمكنني الإنهاء وحدي، لكن قد أحتاج يومًا إضافيًا."),
            endingGood: ("team", "تعاون ناجح", "حددت المطلوب والموعد بوضوح."),
            endingOther: ("renegotiated", "موعد واقعي", "شرحت المخاطرة وطلبت وقتًا منطقيًا."),
            words: [("draft","مسودة"),("review","مراجعة"),("deadline","موعد نهائي")]
        ),
        build(
            id: "neighbor-noise", level: .b1,
            titleAr: "ضوضاء الجيران", titleEn: "The Noisy Neighbor",
            summaryAr: "تعالج خلافًا يوميًا بهدوء وتقترح حلًا.",
            opening: "Music from the next apartment is loud after midnight.",
            openingAr: "الموسيقى من الشقة المجاورة مرتفعة بعد منتصف الليل.",
            goodChoice: ("Could you lower the music, please? I have work early tomorrow.", "هل يمكنك خفض الموسيقى؟ لدي عمل مبكرًا غدًا."),
            weakChoice: ("You always ruin everything!", "أنت تفسد كل شيء دائمًا!"),
            middle: "Your neighbor apologizes and says friends are visiting for one night.",
            middleAr: "يعتذر جارك ويقول إن أصدقاء يزورونه لليلة واحدة.",
            finalGood: ("Thank you. Keeping it low after midnight would be fine.", "شكرًا. خفض الصوت بعد منتصف الليل سيكون مناسبًا."),
            finalOther: ("Could we agree on a quiet time for future visits?", "هل نتفق على وقت هادئ للزيارات القادمة؟"),
            endingGood: ("peace", "حل هادئ", "شرحت احتياجك دون تصعيد."),
            endingOther: ("agreement", "اتفاق مستقبلي", "حولت المشكلة إلى قاعدة واضحة للطرفين."),
            words: [("lower","يخفض"),("midnight","منتصف الليل"),("agree","يتفق")]
        ),
        build(
            id: "flexible-policy", level: .b2,
            titleAr: "سياسة العمل المرن", titleEn: "The Flexible Work Policy",
            summaryAr: "توازن بين المرونة والتنسيق في نقاش مهني.",
            opening: "The company is considering three remote days each week. Some managers worry about coordination.",
            openingAr: "تدرس الشركة ثلاثة أيام عمل عن بعد أسبوعيًا. يقلق بعض المديرين من التنسيق.",
            goodChoice: ("The policy could improve flexibility, provided that teams keep fixed coordination hours.", "قد تحسن السياسة المرونة بشرط أن تحافظ الفرق على ساعات تنسيق ثابتة."),
            weakChoice: ("Remote work is perfect and has no risks.", "العمل عن بعد مثالي ولا مخاطر له."),
            middle: "The director asks how the company should measure whether the policy works.",
            middleAr: "يسأل المدير كيف تقيس الشركة نجاح السياسة.",
            finalGood: ("We could compare delivery time, employee feedback, and missed deadlines after three months.", "يمكن مقارنة وقت التسليم وآراء الموظفين والمواعيد الفائتة بعد ثلاثة أشهر."),
            finalOther: ("A one-month pilot may reveal the main coordination problems.", "قد تكشف تجربة لشهر واحد مشكلات التنسيق الأساسية."),
            endingGood: ("metrics", "قرار قائم على مؤشرات", "اقترحت مقاييس متعددة بدل الانطباع العام."),
            endingOther: ("pilot", "تجربة محسوبة", "قللت المخاطرة باختبار محدود قبل التوسع."),
            words: [("provided that","بشرط أن"),("measure","يقيس"),("pilot","تجربة أولية")]
        ),
        build(
            id: "service-complaint", level: .b2,
            titleAr: "شكوى خدمة احترافية", titleEn: "A Professional Service Complaint",
            summaryAr: "توثق المشكلة وتطلب حلًا محددًا دون لغة عدائية.",
            opening: "A device you ordered arrived damaged, and support has not replied for five days.",
            openingAr: "وصل جهاز طلبته تالفًا، ولم ترد خدمة الدعم منذ خمسة أيام.",
            goodChoice: ("I am following up on order 204, which arrived damaged last Monday.", "أتابع الطلب 204 الذي وصل تالفًا الاثنين الماضي."),
            weakChoice: ("Your company is the worst in history.", "شركتكم الأسوأ في التاريخ."),
            middle: "The agent apologizes and offers either a refund or a replacement.",
            middleAr: "يعتذر الموظف ويعرض استرداد المبلغ أو الاستبدال.",
            finalGood: ("I would prefer a replacement, with written confirmation of the delivery date.", "أفضل الاستبدال مع تأكيد مكتوب لموعد التسليم."),
            finalOther: ("A full refund would be acceptable if it is processed this week.", "سيكون الاسترداد الكامل مناسبًا إذا نُفذ هذا الأسبوع."),
            endingGood: ("replacement", "استبدال موثق", "طلبت حلًا محددًا وآلية متابعة."),
            endingOther: ("refund", "استرداد واضح", "حددت البديل المقبول والإطار الزمني."),
            words: [("following up","أتابع"),("damaged","تالف"),("confirmation","تأكيد")]
        ),
        build(
            id: "research-claim", level: .c1,
            titleAr: "ادعاء بحثي تحت الاختبار", titleEn: "A Research Claim Under Test",
            summaryAr: "تصوغ استنتاجًا علميًا متحفظًا أمام أدلة محدودة.",
            opening: "A pilot study reports a large improvement, but it included only eighteen participants and no control group.",
            openingAr: "تذكر دراسة أولية تحسنًا كبيرًا، لكنها شملت 18 مشاركًا فقط دون مجموعة ضابطة.",
            goodChoice: ("The result is promising, but the design does not justify a definitive causal claim.", "النتيجة واعدة، لكن التصميم لا يبرر ادعاءً سببيًا قاطعًا."),
            weakChoice: ("This proves the method works for everyone.", "هذا يثبت أن الطريقة تنجح مع الجميع."),
            middle: "A colleague asks what evidence would make the conclusion more reliable.",
            middleAr: "يسأل زميل ما الأدلة التي تجعل الاستنتاج أكثر موثوقية.",
            finalGood: ("A larger randomized sample and an appropriate comparison group would strengthen the inference.", "ستقوي عينة عشوائية أكبر ومجموعة مقارنة مناسبة الاستدلال."),
            finalOther: ("Replicating the study in different settings would test whether the effect is robust.", "سيختبر تكرار الدراسة في بيئات مختلفة متانة الأثر."),
            endingGood: ("method", "تحسين منهجي", "ربطت قوة الاستنتاج بتصميم الدراسة."),
            endingOther: ("replication", "اختبار المتانة", "اقترحت تكرارًا يكشف قابلية تعميم النتيجة."),
            words: [("definitive","قاطع"),("inference","استدلال"),("robust","متين")]
        ),
        build(
            id: "contract-negotiation", level: .c1,
            titleAr: "تفاوض على عقد", titleEn: "Contract Negotiation",
            summaryAr: "تعالج تحفظًا زمنيًا وتقترح التزامات قابلة للقياس.",
            opening: "The other party accepts the scope but argues that the delivery schedule is too aggressive.",
            openingAr: "يقبل الطرف الآخر نطاق العمل لكنه يرى جدول التسليم شديد الضغط.",
            goodChoice: ("I understand the concern. We could phase delivery without changing the core scope.", "أتفهم التحفظ. يمكننا تقسيم التسليم إلى مراحل دون تغيير النطاق الأساسي."),
            weakChoice: ("The schedule is final, so there is nothing to discuss.", "الجدول نهائي ولا شيء للنقاش."),
            middle: "They ask how delayed milestones would be handled without creating uncertainty.",
            middleAr: "يسألون كيف ستعالج المراحل المتأخرة دون خلق غموض.",
            finalGood: ("Each milestone could have a cure period, a named owner, and written escalation steps.", "يمكن أن تكون لكل مرحلة مهلة معالجة ومسؤول محدد وخطوات تصعيد مكتوبة."),
            finalOther: ("We could hold a weekly risk review and revise only the affected milestone.", "يمكن عقد مراجعة مخاطر أسبوعية وتعديل المرحلة المتأثرة فقط."),
            endingGood: ("framework", "إطار قابل للتنفيذ", "حولت القلق إلى التزامات وإجراءات واضحة."),
            endingOther: ("adaptive", "متابعة مرنة", "اقترحت رقابة دورية دون زعزعة العقد كله."),
            words: [("phase","يقسم إلى مراحل"),("milestone","مرحلة إنجاز"),("escalation","تصعيد")]
        )
    ]

    private static func build(
        id: String,
        level: CEFRLevel,
        titleAr: String,
        titleEn: String,
        summaryAr: String,
        opening: String,
        openingAr: String,
        goodChoice: (String, String),
        weakChoice: (String, String),
        middle: String,
        middleAr: String,
        finalGood: (String, String),
        finalOther: (String, String),
        endingGood: (String, String, String),
        endingOther: (String, String, String),
        words: [(String, String)]
    ) -> InteractiveStory {
        let startID = "\(id)-start"
        let middleID = "\(id)-middle"
        let retryID = "\(id)-retry"
        let goodEndID = "\(id)-good-end"
        let otherEndID = "\(id)-other-end"
        let scenes = [
            StoryScene(
                id: startID,
                english: opening,
                arabic: openingAr,
                narratorHintAr: "اختر الرد الذي يناسب الموقف والمعنى.",
                choices: [
                    StoryChoice(id: "\(id)-c1-good", english: goodChoice.0, arabic: goodChoice.1, nextSceneID: middleID, points: 10, feedbackAr: "رد طبيعي ومناسب."),
                    StoryChoice(id: "\(id)-c1-weak", english: weakChoice.0, arabic: weakChoice.1, nextSceneID: retryID, points: 0, feedbackAr: "المعنى أو الأسلوب غير مناسب، وستحصل على فرصة لتصحيحه.")
                ],
                ending: nil
            ),
            StoryScene(
                id: retryID,
                english: "You pause, reformulate your sentence, and continue more clearly.",
                arabic: "تتوقف لحظة، ثم تعيد صياغة الجملة وتتابع بوضوح أكبر.",
                narratorHintAr: "التصحيح جزء طبيعي من تعلم اللغة.",
                choices: [
                    StoryChoice(id: "\(id)-retry-choice", english: goodChoice.0, arabic: goodChoice.1, nextSceneID: middleID, points: 5, feedbackAr: "ممتاز، صححت العبارة وأكملت الموقف.")
                ],
                ending: nil
            ),
            StoryScene(
                id: middleID,
                english: middle,
                arabic: middleAr,
                narratorHintAr: "كلا الخيارين ممكن، لكنهما يقودان إلى نتيجتين مختلفتين.",
                choices: [
                    StoryChoice(id: "\(id)-c2-good", english: finalGood.0, arabic: finalGood.1, nextSceneID: goodEndID, points: 10, feedbackAr: "اختيار دقيق يدفع الموقف إلى الأمام."),
                    StoryChoice(id: "\(id)-c2-other", english: finalOther.0, arabic: finalOther.1, nextSceneID: otherEndID, points: 8, feedbackAr: "اختيار صحيح بأسلوب مختلف.")
                ],
                ending: nil
            ),
            StoryScene(id: goodEndID, english: "The situation ends successfully.", arabic: endingGood.2, narratorHintAr: nil, choices: [], ending: StoryEnding(id: endingGood.0, titleAr: endingGood.1, messageAr: endingGood.2)),
            StoryScene(id: otherEndID, english: "The situation reaches another successful ending.", arabic: endingOther.2, narratorHintAr: nil, choices: [], ending: StoryEnding(id: endingOther.0, titleAr: endingOther.1, messageAr: endingOther.2))
        ]
        let vocabulary = words.enumerated().map { index, pair in
            VocabularyWord(
                id: "story-\(id)-word-\(index + 1)",
                english: pair.0,
                arabic: pair.1,
                example: opening,
                exampleArabic: openingAr,
                partOfSpeech: "story word",
                phonetic: nil
            )
        }
        return InteractiveStory(
            id: id,
            level: level,
            titleAr: titleAr,
            titleEn: titleEn,
            summaryAr: summaryAr,
            startSceneID: startID,
            scenes: scenes,
            keyWords: vocabulary
        )
    }
}
