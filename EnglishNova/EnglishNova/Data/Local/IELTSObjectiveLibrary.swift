import Foundation

/// Original, offline practice material modelled on IELTS Academic question
/// families. It is not copied from, endorsed by, or presented as an official
/// IELTS paper. Four modules per objective section provide 40 scored items.
enum IELTSObjectiveLibrary {
    static let readingModules: [IELTSObjectiveModule] = [
        .init(
            id: "ielts-reading-shade",
            section: .reading,
            titleAr: "القراءة 1: الظل في المدن",
            contextAr: "نص أكاديمي؛ الفكرة والتفاصيل وTrue/False/Not Given.",
            sourceText: """
            As cities grow warmer, planners have begun to treat shade as public infrastructure rather than a pleasant extra. Trees are often the first solution proposed, but their effect varies. A mature tree can cool pedestrians directly by blocking solar radiation and indirectly through evaporation from its leaves. Yet a newly planted tree may take many years to provide a broad canopy, and some species struggle when soil is compacted beneath pavements.

            Built shade can produce immediate benefits. Shelters, fabric canopies and covered walkways can be positioned where people wait for buses or cross large open squares. They require maintenance, however, and poorly designed structures may trap warm air. Researchers therefore argue that cities should measure the experience at street level instead of relying only on satellite maps of surface temperature. A roof may look cool from above while the pavement beside it remains uncomfortable for someone waiting below.

            Equity is another concern. In several cities, neighbourhoods with lower household incomes have fewer established trees and longer walks to public transport. Planting programmes that count only the number of new trees can miss this imbalance. Survival, canopy size and the location of shade during the hottest hours are more useful indicators. Some councils now combine temperature sensors with walking audits in which residents describe where a journey becomes difficult.

            No single design works everywhere. A dry city may favour drought-resistant trees and narrow structures that cast shade without blocking air movement. A humid city may prioritise ventilation. The emerging lesson is not that trees or built shelters are universally superior, but that shade should be planned as a connected network along the routes people actually use.
            """,
            recommendedMinutes: 20,
            questions: [
                q("shade-1", "What is the main purpose of the passage?", ["To compare ways of planning useful urban shade", "To argue that all cities should plant the same tree", "To explain how satellites are manufactured", "To oppose covered public transport"], "To compare ways of planning useful urban shade", "ابحث عن الفكرة التي تغطي الأشجار والمنشآت والعدالة والسياق المناخي."),
                q("shade-2", "Why may a newly planted tree have limited immediate value?", ["Its canopy takes time to grow", "Its leaves always trap warm air", "It cannot survive outside parks", "It blocks every road"], "Its canopy takes time to grow", "النص يذكر أن الشجرة الجديدة قد تحتاج سنوات لتكوين مظلة واسعة."),
                q("shade-3", "Built shade always reduces air temperature.", ["True", "False", "Not Given"], "False", "النص يذكر أن التصميم السيئ قد يحبس الهواء الدافئ."),
                q("shade-4", "Satellite maps can fully represent a pedestrian's experience.", ["True", "False", "Not Given"], "False", "يميز النص بين حرارة السطح من الأعلى وتجربة الشخص عند مستوى الشارع."),
                q("shade-5", "Which indicator is described as more useful than simply counting new trees?", ["Canopy size", "Number of roads", "Price of sensors", "Height of buses"], "Canopy size", "وردت ثلاثة مؤشرات أفضل، ومنها حجم المظلة."),
                q("shade-6", "What do residents contribute during walking audits?", ["Descriptions of difficult parts of journeys", "Legal permission to cut trees", "Satellite photographs", "Designs for new buses"], "Descriptions of difficult parts of journeys", "السكان يصفون المواضع التي تصبح فيها الرحلة صعبة."),
                q("shade-7", "All lower-income neighbourhoods are located far from city centres.", ["True", "False", "Not Given"], "Not Given", "ذكر النص قلة الأشجار وطول المشي للنقل، ولم يذكر بعدها عن المركز."),
                q("shade-8", "In a humid city, planners may give priority to...", ["ventilation", "compacted soil", "narrower buses", "satellite ownership"], "ventilation", "الجملة الأخيرة من الفقرة الرابعة تربط المدن الرطبة بالتهوية."),
                q("shade-9", "The word ‘equity’ is closest in meaning to...", ["fair distribution", "rapid construction", "private ownership", "visual beauty"], "fair distribution", "السياق يناقش اختلاف توفر الظل بين الأحياء."),
                q("shade-10", "What is the writer's final recommendation?", ["Create connected shade along real routes", "Use only mature trees", "Replace walking with buses", "Copy one universal design"], "Create connected shade along real routes", "الخاتمة تنص على شبكة مترابطة على المسارات المستخدمة فعلًا.")
            ]
        ),
        .init(
            id: "ielts-reading-plain-language",
            section: .reading,
            titleAr: "القراءة 2: اللغة الواضحة",
            contextAr: "نص أكاديمي؛ المطابقة والاستنتاج ومعنى الكلمة من السياق.",
            sourceText: """
            Government agencies often publish information that is legally accurate yet difficult for the public to use. The plain-language movement seeks to close this gap. Its supporters do not propose deleting necessary technical concepts. Instead, they recommend arranging information around the reader's task, defining unfamiliar terms, and placing important actions before background detail.

            Critics sometimes claim that simpler wording inevitably reduces legal precision. Studies of revised forms provide a more complicated picture. When a tax agency replaced long sentences and unexplained abbreviations, more applicants completed the form correctly and staff received fewer requests for clarification. The legal conditions themselves did not change. However, simplification can fail when editors replace a precise term with a familiar but broader word. Successful revision therefore requires subject specialists as well as communication experts.

            Structure may matter more than vocabulary. A notice can use common words and still confuse readers if deadlines appear on the last page or exceptions are separated from the rule they modify. Headings, informative labels and short summaries allow readers to locate a decision before studying its basis. Digital documents also need semantic headings and correctly marked tables so screen-reader users can navigate efficiently. Merely increasing the font size does not solve a structural access problem.

            Evaluation is essential. Agencies frequently judge a document by asking senior staff whether it looks professional. A better method is to observe representative users attempting realistic tasks: identifying a deadline, comparing two options, or explaining the next required action. Completion time, errors and requests for help reveal problems that an internal review may miss. Plain language, in this view, is not a style preference but a measurable part of service quality.
            """,
            recommendedMinutes: 20,
            questions: [
                q("plain-1", "What does the plain-language movement primarily aim to do?", ["Make accurate information usable", "Remove every legal term", "Shorten all documents to one page", "Replace government staff"], "Make accurate information usable", "الفكرة الرئيسة هي سد الفجوة بين الدقة القانونية وقابلية الاستخدام."),
                q("plain-2", "Supporters want background detail to appear before required actions.", ["True", "False", "Not Given"], "False", "التوصية هي وضع الإجراءات المهمة قبل الخلفية."),
                q("plain-3", "What happened after the tax form was revised?", ["More people completed it correctly", "The legal conditions were removed", "Applications became more expensive", "Staff received more questions"], "More people completed it correctly", "النص يذكر زيادة الإكمال الصحيح وانخفاض طلبات التوضيح."),
                q("plain-4", "Successful revision should involve...", ["subject and communication specialists", "only senior managers", "only members of the public", "software developers alone"], "subject and communication specialists", "الدقة والوضوح يحتاجان خبرة موضوعية وخبرة تواصل."),
                q("plain-5", "The writer believes common vocabulary guarantees clarity.", ["True", "False", "Not Given"], "False", "يمكن للكلمات الشائعة أن تبقى مربكة إذا كان البناء سيئًا."),
                q("plain-6", "Why are semantic headings mentioned?", ["They support efficient screen-reader navigation", "They increase printing speed", "They translate legal terms", "They remove exceptions"], "They support efficient screen-reader navigation", "وردت في سياق إتاحة الوثائق الرقمية."),
                q("plain-7", "Increasing font size fixes every structural accessibility problem.", ["True", "False", "Not Given"], "False", "النص ينفي ذلك صراحة."),
                q("plain-8", "Which evaluation method does the writer prefer?", ["Watching users complete realistic tasks", "Asking senior staff about appearance", "Counting the number of pages", "Comparing font colours"], "Watching users complete realistic tasks", "الفقرة الأخيرة تقارن الحكم الشكلي بملاحظة الأداء الفعلي."),
                q("plain-9", "The word ‘representative’ most nearly means...", ["typical of the intended users", "officially elected", "legally qualified", "available every day"], "typical of the intended users", "المقصود مستخدمون يشبهون الجمهور المستهدف."),
                q("plain-10", "What is the conclusion of the passage?", ["Plain language is measurable service quality", "Professional appearance is the only test", "Precision and clarity cannot coexist", "Digital notices need no testing"], "Plain language is measurable service quality", "هذه خلاصة الجملة الأخيرة.")
            ]
        ),
        .init(
            id: "ielts-reading-sleep-learning",
            section: .reading,
            titleAr: "القراءة 3: النوم والتعلم",
            contextAr: "نص أكاديمي؛ السبب والنتيجة وحدود البحث.",
            sourceText: """
            Learning does not end when a study session finishes. During sleep, newly encoded information is reorganised and stabilised, a process commonly called memory consolidation. Laboratory experiments often compare people who learn the same material and are then tested after a period containing sleep or an equivalent period awake. On average, the group that sleeps retains more, although the size of the advantage depends on the task.

            Different stages of sleep appear to support different kinds of memory. Deep sleep has been associated with factual information, while rapid-eye-movement sleep may help integrate emotional or procedural learning. These associations are not simple switches. A person passes repeatedly through several stages, and researchers cannot yet assign every learning process to one stage with certainty.

            Timing also matters. Staying awake all night before an examination harms attention as well as memory, so extra hours of late study may produce diminishing returns. Short daytime naps can improve later recall in some experiments, but they do not fully compensate for repeated nights of insufficient sleep. Furthermore, people vary in their sleep needs, and an intervention that benefits one age group may not have the same effect in another.

            These findings have encouraged schools and employers to reconsider very early schedules. Nevertheless, changing a timetable does not guarantee better learning. Travel time, household responsibilities, light exposure and personal habits all influence when a person actually sleeps. Researchers therefore warn against turning a general biological finding into a single universal rule. The practical message is narrower: protect regular, adequate sleep, and treat it as part of learning rather than as time stolen from it.
            """,
            recommendedMinutes: 20,
            questions: [
                q("sleep-1", "What is memory consolidation?", ["The stabilisation of newly learned information", "The measurement of sleep duration", "The loss of procedural learning", "The repetition of an exam"], "The stabilisation of newly learned information", "التعريف في الفقرة الأولى."),
                q("sleep-2", "Sleeping groups always retain exactly the same amount more than awake groups.", ["True", "False", "Not Given"], "False", "حجم الفائدة يعتمد على نوع المهمة."),
                q("sleep-3", "Deep sleep has been associated mainly with...", ["factual information", "travel planning", "visual brightness", "household duties"], "factual information", "ورد الارتباط مباشرة في الفقرة الثانية."),
                q("sleep-4", "Researchers can identify the exact sleep stage for every learning process.", ["True", "False", "Not Given"], "False", "النص يقول إنهم لا يستطيعون ذلك بيقين حتى الآن."),
                q("sleep-5", "Why can late-night study have diminishing returns?", ["Sleep loss damages attention and memory", "Exams become shorter", "Facts move into procedural memory", "People stop needing practice"], "Sleep loss damages attention and memory", "السبب مذكور في بداية الفقرة الثالثة."),
                q("sleep-6", "Daytime naps fully repair repeated sleep loss.", ["True", "False", "Not Given"], "False", "النص ينص على أنها لا تعوض النقص المتكرر بالكامل."),
                q("sleep-7", "The same sleep intervention may affect age groups differently.", ["True", "False", "Not Given"], "True", "هذه الفكرة مذكورة صراحة."),
                q("sleep-8", "Which factor is NOT listed as affecting actual sleep time?", ["Salary", "Travel time", "Light exposure", "Household responsibilities"], "Salary", "الراتب غير مذكور ضمن العوامل."),
                q("sleep-9", "What warning do researchers give?", ["Do not turn a general finding into one universal rule", "Never change a school timetable", "Avoid all daytime naps", "Study only factual information"], "Do not turn a general finding into one universal rule", "ورد التحذير في الفقرة الأخيرة."),
                q("sleep-10", "Which statement best reflects the practical message?", ["Regular adequate sleep supports learning", "Every learner needs eight exact hours", "Sleep replaces active study", "Early schedules always fail"], "Regular adequate sleep supports learning", "الخاتمة تقدم رسالة محددة وغير مطلقة.")
            ]
        ),
        .init(
            id: "ielts-reading-automation",
            section: .reading,
            titleAr: "القراءة 4: الأتمتة والعمل",
            contextAr: "نص أكاديمي؛ موقف الكاتب والأدلة والاستنتاج.",
            sourceText: """
            Predictions about automation often count occupations, but jobs are bundles of tasks rather than indivisible units. Software may perform one routine part of a role while leaving negotiation, judgment or physical coordination to a person. As a result, the number of occupations that disappear can be much smaller than the number that change substantially.

            This distinction affects training. If an employer assumes that a whole role will vanish, it may delay investment in the employees who currently perform it. If managers instead map individual tasks, they can identify which skills will remain valuable and which new responsibilities are likely to emerge. A payroll clerk, for example, may spend less time entering data and more time investigating unusual cases or explaining results.

            Change is not automatically beneficial. When a system makes recommendations that workers cannot question, errors can be repeated at scale. Productivity statistics may also hide a transfer of effort to customers or junior staff. A faster online process is not a genuine efficiency gain if users must spend hours correcting failures through another channel. Evaluation should therefore include error rates, appeal routes and the distribution of saved time, not speed alone.

            Historical comparisons are useful but limited. Earlier technologies created new categories of work, yet the speed, reach and data requirements of current systems differ. The safest conclusion is neither that employment will collapse nor that adaptation will occur without cost. Institutions need continuous task-level evidence, accessible retraining and clear responsibility for automated decisions. Automation changes the design of work; policy determines how the gains and risks are shared.
            """,
            recommendedMinutes: 20,
            questions: [
                q("auto-1", "Why does the writer describe jobs as bundles of tasks?", ["To explain why roles may change without disappearing", "To prove every occupation will vanish", "To compare physical salaries", "To oppose all software"], "To explain why roles may change without disappearing", "هذه الفكرة تربط بين أتمتة المهمة وبقاء الوظيفة."),
                q("auto-2", "Automation affects more occupations than it completely removes.", ["True", "False", "Not Given"], "True", "هذا استنتاج مباشر من نهاية الفقرة الأولى."),
                q("auto-3", "What can task mapping help managers identify?", ["Skills that remain valuable", "The age of every worker", "A single future salary", "The legal owner of software"], "Skills that remain valuable", "الفقرة الثانية تذكر المهارات والمسؤوليات الجديدة."),
                q("auto-4", "What new activity might a payroll clerk do more often?", ["Investigate unusual cases", "Enter more routine data", "Repair office furniture", "Design transport routes"], "Investigate unusual cases", "هذا هو المثال المحدد في النص."),
                q("auto-5", "Recommendations that cannot be questioned may...", ["repeat errors at scale", "guarantee fair decisions", "eliminate data needs", "reduce every workload"], "repeat errors at scale", "الفقرة الثالثة تحذر من تضخيم الخطأ."),
                q("auto-6", "A faster online process is always a genuine efficiency gain.", ["True", "False", "Not Given"], "False", "يقدم النص مثالًا معاكسًا عندما ينتقل عبء التصحيح للمستخدم."),
                q("auto-7", "Which measure should be considered in addition to speed?", ["Appeal routes", "Office colour", "Number of managers", "Length of job titles"], "Appeal routes", "وردت مع معدلات الخطأ وتوزيع الوقت الموفر."),
                q("auto-8", "Current automation is identical to every earlier technology.", ["True", "False", "Not Given"], "False", "النص يذكر اختلاف السرعة والنطاق ومتطلبات البيانات."),
                q("auto-9", "The writer predicts the exact number of jobs that will be lost.", ["True", "False", "Not Given"], "Not Given", "لا يوجد رقم أو تنبؤ محدد؛ بل يرفض النص الاستنتاجين المطلقين."),
                q("auto-10", "What is the final argument?", ["Policy shapes how automation's gains and risks are shared", "Training is no longer useful", "Only customers benefit from automation", "Task evidence should remain secret"], "Policy shapes how automation's gains and risks are shared", "الجملة الأخيرة تلخص موقف الكاتب.")
            ]
        )
    ]

