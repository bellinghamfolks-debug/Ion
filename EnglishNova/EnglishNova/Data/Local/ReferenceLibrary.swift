import Foundation

enum ReferenceLibrary {
    static let grammar: [GrammarTopic] = [
        GrammarTopic(
            id: "be-present",
            level: .a0,
            titleAr: "فعل الكينونة في الحاضر",
            titleEn: "The Verb Be",
            summaryAr: "نستخدم am مع I، وis مع he وshe وit، وare مع you وwe وthey.",
            formula: "Subject + am/is/are + complement",
            examples: [
                .init(english: "I am ready.", arabic: "أنا مستعد."),
                .init(english: "She is a student.", arabic: "هي طالبة."),
                .init(english: "They are at home.", arabic: "هم في المنزل.")
            ],
            commonMistakes: ["I is ready ✗  والصحيح I am ready.", "He are here ✗  والصحيح He is here."]
        ),
        GrammarTopic(
            id: "present-simple",
            level: .a1,
            titleAr: "المضارع البسيط",
            titleEn: "Present Simple",
            summaryAr: "يصف العادات والحقائق. نضيف s أو es غالبًا مع he وshe وit.",
            formula: "Subject + base verb / verb+s",
            examples: [
                .init(english: "I work in Riyadh.", arabic: "أعمل في الرياض."),
                .init(english: "He works every day.", arabic: "هو يعمل كل يوم."),
                .init(english: "Do you speak English?", arabic: "هل تتحدث الإنجليزية؟")
            ],
            commonMistakes: ["He work every day ✗  والصحيح He works every day.", "I am work ✗  والصحيح I work."]
        ),
        GrammarTopic(
            id: "past-simple",
            level: .a2,
            titleAr: "الماضي البسيط",
            titleEn: "Past Simple",
            summaryAr: "يصف حدثًا انتهى في وقت ماضٍ محدد. بعض الأفعال منتظمة وبعضها شاذ.",
            formula: "Subject + past verb",
            examples: [
                .init(english: "I visited Jeddah last week.", arabic: "زرت جدة الأسبوع الماضي."),
                .init(english: "She went home early.", arabic: "ذهبت إلى المنزل مبكرًا."),
                .init(english: "Did you call him?", arabic: "هل اتصلت به؟")
            ],
            commonMistakes: ["Did you went? ✗  والصحيح Did you go?", "I go yesterday ✗  والصحيح I went yesterday."]
        ),
        GrammarTopic(
            id: "present-perfect",
            level: .b1,
            titleAr: "المضارع التام",
            titleEn: "Present Perfect",
            summaryAr: "يربط الماضي بالحاضر، ويستخدم للتجارب أو النتائج الحالية أو مدة مستمرة.",
            formula: "Subject + have/has + past participle",
            examples: [
                .init(english: "I have finished the report.", arabic: "أنهيت التقرير."),
                .init(english: "She has lived here for five years.", arabic: "تعيش هنا منذ خمس سنوات."),
                .init(english: "Have you ever traveled alone?", arabic: "هل سبق أن سافرت وحدك؟")
            ],
            commonMistakes: ["I have went ✗  والصحيح I have gone.", "She have finished ✗  والصحيح She has finished."]
        ),
        GrammarTopic(
            id: "conditionals",
            level: .b2,
            titleAr: "الجمل الشرطية",
            titleEn: "Conditionals",
            summaryAr: "تعبّر عن نتائج حقيقية أو محتملة أو افتراضية بحسب الزمن والبنية.",
            formula: "If-clause + result clause",
            examples: [
                .init(english: "If it rains, we will stay home.", arabic: "إذا أمطرت فسنبقى في المنزل."),
                .init(english: "If I had more time, I would study French.", arabic: "لو كان لدي وقت أكثر لدرست الفرنسية."),
                .init(english: "If she had called, I would have answered.", arabic: "لو اتصلت لأجبتها.")
            ],
            commonMistakes: ["If I will go ✗ في الشرط الأول، والصحيح If I go.", "If I would have ✗  والصحيح If I had."]
        ),
        GrammarTopic(
            id: "hedging",
            level: .c1,
            titleAr: "التحفظ والدقة الأكاديمية",
            titleEn: "Academic Hedging",
            summaryAr: "تُستخدم كلمات مثل may وappears وsuggests لتجنب الجزم عندما لا تكون الأدلة قاطعة.",
            formula: "Evidence + cautious reporting verb/modal + claim",
            examples: [
                .init(english: "The findings may indicate a gradual shift.", arabic: "قد تشير النتائج إلى تحول تدريجي."),
                .init(english: "This appears to be the most plausible explanation.", arabic: "يبدو أن هذا هو التفسير الأكثر معقولية."),
                .init(english: "The data suggests that further research is needed.", arabic: "تشير البيانات إلى الحاجة لمزيد من البحث.")
            ],
            commonMistakes: ["The study proves... عند محدودية البيانات، والأدق may suggest.", "تكديس كلمات التحفظ حتى تصبح الجملة غامضة."]
        )
    ]

