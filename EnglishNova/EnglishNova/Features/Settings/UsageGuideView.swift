import SwiftUI

struct UsageGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(LE(
                    "دليل عملي سريع لأهم مسارات EnglishNova. الرسومات مختصرة ومقروءة بالكامل بواسطة VoiceOver.",
                    "A practical guide to EnglishNova's main learning flows. Every visual is also fully described for VoiceOver."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)

                ForEach(Self.sections) { section in
                    InfoCard(title: section.title, systemImage: section.icon, tint: section.tint) {
                        GuideFlow(steps: section.steps)

                        ForEach(section.points, id: \.self) { point in
                            Label(point, systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle(L("دليل الاستخدام"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private struct GuideSection: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let tint: Color
        let steps: [GuideStep]
        let points: [String]
    }

    private struct GuideStep: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
    }

    private struct GuideFlow: View {
        let steps: [GuideStep]

        var body: some View {
            // Steps sit side by side, or stack when the text is large.
            ViewThatFits(in: .horizontal) {
                row
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        Label("\(index + 1). \(step.title)", systemImage: step.icon)
                            .font(.subheadline.bold())
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(steps.map(\.title).joined(separator: Localizer.shared.isEnglish ? ", then " : "، ثم "))
            .padding(.vertical, 4)
        }

        private var row: some View {
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    VStack(spacing: 6) {
                        Image(systemName: step.icon)
                            .font(.title2)
                            .frame(width: 46, height: 46)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityHidden(true)
                        Text(step.title)
                            .font(.caption.bold())
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    if index < steps.count - 1 {
                        Image(systemName: "arrow.forward")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.top, 16)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private static var sections: [GuideSection] { [
        .init(
            title: LE("ابدأ في دقيقة", "Get started in a minute"),
            icon: "sparkles",
            tint: AppTheme.brand,
            steps: [
                .init(icon: "target", title: LE("هدفك", "Your goal")),
                .init(icon: "graduationcap.fill", title: LE("مستواك", "Your level")),
                .init(icon: "clock.fill", title: LE("وقتك اليومي", "Daily time"))
            ],
            points: [
                LE("عند أول تشغيل تختار هدفك ومستواك وكم دقيقة تريد يوميًا، ويمكنك تفعيل تذكير يومي.",
                   "On first launch you choose your goal, level and daily minutes, and can turn on a daily reminder."),
                LE("إذا لم تكن متأكدًا من مستواك، اختر الأقرب ثم أجرِ «اختبار تحديد المستوى» من تبويب التدريب.",
                   "If you're unsure of your level, pick the closest one, then take the placement test from the Practice tab."),
                LE("التطبيق أربعة تبويبات: «اليوم» لجلستك اليومية، و«المسار» لكل الدروس، و«التدريب» للمهارات والاختبارات، و«أنا» لمراجعتك وتقدّمك وإعداداتك.",
                   "The app has four tabs: Today for your daily session, Path for every lesson, Practice for skills and tests, and Me for your review, progress and settings.")
            ]
        ),
        .init(
            title: LE("جلسة اليوم", "Today's session"),
            icon: "sun.max.fill",
            tint: AppTheme.warning,
            steps: [
                .init(icon: "rectangle.stack.fill", title: LE("مراجعة", "Review")),
                .init(icon: "play.fill", title: LE("درس", "Lesson")),
                .init(icon: "arrow.uturn.backward", title: LE("أخطاؤك", "Mistakes")),
                .init(icon: "waveform.and.mic", title: LE("تحدّث", "Speak"))
            ],
            points: [
                LE("زر «ابدأ الجلسة» يفتح الخطوة التالية مباشرة. الخطوة المنتهية تبقى ظاهرة بعلامة صح.",
                   "The Start session button opens the next step. Finished steps stay visible with a check mark."),
                LE("تتغير الجلسة يوميًا بحسب ما حان وقت مراجعته وما أخطأت فيه. في الأيام الخفيفة تكون أقصر.",
                   "The session changes daily with what is due and what you missed. It is shorter on light days."),
                LE("«كلمة اليوم» تعطيك كلمة من مستواك مع مثال ونطق، ويمكنك إضافتها إلى مراجعتك.",
                   "Word of the day gives you a word from your level with an example and audio, and you can add it to your review."),
                LE("السلسلة تزيد كل يوم تدرس فيه. كل 7 أيام تربح «حماية سلسلة» تحفظها إذا فاتك يوم، وتحتفظ بحمايتين كحد أقصى.",
                   "Your streak grows each day you study. Every 7 days you earn a streak freeze that saves it if you miss a day; you can hold two.")
            ]
        ),
        .init(
            title: LE("المسار والدروس", "Path and lessons"),
            icon: "map.fill",
            tint: AppTheme.accentTeal,
            steps: [
                .init(icon: "map.fill", title: LE("اختر درسًا", "Pick a lesson")),
                .init(icon: "text.cursor", title: LE("أجب", "Answer")),
                .init(icon: "arrow.uturn.backward.circle", title: LE("جولة التصحيح", "Correction round")),
                .init(icon: "checkmark.seal.fill", title: LE("الملخص", "Summary"))
            ],
            points: [
                LE("في «المسار» ترى كل وحدة كطريق: مكتمل، ثم «ابدأ من هنا»، ثم ما لم يبدأ. كل الدروس مفتوحة.",
                   "Path shows each unit as a trail: done, then Start here, then not started. Every lesson stays open."),
                LE("يظهر أعلى الدرس «السؤال 3 من 20». بعد آخر سؤال تعود الأسئلة التي أخطأت فيها في «جولة التصحيح»، وهي لا تغيّر درجتك.",
                   "The top of a lesson shows Question 3 of 20. After the last one, items you missed return in a correction round that doesn't change your score."),
                LE("في كل درس تمارين جديدة من كلماته: التوصيل (اختر معنى كل كلمة من قائمة)، وصح أو خطأ، واستمع واكتب، والإملاء.",
                   "Each lesson adds exercises from its own words: matching (pick each word's meaning from a menu), true or false, listen and type, and dictation."),
                LE("درجة الدرس ليست نسبة الصحيح فقط؛ نوع المهمة ومستوى CEFR يؤثران في وزنها. الملخص يعرض كلمات الدرس وما صحّحته.",
                   "The lesson score isn't just percent correct; task type and CEFR level affect the weighting. The summary lists the lesson's words and what you fixed.")
            ]
        ),
        .init(
            title: LE("المراجعة والأخطاء", "Review and mistakes"),
            icon: "arrow.triangle.2.circlepath",
            tint: AppTheme.success,
            steps: [
                .init(icon: "rectangle.stack.fill", title: LE("مستحق", "Due")),
                .init(icon: "brain.head.profile", title: LE("استرجع", "Recall")),
                .init(icon: "calendar", title: LE("موعد جديد", "Reschedule"))
            ],
            points: [
                LE("شاشة «المراجعة» تجمع مراجعة الدروس المجتازة وبطاقات الكلمات في مكان واحد، وتصل إليها من «اليوم» أو «أنا».",
                   "The Review screen brings completed-lesson reviews and word cards together; open it from Today or Me."),
                LE("«تدرّب على أخطائك» يعيد عليك السؤال الأصلي الذي أخطأت فيه. إذا أجبت صحيحًا يُعلَّم الخطأ كمحسوم.",
                   "Practise your mistakes replays the original item you missed. A right answer marks the mistake resolved."),
                LE("«دفتر الأخطاء» يعرض كل الملاحظات من الدروس والكتابة والنطق والمحادثة مع البحث.",
                   "The mistake notebook lists every note from lessons, writing, pronunciation and conversation, with search.")
            ]
        ),
        .init(
            title: LE("تحدّث واستمع", "Speak and listen"),
            icon: "waveform.and.mic",
            tint: AppTheme.brandSecondary,
            steps: [
                .init(icon: "speaker.wave.2.fill", title: LE("استمع", "Listen")),
                .init(icon: "mic.fill", title: LE("قلّد", "Repeat")),
                .init(icon: "text.word.spacing", title: LE("كلماتك", "Your words"))
            ],
            points: [
                LE("«مدرّب النطق» يختار جملًا من دروسك: استمع بسرعة عادية أو ببطء، ثم قلها مباشرة. انقر أي كلمة في النتيجة لتسمعها وحدها.",
                   "The pronunciation coach picks sentences from your lessons: listen at normal speed or slowly, then say it straight after. Tap any word in the result to hear it alone."),
                LE("في «تدريب المحادثة بالصوت» فعّل «محادثة بدون لمس»: يستمع التطبيق بعد أن ينتهي الطرف الآخر، ويتوقف عندما تصمت، ثم يرد ويتابع.",
                   "In voice conversation, turn on Hands-free: the app listens after your partner speaks, stops when you go quiet, then replies and continues."),
                LE("من «الإعدادات ثم الأصوات الطبيعية» اختر صوتًا أوضح. نزّل الأصوات «المحسّنة» مجانًا من إعدادات iOS: تسهيلات الاستخدام ثم المحتوى المنطوق ثم الأصوات.",
                   "In Settings › Natural voices, choose a clearer voice. Download Enhanced voices for free in iOS Settings › Accessibility › Spoken Content › Voices."),
                LE("تقييم النطق تعليمي وتقريبي يعتمد على النص الذي تعرّف إليه النظام، وليس قياسًا مخبريًا للأصوات.",
                   "Pronunciation scoring is educational and approximate, based on recognized text, not a laboratory measurement.")
            ]
        ),
        .init(
            title: LE("اكتب واقرأ", "Write and read"),
            icon: "pencil.and.scribble",
            tint: AppTheme.brand,
            steps: [
                .init(icon: "list.bullet", title: LE("نوع الكتابة", "Writing type")),
                .init(icon: "pencil", title: LE("اكتب", "Write")),
                .init(icon: "chart.bar.fill", title: LE("التقييم", "Rubric")),
                .init(icon: "arrow.triangle.2.circlepath", title: LE("حسّن", "Improve"))
            ],
            points: [
                LE("في «تدريب الكتابة» اختر نوعًا مثل رسالة أو رأي أو IELTS مهمة 2، فيظهر لك موضوع مقترح. تحصل على درجة وأربعة معايير: إنجاز المهمة والترابط والمفردات والقواعد.",
                   "In the writing coach, choose a type such as email, opinion or IELTS Task 2 to get a suggested task. You get a score and four criteria: task achievement, coherence, vocabulary and grammar."),
                LE("اضغط «اكتب نسخة محسّنة» لتعدّل نصك بنفسك؛ يقارن المدرّب النسختين ويخبرك بما تحسّن.",
                   "Tap Write an improved version to revise it yourself; the coach compares both drafts and tells you what improved."),
                LE("«اشرح أي نص»: صوّر لافتة أو صفحة، أو اختر صورة، أو الصق نصًا. تُقرأ الصورة على جهازك، ثم تحصل على ترجمة وملخص ونسخة أبسط وكلمات وقواعد.",
                   "Explain any text: photograph a sign or page, pick a photo, or paste text. The photo is read on your device, then you get a translation, summary, simpler version, words and grammar.")
            ]
        ),
        .init(
            title: LE("الاختبارات وتقدّمك", "Tests and progress"),
            icon: "stopwatch.fill",
            tint: AppTheme.streak,
            steps: [
                .init(icon: "timer", title: LE("محاكاة", "Mock test")),
                .init(icon: "number", title: LE("Band تقريبي", "Approx. band")),
                .init(icon: "hexagon.fill", title: LE("مهاراتي", "My skills"))
            ],
            points: [
                LE("«اختبار تجريبي كامل» يقدّم IELTS Listening أو Reading بأربعين سؤالًا ووقت حقيقي، بلا تصحيح حتى التسليم، مع خيار وقت إضافي 25٪.",
                   "The full mock test gives IELTS Listening or Reading with 40 questions and real timing, no marking until you submit, and an optional 25% extra time."),
                LE("في «أنا ثم مهاراتي ومستواي» ترى ست مهارات ومستواك التقريبي في CEFR واقتراحًا لما تركّز عليه. هذه تقديرات تعليمية وليست شهادات.",
                   "In Me › My skills and level you see six skills, your estimated CEFR level and a suggested focus. These are learning estimates, not certificates.")
            ]
        ),
        .init(
            title: LE("المساعد الذكي ورصيده", "The AI assistant and its allowance"),
            icon: "sparkles",
            tint: AppTheme.accentTeal,
            steps: [
                .init(icon: "person.crop.circle", title: LE("سجّل الدخول", "Sign in")),
                .init(icon: "gauge.with.dots.needle.50percent", title: LE("رصيد يومي", "Daily allowance")),
                .init(icon: "moon.stars.fill", title: LE("يتجدد ليلًا", "Renews nightly"))
            ],
            points: [
                LE("ميزات الذكاء الاصطناعي (المدرّب، الكتابة، الشرح، التمارين المخصصة) تحتاج تسجيل الدخول والإنترنت.",
                   "AI features (tutor, writing, explanations, custom exercises) need sign-in and an internet connection."),
                LE("لكل متعلّم رصيد يومي يظهر أعلى تبويب «التدريب»، ويتجدد عند منتصف الليل بتوقيت الرياض. الإجابات المحفوظة مسبقًا والطلبات الفاشلة لا تُحسب.",
                   "Each learner has a daily allowance shown at the top of Practice; it renews at midnight Riyadh time. Cached answers and failed requests don't count."),
                LE("الدروس والمراجعة ومدرّب النطق والاختبار التجريبي تعمل دون إنترنت ولا تستهلك الرصيد.",
                   "Lessons, review, the pronunciation coach and the mock test work offline and don't use the allowance.")
            ]
        ),
        .init(
            title: LE("VoiceOver واختصارات الوصول", "VoiceOver and access shortcuts"),
            icon: "accessibility",
            tint: AppTheme.success,
            steps: [
                .init(icon: "hand.tap.fill", title: LE("نقر مزدوج بإصبعين", "Two-finger double-tap")),
                .init(icon: "arrow.uturn.backward", title: LE("إيماءة الرجوع", "Escape gesture")),
                .init(icon: "list.bullet.indent", title: LE("العناوين", "Headings"))
            ],
            points: [
                LE("النقر المزدوج بإصبعين (Magic Tap) يعيد صوت السؤال في الدروس، ويبدأ التسجيل أو يوقفه في مدرّب النطق.",
                   "A two-finger double-tap (Magic Tap) replays the question audio in lessons and starts or stops recording in the pronunciation coach."),
                LE("إيماءة الرجوع (حرف Z بإصبعين) تسأل قبل الخروج من الدرس أو الاختبار حتى لا تضيع إجاباتك.",
                   "The escape gesture (two-finger Z) asks before leaving a lesson or test so your answers aren't lost."),
                LE("يقرأ VoiceOver نتيجة كل إجابة تلقائيًا، ويعلن الوقت المتبقي في الاختبار عند 10 و5 ودقيقة واحدة. تنقّل بين العناوين بالدوّار.",
                   "VoiceOver reads each answer's result automatically and announces time left in a test at 10, 5 and 1 minutes. Use the rotor to move between headings.")
            ]
        ),
        .init(
            title: LE("الحساب والخصوصية", "Account and privacy"),
            icon: "lock.shield.fill",
            tint: AppTheme.warning,
            steps: [
                .init(icon: "g.circle.fill", title: "Google"),
                .init(icon: "checkmark.shield.fill", title: LE("تحقق الخادم", "Server verification")),
                .init(icon: "icloud.fill", title: LE("مزامنة", "Sync"))
            ],
            points: [
                LE("يمكنك التعلّم دون حساب. الحساب (بريد أو Google) يحفظ تقدّمك ويتيح المساعد الذكي.",
                   "You can learn without an account. An account (email or Google) keeps your progress and enables the AI assistant."),
                LE("عند تسجيل الدخول بـ Google يتحقق خادم EnglishNova من الرمز قبل إنشاء الجلسة، ويُربط بحسابك الموجود إن كان البريد نفسه.",
                   "With Google sign-in, the EnglishNova server verifies the token before creating a session and links it to your existing account if the email matches."),
                LE("التذكيرات تُخطط على جهازك بحسب تقدّمك، وتتوقف تلقائيًا بعد أسبوعين بلا دراسة. راجع سياسة الخصوصية لمعرفة ما يُرسل وما يبقى على جهازك.",
                   "Reminders are planned on your device from your progress and stop automatically after two quiet weeks. See the Privacy Policy for what is sent and what stays on your device.")
            ]
        )
    ] }
}
