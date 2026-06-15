import Foundation

enum PlacementQuestionBank {
    static let all: [PlacementQuestion] = [
        q("a0-v1", .a0, .vocabulary, "Choose the greeting.", "اختر التحية.", ["Hello", "Table", "Seven"], "Hello", "Hello تحية.", 0.9),
        q("a0-g1", .a0, .grammar, "I ___ Abdullah.", "اختر الكلمة الصحيحة.", ["am", "is", "are"], "am", "نستخدم am مع I.", 1.0),
        q("a0-r1", .a0, .reading, "The bag is blue. What is blue?", "اقرأ ثم اختر.", ["The bag", "The table", "The phone"], "The bag", "الجملة تقول إن الحقيبة زرقاء.", 0.9),
        q("a0-l1", .a0, .listening, "Listen and choose the word.", "استمع واختر الكلمة.", ["water", "window", "winter"], "water", "الكلمة المنطوقة water.", 1.1, "water"),
        q("a0-p1", .a0, .practicalCommunication, "You want help. What do you say?", "تريد مساعدة. ماذا تقول؟", ["I need help, please.", "I am a table.", "Goodbye yesterday."], "I need help, please.", "هذه العبارة طلب واضح ومهذب.", 1.1),
        q("a0-v2", .a0, .vocabulary, "What does ‘mother’ mean?", "ما معنى mother؟", ["أم", "أخ", "صديق"], "أم", "mother تعني أم.", 0.8),
        q("a0-g2", .a0, .grammar, "___ is my book.", "الكتاب قريب منك.", ["This", "These", "They"], "This", "This للمفرد القريب.", 1.0),
        q("a0-p2", .a0, .practicalCommunication, "Ask someone to repeat.", "اطلب من شخص أن يكرر.", ["Can you repeat, please?", "Where are repeat?", "I repeat yesterday."], "Can you repeat, please?", "صيغة مهذبة لطلب التكرار.", 1.2),

        q("a1-v1", .a1, .vocabulary, "Choose the word for a planned meeting time.", "اختر كلمة الموعد.", ["appointment", "weather", "wallet"], "appointment", "appointment تعني موعدًا محددًا.", 1.0),
        q("a1-g1", .a1, .grammar, "She ___ to work every day.", "اختر الفعل الصحيح.", ["go", "goes", "went"], "goes", "نضيف s مع she في الحاضر البسيط.", 1.1),
        q("a1-r1", .a1, .reading, "Mona missed the bus, so she took a taxi. How did she travel?", "كيف انتقلت منى؟", ["By taxi", "By bus", "By train"], "By taxi", "النص يقول إنها أخذت سيارة أجرة.", 1.0),
        q("a1-l1", .a1, .listening, "Listen and choose the time.", "استمع واختر الوقت.", ["nine thirty", "nine thirteen", "five thirty"], "nine thirty", "الوقت المنطوق nine thirty.", 1.1, "The meeting starts at nine thirty."),
        q("a1-p1", .a1, .practicalCommunication, "Ask for the price of a shirt.", "اسأل عن سعر قميص.", ["How much is this shirt?", "How many shirt time?", "Where price is?"], "How much is this shirt?", "How much تستخدم للسؤال عن السعر.", 1.2),
        q("a1-g2", .a1, .grammar, "Yesterday, I ___ a movie.", "اختر الماضي الصحيح.", ["watched", "watch", "am watching"], "watched", "Yesterday يحتاج إلى الماضي.", 1.2),
        q("a1-v2", .a1, .vocabulary, "A place where you buy medicine is a ___.", "مكان شراء الدواء.", ["pharmacy", "station", "museum"], "pharmacy", "pharmacy تعني صيدلية.", 1.0),
        q("a1-p2", .a1, .practicalCommunication, "You received the wrong item. Choose the clearest sentence.", "استلمت منتجًا خطأ.", ["I received the wrong item.", "The item received me.", "Wrong is yesterday."], "I received the wrong item.", "جملة واضحة لخدمة العملاء.", 1.3),

        q("a2-v1", .a2, .vocabulary, "Choose the closest meaning of ‘delay’.", "اختر معنى delay.", ["تأخير", "مغادرة", "حجز"], "تأخير", "delay تعني تأخيرًا.", 1.1),
        q("a2-g1", .a2, .grammar, "I have lived here ___ 2022.", "اختر حرف الجر الصحيح.", ["since", "for", "during"], "since", "since مع نقطة بداية زمنية.", 1.3),
        q("a2-r1", .a2, .reading, "The shop closes at six, but Omar arrived at six fifteen. Why could he not enter?", "لماذا لم يدخل عمر؟", ["The shop was closed.", "He had no money.", "It was too far."], "The shop was closed.", "وصل بعد وقت الإغلاق.", 1.2),
        q("a2-l1", .a2, .listening, "Listen and choose the reason.", "استمع واختر السبب.", ["because of the weather", "because of the price", "because of the manager"], "because of the weather", "هذا هو السبب المذكور في المقطع.", 1.3, "The flight was delayed because of the weather."),
        q("a2-p1", .a2, .practicalCommunication, "Politely ask to change a hotel room.", "اطلب تغيير غرفة الفندق بأدب.", ["Could I change my room, please?", "Change room now me.", "My room changes you."], "Could I change my room, please?", "Could I صيغة طلب مهذبة.", 1.4),
        q("a2-g2", .a2, .grammar, "This phone is ___ than my old phone.", "اختر صيغة المقارنة.", ["faster", "fastest", "more fast"], "faster", "faster صيغة المقارنة من fast.", 1.2),
        q("a2-v2", .a2, .vocabulary, "If something is ‘available’, it is ___.", "معنى available.", ["ready to use or buy", "completely broken", "very expensive"], "ready to use or buy", "available يعني متاحًا.", 1.2),
        q("a2-p2", .a2, .practicalCommunication, "Explain a symptom and its duration.", "اشرح عرضًا ومدته.", ["I have had a cough for three days.", "I cough since three day ago have.", "Three days are cough."], "I have had a cough for three days.", "صياغة طبيعية للعرض والمدة.", 1.5),

        q("b1-v1", .b1, .vocabulary, "Choose the closest meaning of ‘reliable’.", "اختر معنى reliable.", ["يمكن الاعتماد عليه", "مؤقت جدًا", "غامض"], "يمكن الاعتماد عليه", "reliable تعني جديرًا بالاعتماد.", 1.2),
        q("b1-g1", .b1, .grammar, "If I have time, I ___ you tonight.", "اختر الشرط الأول.", ["will call", "would call", "called"], "will call", "الشرط الأول: present + will.", 1.4),
        q("b1-r1", .b1, .reading, "The team chose the simpler plan because it could be delivered on time, although it offered fewer features. What was their priority?", "ما أولوية الفريق؟", ["Meeting the deadline", "Adding every feature", "Increasing the budget"], "Meeting the deadline", "اختاروا الخطة القابلة للتسليم في الوقت.", 1.4),
        q("b1-l1", .b1, .listening, "Listen and identify the requested action.", "استمع وحدد المطلوب.", ["Send feedback today", "Cancel the project", "Rewrite the entire report"], "Send feedback today", "المتحدث يطلب إرسال الملاحظات قبل نهاية اليوم.", 1.5, "Please send me your feedback by the end of the day."),
        q("b1-p1", .b1, .practicalCommunication, "Give a concise work update.", "قدّم تحديثًا مهنيًا موجزًا.", ["I finished the draft, but it needs a final review.", "Draft finish maybe review thing.", "I am finish yesterday perhaps."], "I finished the draft, but it needs a final review.", "التحديث يذكر الإنجاز والخطوة الباقية.", 1.5),
        q("b1-g2", .b1, .grammar, "The report ___ before the meeting started.", "اختر الزمن الأنسب.", ["had been sent", "has send", "was sending by"], "had been sent", "الماضي التام يوضح الحدث الأسبق.", 1.6),
        q("b1-v2", .b1, .vocabulary, "A ‘deadline’ is ___.", "ما معنى deadline؟", ["the latest time to finish something", "a short holiday", "a type of meeting"], "the latest time to finish something", "deadline هو الموعد النهائي.", 1.2),
        q("b1-p2", .b1, .practicalCommunication, "Disagree politely in a meeting.", "اعترض بأدب في اجتماع.", ["I see your point, but I have a different concern.", "You are completely wrong.", "No. Bad idea."], "I see your point, but I have a different concern.", "تعترف بالرأي ثم تعرض تحفظك.", 1.6),

        q("b2-v1", .b2, .vocabulary, "Choose the closest meaning of ‘feasible’.", "اختر معنى feasible.", ["practical and possible", "legally forbidden", "already completed"], "practical and possible", "feasible يعني قابلًا للتنفيذ.", 1.3),
        q("b2-g1", .b2, .grammar, "The policy, ___ was introduced last year, has reduced delays.", "اختر أداة الوصل.", ["which", "what", "whereas"], "which", "which تبدأ جملة وصفية غير مقيدة.", 1.5),
        q("b2-r1", .b2, .reading, "Supporters emphasized flexibility, whereas critics worried about coordination. The final policy required regular in-person meetings. What compromise was made?", "ما الحل التوفيقي؟", ["Flexible work with scheduled meetings", "A complete ban on remote work", "No coordination rules"], "Flexible work with scheduled meetings", "جُمعت المرونة مع اجتماعات منتظمة.", 1.6),
        q("b2-l1", .b2, .listening, "Listen and identify the speaker’s reservation.", "استمع وحدد التحفظ.", ["The timeline may be unrealistic.", "The proposal has no benefit.", "The budget has already been approved."], "The timeline may be unrealistic.", "المتحدث يرحب بالفكرة لكنه يتحفظ على الجدول.", 1.7, "The proposal is promising; however, the timeline may be unrealistic."),
        q("b2-p1", .b2, .practicalCommunication, "Request a remedy in a professional complaint.", "اطلب معالجة مهنية للشكوى.", ["I would appreciate a replacement and written confirmation of the delivery date.", "Send another one now or else.", "My delivery date replacement appreciate."], "I would appreciate a replacement and written confirmation of the delivery date.", "طلب واضح ومهني ومحدد.", 1.7),
        q("b2-g2", .b2, .grammar, "Had they reviewed the data earlier, they ___ the error.", "اختر نتيجة الشرط الثالث.", ["would have found", "will find", "would find yesterday"], "would have found", "الشرط الثالث يستخدم would have + past participle.", 1.8),
        q("b2-v2", .b2, .vocabulary, "To ‘mitigate’ a risk means to ___.", "ما معنى mitigate؟", ["reduce its impact", "ignore it completely", "make it certain"], "reduce its impact", "mitigate يعني تخفيف الأثر.", 1.5),
        q("b2-p2", .b2, .practicalCommunication, "Choose the best meeting summary.", "اختر أفضل تلخيص للاجتماع.", ["We agreed on a phased launch, with a review after the first month.", "We talked and maybe launch stuff.", "The month agreed us."], "We agreed on a phased launch, with a review after the first month.", "يلخص القرار وآلية المتابعة.", 1.7),

        q("c1-v1", .c1, .vocabulary, "Choose the closest meaning of ‘scrutiny’.", "اختر معنى scrutiny.", ["careful critical examination", "casual approval", "public celebration"], "careful critical examination", "scrutiny هو الفحص النقدي الدقيق.", 1.4),
        q("c1-g1", .c1, .grammar, "Rarely ___ such a comprehensive response.", "اختر القلب النحوي الصحيح.", ["have we seen", "we have seen", "did we saw"], "have we seen", "بعد Rarely في البداية يحدث inversion.", 1.8),
        q("c1-r1", .c1, .reading, "A study reports a strong effect, but its sample is small and no comparison group was used. Which conclusion is best supported?", "أي استنتاج أدق؟", ["The method may be promising, but stronger evidence is needed.", "The method is proven beyond doubt.", "The sample size is irrelevant."], "The method may be promising, but stronger evidence is needed.", "الاستنتاج المتحفظ يناسب حدود الدراسة.", 1.9),
        q("c1-l1", .c1, .listening, "Listen and identify the rhetorical function.", "استمع وحدد وظيفة العبارة.", ["Qualifying a claim", "Giving an absolute guarantee", "Changing the subject"], "Qualifying a claim", "may indicate وshould be interpreted cautiously أدوات تحفظ.", 1.9, "The findings may indicate a shift, although they should be interpreted cautiously."),
        q("c1-p1", .c1, .practicalCommunication, "Respond to a concern in a negotiation.", "استجب لتحفظ في تفاوض.", ["I understand the concern; a phased delivery with measurable milestones could address it.", "That concern is not important.", "We refuse any discussion."], "I understand the concern; a phased delivery with measurable milestones could address it.", "تعترف بالمشكلة وتقترح آلية قابلة للقياس.", 1.9),
        q("c1-g2", .c1, .grammar, "The recommendation was rejected, not because it lacked merit, but because it ___ adequately costed.", "اختر الصيغة الصحيحة.", ["had not been", "has not", "was not being have"], "had not been", "الماضي التام المبني للمجهول يسبق الرفض.", 1.8),
        q("c1-v2", .c1, .vocabulary, "A ‘nuanced’ argument is ___.", "ما معنى nuanced؟", ["sensitive to fine distinctions", "deliberately meaningless", "entirely one-sided"], "sensitive to fine distinctions", "nuanced يعني يراعي الفروق الدقيقة.", 1.6),
        q("c1-p2", .c1, .practicalCommunication, "Choose the strongest academic qualification.", "اختر أفضل صياغة أكاديمية متحفظة.", ["The evidence appears to support this interpretation, though alternative explanations remain plausible.", "This proves the claim forever.", "Everyone clearly knows this is true."], "The evidence appears to support this interpretation, though alternative explanations remain plausible.", "توازن بين الدليل والبدائل الممكنة.", 2.0)
    ]

    private static func q(
        _ id: String,
        _ level: CEFRLevel,
        _ skill: LanguageSkill,
        _ prompt: String,
        _ promptAr: String,
        _ choices: [String],
        _ answer: String,
        _ explanationAr: String,
        _ discrimination: Double,
        _ speechText: String? = nil
    ) -> PlacementQuestion {
        PlacementQuestion(
            id: id,
            level: level,
            skill: skill,
            prompt: prompt,
            promptAr: promptAr,
            choices: choices,
            answer: answer,
            explanationAr: explanationAr,
            speechText: speechText,
            discrimination: discrimination
        )
    }
}