    static let listeningModules: [IELTSObjectiveModule] = [
        listening(
            "ielts-listening-library",
            "الاستماع 1: عضوية مكتبة",
            "محادثة خدمات يومية؛ الأسماء والأرقام والتعليمات.",
            """
            Librarian: Good morning, Westgate Library. How can I help?
            Caller: I'd like to join before my course begins next week. Can I register online?
            Librarian: You can start online, but you must show identification at the desk before borrowing anything. A passport or national identity card is fine. We also need proof of your current address, such as a recent electricity bill.
            Caller: I moved last month, so my identity card has my old address. I do have a bank statement from Friday.
            Librarian: That's acceptable. Standard membership is free. There is a twenty-pound annual fee only if you want access to the specialist business database from home.
            Caller: I don't need that yet. How many books can I borrow?
            Librarian: Eight printed books for three weeks. They renew automatically twice unless another reader has requested them. Laptops are different: one at a time, for four hours, and they must stay inside the building.
            Caller: Is the library open on Sunday?
            Librarian: The main floor opens from eleven until four. The study room opens at ten, but you need your membership card to enter before eleven.
            Caller: Great. I'll complete the form today and bring my bank statement tomorrow afternoon.
            """,
            [
                q("lib-1", "When does the caller's course begin?", ["next week", "tomorrow", "last month", "on Friday"], "next week", "ذُكر الموعد في أول رد للمتصل."),
                q("lib-2", "Where must identification be shown?", ["at the desk", "online", "at the bank", "in the study room"], "at the desk", "بدء التسجيل إلكتروني، لكن التحقق عند المكتب."),
                q("lib-3", "Which document will the caller use as proof of address?", ["a bank statement", "a passport", "an old identity card", "a course letter"], "a bank statement", "ذكر أن كشف البنك صدر يوم الجمعة وقُبل."),
                q("lib-4", "What is free?", ["standard membership", "the business database", "taking a laptop home", "replacement cards"], "standard membership", "الرسوم تخص قاعدة البيانات المتخصصة فقط."),
                q("lib-5", "How many printed books may be borrowed?", ["eight", "three", "two", "four"], "eight", "انتبه للفرق بين عدد الكتب ومدة الإعارة."),
                q("lib-6", "For how long is a normal book loan?", ["three weeks", "two weeks", "four hours", "one week"], "three weeks", "المدة ثلاثة أسابيع."),
                q("lib-7", "When will a book NOT renew automatically?", ["when another reader requests it", "when Sunday begins", "when a laptop is borrowed", "when the course ends"], "when another reader requests it", "هذا هو الاستثناء المذكور."),
                q("lib-8", "Where can library laptops be used?", ["inside the building", "at home", "in the caller's course", "at the bank"], "inside the building", "لا يجوز إخراجها."),
                q("lib-9", "What time does the main floor open on Sunday?", ["11:00", "10:00", "4:00", "12:00"], "11:00", "غرفة الدراسة تفتح العاشرة، والطابق الرئيس الحادية عشرة."),
                q("lib-10", "What will the caller do today?", ["complete the form", "visit the desk", "borrow eight books", "pay twenty pounds"], "complete the form", "سيكمل النموذج اليوم ويحضر الوثيقة غدًا.")
            ]
        ),
        listening(
            "ielts-listening-museum",
            "الاستماع 2: جولة متحف",
            "شرح لمجموعة زوار؛ الاتجاهات والقواعد والتغييرات.",
            """
            Welcome to the Riverside Museum. Before we begin, I need to explain today's route because the east staircase is closed for repairs. We are standing in the entrance hall. The information desk is directly behind you, and the lockers are through the glass door on your left. Large bags must be stored there, but small handbags may be carried.
            We will start in Gallery Two, on the ground floor, with the photography exhibition. Gallery One is normally first, but a school group is using it until noon. After photography, we will take the lift to the second floor. Please note that the lift opposite the café goes only to the first floor; use the larger lift beside the museum shop.
            At twelve fifteen, we will meet in the River Room for a short talk by the curator. The room was listed as the Garden Room in the programme, so please correct that name. Lunch is not included, but the café offers a ten percent discount when you show today's tour ticket. The discount applies to food, not drinks.
            You may take photographs without flash in most galleries. Photography is completely prohibited in the textile room because the objects are especially sensitive to light. If you need step-free access or a quiet place during the tour, speak to me or any guide wearing a blue badge. We expect to finish at two thirty beside the main entrance.
            """,
            [
                q("museum-1", "Why has the route changed?", ["the east staircase is closed", "the café is full", "the museum shop moved", "the entrance hall is locked"], "the east staircase is closed", "سبب التغيير في أول جملة تفسيرية."),
                q("museum-2", "Where are the lockers?", ["through the glass door on the left", "behind the information desk", "beside Gallery Two", "on the second floor"], "through the glass door on the left", "اتبع وصف الموقع من نقطة وقوف المجموعة."),
                q("museum-3", "Which bags must be stored?", ["large bags", "small handbags", "camera bags only", "all bags"], "large bags", "الحقائب الصغيرة مسموح بها."),
                q("museum-4", "Which gallery will the group visit first?", ["Gallery Two", "Gallery One", "the textile room", "the River Room"], "Gallery Two", "المجموعة المدرسية غيرت الترتيب المعتاد."),
                q("museum-5", "Where is the lift to the second floor?", ["beside the museum shop", "opposite the café", "inside Gallery One", "behind the lockers"], "beside the museum shop", "المصعد المقابل للمقهى يصل للطابق الأول فقط."),
                q("museum-6", "What time is the curator's talk?", ["12:15", "12:00", "2:30", "1:15"], "12:15", "الوقت مذكور قبل اسم الغرفة."),
                q("museum-7", "What is the corrected room name?", ["River Room", "Garden Room", "Textile Room", "East Room"], "River Room", "البرنامج القديم كتب Garden Room."),
                q("museum-8", "The café discount applies to...", ["food only", "drinks only", "food and drinks", "tour tickets"], "food only", "استبعد المشروبات."),
                q("museum-9", "Where is photography completely prohibited?", ["the textile room", "Gallery Two", "the entrance hall", "the café"], "the textile room", "الحظر الكامل لحساسية القطع للضوء."),
                q("museum-10", "How can visitors identify a guide?", ["by a blue badge", "by a camera", "by a red bag", "by a tour ticket"], "by a blue badge", "دليل المتحف يرتدي شارة زرقاء.")
            ]
        ),
        listening(
            "ielts-listening-project",
            "الاستماع 3: مشروع جامعي",
            "نقاش أكاديمي؛ اختيار المنهج وتقسيم المهام.",
            """
            Maya: We need to finalise our study of commuting habits. I still think an online questionnaire will give us the largest sample.
            Omar: A large sample is useful, but our draft questions produced vague answers. People said their journey was 'long' without giving minutes.
            Maya: Then we can revise the questions and ask for exact travel time. Professor Hall also suggested interviewing a smaller group so we understand why people choose a route.
            Omar: Right. We could survey two hundred students and interview twelve. I first proposed twenty interviews, but we won't have time to transcribe that many.
            Maya: Agreed. We should include staff too, though perhaps only in the questionnaire. Their schedules are different, and that comparison might be valuable.
            Omar: What about collecting data at the station entrance?
            Maya: The transport office refused permission during the morning rush, but they offered us a table in the student centre from two until five on Wednesday.
            Omar: Let's use it. I'll revise the questionnaire tonight. Could you prepare the consent form and participant information?
            Maya: Yes. Lina said she can analyse the numerical data, but she needs the final spreadsheet by Friday the eighteenth, not Monday as we wrote in the plan.
            Omar: Then I'll also build the spreadsheet. We should pilot the revised questions with ten people on Wednesday morning before the public session.
            Maya: Good. In our report, let's separate journey duration from satisfaction. A short trip can still be stressful, so combining them would hide useful differences.
            """,
            [
                q("project-1", "What problem did the draft questions produce?", ["vague answers", "too few participants", "missing consent", "incorrect dates"], "vague answers", "الإجابات وصفت الرحلة بأنها طويلة بلا دقائق."),
                q("project-2", "What will be requested in the revised question?", ["exact travel time", "home address", "ticket price only", "course grades"], "exact travel time", "هذا هو التصحيح المباشر للمشكلة."),
                q("project-3", "How many students will be surveyed?", ["200", "20", "12", "10"], "200", "ميز بين المسح والمقابلات والتجربة الأولية."),
                q("project-4", "How many interviews will they conduct?", ["12", "20", "200", "10"], "12", "خُفض العدد من عشرين إلى اثني عشر."),
                q("project-5", "How will staff participate?", ["in the questionnaire", "in interviews only", "at the station entrance", "by analysing data"], "in the questionnaire", "اقتُرح إشراك الموظفين في الاستبانة فقط."),
                q("project-6", "Where may the team collect public responses?", ["the student centre", "the station entrance", "Professor Hall's office", "the transport office"], "the student centre", "رُفضت المحطة وعُرض مركز الطلاب."),
                q("project-7", "Who will prepare the consent form?", ["Maya", "Omar", "Lina", "Professor Hall"], "Maya", "وافقت مايا على المهمة."),
                q("project-8", "When does Lina need the spreadsheet?", ["Friday the eighteenth", "Monday the eighteenth", "Wednesday morning", "Wednesday at five"], "Friday the eighteenth", "تم تصحيح الموعد من الاثنين إلى الجمعة."),
                q("project-9", "How many people will take part in the pilot?", ["10", "12", "20", "200"], "10", "التجربة الأولية صباح الأربعاء مع عشرة أشخاص."),
                q("project-10", "What two measures will be reported separately?", ["duration and satisfaction", "staff and students", "surveys and interviews", "morning and afternoon"], "duration and satisfaction", "السبب أن الرحلة القصيرة قد تكون مرهقة.")
            ]
        ),
        listening(
            "ielts-listening-water",
            "الاستماع 4: إعادة استخدام المياه",
            "مقتطف محاضرة؛ مراحل عملية وحجج علمية.",
            """
            Today we will examine how cities reuse household wastewater. The term does not normally include water from toilets. Instead, systems collect grey water from showers, bathroom sinks and washing machines. Kitchen water is sometimes excluded because grease and food particles make treatment more difficult.
            The first stage is screening. A mesh removes hair and larger material. The water then enters a settling tank, where heavier particles fall to the bottom. After that, biological treatment uses microorganisms to break down dissolved organic matter. Finally, filtration and disinfection reduce remaining particles and harmful microbes. Chlorine can be used, but ultraviolet light is increasingly common because it leaves no chemical residue.
            Recycled grey water is usually not classified as drinking water. Its main uses are toilet flushing, landscape irrigation and some industrial cooling. These applications can reduce demand for high-quality drinking water, especially during dry seasons. Savings depend on building design: installing a second set of pipes during construction is much cheaper than adding one to an existing building.
            Public acceptance is not determined by technical safety alone. People respond to the source of the water, the intended use and their trust in the organisation operating the system. Clear monitoring data and visible maintenance procedures can increase confidence. However, describing the water as 'perfectly pure' may be counterproductive because no treatment system is free of risk. Effective communication explains both the controls and their limits.
            Researchers are now studying smaller systems for individual apartment buildings. These may reduce the cost of long distribution pipes, but they also create more sites that require skilled maintenance. The trade-off is therefore between central efficiency and local flexibility, not simply between new and old technology.
            """,
            [
                q("water-1", "Which source is normally included in grey water?", ["showers", "toilets", "drinking fountains only", "storm drains"], "showers", "الحمامات والمغاسل والغسالات ضمن التعريف."),
                q("water-2", "Why may kitchen water be excluded?", ["grease makes treatment harder", "it contains no particles", "it is already drinking water", "pipes cannot carry it"], "grease makes treatment harder", "وردت الدهون وجزيئات الطعام."),
                q("water-3", "What happens during screening?", ["larger material is removed", "microorganisms are added", "water is declared drinkable", "heavy particles are disinfected"], "larger material is removed", "الشبكة تزيل الشعر والمواد الأكبر."),
                q("water-4", "Where do heavier particles go?", ["to the bottom of a settling tank", "through ultraviolet light", "into drinking pipes", "onto a mesh above the shower"], "to the bottom of a settling tank", "هذه وظيفة مرحلة الترسيب."),
                q("water-5", "What is an advantage of ultraviolet light?", ["it leaves no chemical residue", "it removes every risk", "it needs no electricity", "it adds useful grease"], "it leaves no chemical residue", "قورن بالكلور من هذه الناحية."),
                q("water-6", "Which use is mentioned for recycled grey water?", ["toilet flushing", "direct drinking", "cooking", "medical treatment"], "toilet flushing", "من الاستخدامات الثلاثة المذكورة."),
                q("water-7", "When is a second pipe system cheaper to install?", ["during construction", "after a building is occupied", "only during dry seasons", "after central treatment closes"], "during construction", "الإضافة للمبنى القائم أعلى تكلفة."),
                q("water-8", "What can increase public confidence?", ["clear monitoring data", "claiming there is no risk", "hiding maintenance", "using only old technology"], "clear monitoring data", "البيانات وإجراءات الصيانة المرئية ترفع الثقة."),
                q("water-9", "Why may the phrase ‘perfectly pure’ be counterproductive?", ["every system retains some risk", "people prefer chemical residue", "the water is always dirty", "monitoring is illegal"], "every system retains some risk", "المبالغة تقوض الثقة لأن انعدام المخاطر غير صحيح."),
                q("water-10", "What trade-off is associated with smaller building systems?", ["central efficiency versus local flexibility", "drinking versus washing", "new pipes versus no treatment", "public data versus private data"], "central efficiency versus local flexibility", "الجملة الأخيرة تصوغ المقايضة بوضوح.")
            ]
        )
    ]

    static func modules(for section: IELTSSection) -> [IELTSObjectiveModule] {
        section == .reading ? readingModules : listeningModules
    }

    private static func listening(
        _ id: String,
        _ title: String,
        _ context: String,
        _ transcript: String,
        _ questions: [ComprehensionQuestion]
    ) -> IELTSObjectiveModule {
        IELTSObjectiveModule(
            id: id,
            section: .listening,
            titleAr: title,
            contextAr: context,
            sourceText: transcript,
            recommendedMinutes: 10,
            questions: questions
        )
    }

    private static func q(
        _ id: String,
        _ prompt: String,
        _ choices: [String],
        _ answer: String,
        _ explanationAr: String
    ) -> ComprehensionQuestion {
        ComprehensionQuestion(
            id: id,
            prompt: prompt,
            promptAr: "اختر إجابة واحدة.",
            choices: choices,
            answer: answer,
            explanationAr: explanationAr
        )
    }
}
