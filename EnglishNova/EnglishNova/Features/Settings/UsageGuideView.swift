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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(steps.map(\.title).joined(separator: Localizer.shared.isEnglish ? ", then " : "، ثم "))
            .padding(.vertical, 4)
        }
    }

    private static let sections: [GuideSection] = [
        .init(
            title: LE("ابدأ من مستواك", "Start at the right level"),
            icon: "graduationcap.fill",
            tint: AppTheme.brand,
            steps: [
                .init(icon: "checklist", title: LE("حدد المستوى", "Choose level")),
                .init(icon: "book.fill", title: LE("ابدأ الدرس", "Start lesson")),
                .init(icon: "chart.line.uptrend.xyaxis", title: LE("راجع النتيجة", "Review result"))
            ],
            points: [
                LE("إذا لم تكن متأكدًا من مستواك، استخدم اختبار تحديد المستوى بدل اختيار مستوى مرتفع للتجربة فقط.",
                   "If you are unsure of your level, use the placement test instead of choosing a high level just to try it."),
                LE("من الصفحة الرئيسية افتح الدرس التالي أو خطة اليوم.", "Open the next lesson or Today's Plan from Home."),
                LE("في المستويات الأعلى لا تكفي أسئلة الاختيار وحدها لإثبات الإتقان؛ يطلب التطبيق دليلًا أقوى من الترجمة أو التحدث.",
                   "At higher levels, recognition questions alone are not enough for mastery; stronger productive evidence is required.")
            ]
        ),
        .init(
            title: LE("أكمل الدرس", "Complete a lesson"),
            icon: "book.fill",
            tint: AppTheme.accentTeal,
            steps: [
                .init(icon: "ear.fill", title: LE("افهم", "Understand")),
                .init(icon: "text.cursor", title: LE("أجب", "Respond")),
                .init(icon: "checkmark.seal.fill", title: LE("أثبت الإتقان", "Show mastery"))
            ],
            points: [
                LE("اقرأ التعليمات، أجب، ثم راجع سبب التصحيح قبل الانتقال.", "Read the instruction, answer, then review the feedback before continuing."),
                LE("زر «اشرح أكثر» يفتح شرحًا إضافيًا عندما تحتاج إلى توضيح قاعدة أو عبارة.", "Use Explain More when a rule or phrase is still unclear."),
                LE("درجة نهاية الدرس ليست نسبة الأسئلة الصحيحة فقط؛ نوع المهمة ومستوى CEFR يؤثران في وزنها.",
                   "The final lesson score is not just percent correct; task type and CEFR level affect the evidence weight.")
            ]
        ),
        .init(
            title: LE("راجع قبل أن تنسى", "Review before you forget"),
            icon: "arrow.triangle.2.circlepath",
            tint: AppTheme.success,
            steps: [
                .init(icon: "rectangle.stack.fill", title: LE("بطاقات مستحقة", "Due cards")),
                .init(icon: "brain.head.profile", title: LE("استرجع", "Recall")),
                .init(icon: "calendar", title: LE("موعد جديد", "Reschedule"))
            ],
            points: [
                LE("المراجعة تعرض الكلمات التي حان وقتها بحسب أدائك السابق.", "Review shows vocabulary when it is due based on your previous performance."),
                LE("حاول تذكر المعنى قبل إظهاره، ثم قيّم صعوبة الاسترجاع بصدق.", "Try to recall the meaning before revealing it, then rate retrieval difficulty honestly."),
                LE("دفتر المفردات ودفتر الأخطاء يعيدانك إلى ما يحتاج إلى عمل، لا إلى قائمة عشوائية.",
                   "Vocabulary and mistake notebooks take you back to material that actually needs work.")
            ]
        ),
        .init(
            title: LE("تدرّب على مهارة", "Practice a skill"),
            icon: "waveform.and.mic",
            tint: AppTheme.brandSecondary,
            steps: [
                .init(icon: "scope", title: LE("اختر المهارة", "Choose skill")),
                .init(icon: "play.circle.fill", title: LE("نفّذ المهمة", "Do the task")),
                .init(icon: "arrow.clockwise", title: LE("أعد التطبيق", "Apply again"))
            ],
            points: [
                LE("تتوفر تدريبات للنطق والاستماع والمحادثة والكتابة والقراءة.", "Practice pronunciation, listening, conversation, writing, and reading."),
                LE("في التدريب الصوتي ابدأ التسجيل، تحدث طبيعيًا، ثم أوقفه قبل طلب التحليل.",
                   "In voice practice, start recording, speak naturally, then stop before requesting analysis."),
                LE("تقييم النطق تعليمي وتقريبي، وليس قياسًا مخبريًا لمخارج الأصوات.", "Pronunciation scoring is educational and approximate, not a laboratory phonetics measurement.")
            ]
        ),
        .init(
            title: LE("سجّل الدخول باستخدام Google", "Sign in with Google"),
            icon: "person.badge.key.fill",
            tint: AppTheme.warning,
            steps: [
                .init(icon: "g.circle.fill", title: "Google"),
                .init(icon: "checkmark.shield.fill", title: LE("تحقق الخادم", "Server verification")),
                .init(icon: "icloud.fill", title: LE("مزامنة", "Sync"))
            ],
            points: [
                LE("بعد اختيار Google، يرسل التطبيق Google ID token إلى خادم EnglishNova عبر HTTPS.",
                   "After Google Sign-In, the app sends a Google ID token to the EnglishNova server over HTTPS."),
                LE("يتحقق الخادم من توقيع الرمز والجمهور والصلاحية قبل إنشاء جلسة EnglishNova.",
                   "The server verifies the token signature, audience, issuer, and expiry before creating an EnglishNova session."),
                LE("إذا كان البريد الموثق مرتبطًا بحساب موجود، يُربط Google بالحساب بدل إنشاء نسخة مكررة.",
                   "If the verified email already belongs to an account, Google is linked to it instead of creating a duplicate."),
                LE("يتطلب البناء الفعلي ضبط OAuth Client IDs الخاصة بمشروع EnglishNova في إعدادات البناء والخادم.",
                   "A production build requires the EnglishNova Google OAuth client IDs to be configured in build and server settings.")
            ]
        ),
        .init(
            title: LE("اللغة والخصوصية", "Language and privacy"),
            icon: "globe.badge.chevron.backward",
            tint: AppTheme.success,
            steps: [
                .init(icon: "globe", title: LE("اختر اللغة", "Choose language")),
                .init(icon: "rectangle.3.group", title: LE("واجهة موحدة", "Consistent UI")),
                .init(icon: "lock.shield.fill", title: LE("تحكم بالبيانات", "Control data"))
            ],
            points: [
                LE("عند اختيار English يجب ألا تظهر نصوص واجهة عربية بسبب نقص ترجمة؛ يعتبر ذلك خطأ يجب إصلاحه.",
                   "When English is selected, Arabic UI text must not appear because of a missing translation; that is treated as a localization defect."),
                LE("التلميحات العربية التعليمية خيار منفصل عن لغة الواجهة، ويمكن التحكم بها من الإعدادات.",
                   "Arabic learning hints are separate from the interface language and can be controlled in Settings."),
                LE("راجع سياسة الخصوصية لمعرفة ما يبقى على الجهاز وما يُرسل عند استخدام المزامنة أو الذكاء الاصطناعي.",
                   "Review the Privacy Policy to see what stays on-device and what is sent when sync or AI features are used.")
            ]
        )
    ]
}