    static let stories: [GradedStory] = [
        GradedStory(
            id: "first-day",
            level: .a0,
            titleAr: "اليوم الأول",
            titleEn: "The First Day",
            paragraphs: [
                .init(english: "Ali is a new student.", arabic: "علي طالب جديد."),
                .init(english: "He says, ‘Hello, my name is Ali.’", arabic: "يقول: مرحبًا، اسمي علي."),
                .init(english: "Sara says, ‘Welcome, Ali.’", arabic: "تقول سارة: أهلًا بك يا علي.")
            ],
            keyWords: [
                .init(id: "story-new", english: "new", arabic: "جديد", example: "Ali is new.", exampleArabic: "علي جديد.", partOfSpeech: "adjective", phonetic: "/nuː/"),
                .init(id: "story-welcome", english: "welcome", arabic: "أهلًا بك", example: "Welcome to our class.", exampleArabic: "أهلًا بك في فصلنا.", partOfSpeech: "phrase", phonetic: nil)
            ],
            questions: [.init(id: "q1", promptAr: "ما اسم الطالب الجديد؟", choices: ["Ali", "Sara", "Omar"], answer: "Ali")]
        ),
        GradedStory(
            id: "missed-bus",
            level: .a1,
            titleAr: "الحافلة الفائتة",
            titleEn: "The Missed Bus",
            paragraphs: [
                .init(english: "Mona wakes up late on Monday.", arabic: "تستيقظ منى متأخرة يوم الاثنين."),
                .init(english: "She runs to the bus stop, but the bus leaves.", arabic: "تركض إلى موقف الحافلة، لكن الحافلة تغادر."),
                .init(english: "She calls a taxi and arrives at work at nine.", arabic: "تطلب سيارة أجرة وتصل إلى العمل الساعة التاسعة.")
            ],
            keyWords: [
                .init(id: "story-late", english: "late", arabic: "متأخر", example: "I am late.", exampleArabic: "أنا متأخر.", partOfSpeech: "adjective", phonetic: "/leɪt/"),
                .init(id: "story-bus-stop", english: "bus stop", arabic: "موقف الحافلة", example: "Wait at the bus stop.", exampleArabic: "انتظر عند موقف الحافلة.", partOfSpeech: "noun", phonetic: nil)
            ],
            questions: [.init(id: "q1", promptAr: "كيف ذهبت منى إلى العمل؟", choices: ["By bus", "By taxi", "On foot"], answer: "By taxi")]
        ),
        GradedStory(
            id: "lost-luggage",
            level: .a2,
            titleAr: "الحقيبة المفقودة",
            titleEn: "The Lost Luggage",
            paragraphs: [
                .init(english: "Fahad arrived at the airport after a long flight.", arabic: "وصل فهد إلى المطار بعد رحلة طويلة."),
                .init(english: "His suitcase did not appear on the baggage belt.", arabic: "لم تظهر حقيبته على سير الأمتعة."),
                .init(english: "He reported the problem, and the airline delivered the bag the next morning.", arabic: "أبلغ عن المشكلة، وأوصلت شركة الطيران الحقيبة في صباح اليوم التالي.")
            ],
            keyWords: [
                .init(id: "story-suitcase", english: "suitcase", arabic: "حقيبة سفر", example: "My suitcase is black.", exampleArabic: "حقيبة سفري سوداء.", partOfSpeech: "noun", phonetic: "/ˈsuːtkeɪs/"),
                .init(id: "story-report", english: "report", arabic: "يبلغ", example: "Please report the problem.", exampleArabic: "يرجى الإبلاغ عن المشكلة.", partOfSpeech: "verb", phonetic: nil)
            ],
            questions: [.init(id: "q1", promptAr: "متى وصلت الحقيبة؟", choices: ["The same night", "The next morning", "A week later"], answer: "The next morning")]
        ),
        GradedStory(
            id: "team-decision",
            level: .b1,
            titleAr: "قرار الفريق",
            titleEn: "The Team Decision",
            paragraphs: [
                .init(english: "The team had to choose between two project plans.", arabic: "كان على الفريق الاختيار بين خطتين للمشروع."),
                .init(english: "They compared the cost, time, and risks before discussing their opinions.", arabic: "قارنوا التكلفة والوقت والمخاطر قبل مناقشة آرائهم."),
                .init(english: "In the end, they selected the simpler plan because it could be delivered on time.", arabic: "في النهاية اختاروا الخطة الأبسط لأنها قابلة للتسليم في الوقت المحدد.")
            ],
            keyWords: [
                .init(id: "story-compare", english: "compare", arabic: "يقارن", example: "Compare the two options.", exampleArabic: "قارن الخيارين.", partOfSpeech: "verb", phonetic: nil),
                .init(id: "story-risk", english: "risk", arabic: "مخاطرة", example: "The risk is low.", exampleArabic: "المخاطرة منخفضة.", partOfSpeech: "noun", phonetic: nil)
            ],
            questions: [.init(id: "q1", promptAr: "لماذا اختار الفريق الخطة الأبسط؟", choices: ["It was more expensive", "It could be delivered on time", "It had more risks"], answer: "It could be delivered on time")]
        ),
        GradedStory(
            id: "balanced-policy",
            level: .b2,
            titleAr: "سياسة متوازنة",
            titleEn: "A Balanced Policy",
            paragraphs: [
                .init(english: "A company proposed a flexible work policy to improve employee satisfaction.", arabic: "اقترحت شركة سياسة عمل مرنة لتحسين رضا الموظفين."),
                .init(english: "Supporters emphasized productivity, whereas critics raised concerns about coordination.", arabic: "أكد المؤيدون الإنتاجية، بينما أثار المنتقدون مخاوف بشأن التنسيق."),
                .init(english: "The final policy combined remote days with regular in-person meetings.", arabic: "جمعت السياسة النهائية بين أيام العمل عن بعد والاجتماعات الحضورية المنتظمة.")
            ],
            keyWords: [
                .init(id: "story-whereas", english: "whereas", arabic: "بينما", example: "One plan is cheap, whereas the other is fast.", exampleArabic: "إحدى الخطتين رخيصة، بينما الأخرى سريعة.", partOfSpeech: "conjunction", phonetic: nil),
                .init(id: "story-coordination", english: "coordination", arabic: "تنسيق", example: "Good coordination saves time.", exampleArabic: "التنسيق الجيد يوفر الوقت.", partOfSpeech: "noun", phonetic: nil)
            ],
            questions: [.init(id: "q1", promptAr: "ماذا جمعت السياسة النهائية؟", choices: ["Only remote work", "Only office work", "Remote days and in-person meetings"], answer: "Remote days and in-person meetings")]
        ),
        GradedStory(
            id: "research-claim",
            level: .c1,
            titleAr: "ادعاء تحت المجهر",
            titleEn: "A Claim Under Scrutiny",
            paragraphs: [
                .init(english: "A widely shared article claimed that a new method dramatically improved learning outcomes.", arabic: "ادعى مقال واسع الانتشار أن طريقة جديدة حسنت نتائج التعلم بصورة كبيرة."),
                .init(english: "A closer examination revealed a small sample and no appropriate comparison group.", arabic: "كشف الفحص الأدق عن عينة صغيرة وعدم وجود مجموعة مقارنة مناسبة."),
                .init(english: "The method may still be promising, but the available evidence does not justify a definitive conclusion.", arabic: "قد تظل الطريقة واعدة، لكن الأدلة المتاحة لا تبرر استنتاجًا قاطعًا.")
            ],
            keyWords: [
                .init(id: "story-scrutiny", english: "scrutiny", arabic: "تدقيق صارم", example: "The claim did not survive scrutiny.", exampleArabic: "لم يصمد الادعاء أمام التدقيق.", partOfSpeech: "noun", phonetic: nil),
                .init(id: "story-definitive", english: "definitive", arabic: "قاطع", example: "There is no definitive answer.", exampleArabic: "لا توجد إجابة قاطعة.", partOfSpeech: "adjective", phonetic: nil)
            ],
            questions: [.init(id: "q1", promptAr: "لماذا لا يمكن قبول الاستنتاج بوصفه قاطعًا؟", choices: ["The article was long", "The sample was small and comparison was missing", "The method was old"], answer: "The sample was small and comparison was missing")]
        )
    ]

    static let achievements: [AchievementDefinition] = [
        .init(id: "first-step", titleAr: "الخطوة الأولى", descriptionAr: "احصل على أول 20 نقطة.", systemImage: "figure.walk", requiredPoints: 20),
        .init(id: "warm-up", titleAr: "المحرّك بدأ", descriptionAr: "اجمع 100 نقطة.", systemImage: "flame.fill", requiredPoints: 100),
        .init(id: "builder", titleAr: "بنّاء الجمل", descriptionAr: "اجمع 300 نقطة.", systemImage: "hammer.fill", requiredPoints: 300),
        .init(id: "navigator", titleAr: "مستكشف اللغة", descriptionAr: "اجمع 700 نقطة.", systemImage: "map.fill", requiredPoints: 700),
        .init(id: "master-track", titleAr: "على طريق الاحتراف", descriptionAr: "اجمع 1500 نقطة.", systemImage: "crown.fill", requiredPoints: 1500)
    ]
}
