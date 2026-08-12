import SwiftUI

struct UsageGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Self.sections) { section in
                    InfoCard(title: section.title, systemImage: section.icon, tint: section.tint) {
                        ForEach(section.points, id: \.self) { point in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(section.tint)
                                    .font(.footnote)
                                    .padding(.top, 3)
                                    .accessibilityHidden(true)
                                Text(point).font(.subheadline)
                            }
                            .accessibilityElement(children: .combine)
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
        let points: [String]
    }

    private static let sections: [GuideSection] = [
        .init(title: L("ابدأ من مستواك"), icon: "graduationcap.fill", tint: AppTheme.brand, points: [
            L("اختر مستواك من شاشة البداية أو من المنهج. ويمكنك تغييره لاحقًا متى احتجت."),
            L("من الصفحة الرئيسية افتح الدرس التالي، أو راجع خطة اليوم إذا كنت تريد جلسة موزعة بين أكثر من مهارة."),
            L("إذا لم تكن متأكدًا من مستواك، استخدم اختبار تحديد المستوى من مركز التدريب.")
        ]),
        .init(title: L("أكمل الدرس"), icon: "book.fill", tint: AppTheme.accentTeal, points: [
            L("اقرأ التعليمات، أجب، ثم راجع التصحيح قبل الانتقال للسؤال التالي."),
            L("يمكنك طلب شرح إضافي من المدرّب عندما يظهر زر «اشرح أكثر»."),
            L("يُحفظ إنجاز الدرس محليًا عند إنهائه. وإذا كنت مسجلًا في حسابك، يحاول التطبيق مزامنة التقدّم مع الخادم.")
        ]),
        .init(title: L("راجع قبل أن تنسى"), icon: "arrow.triangle.2.circlepath", tint: AppTheme.success, points: [
            L("قسم المراجعة يعرض الكلمات التي حان وقتها بحسب أدائك السابق، وليس بجدول واحد لجميع الكلمات."),
            L("بعد إظهار المعنى، قيّم مدى سهولة تذكرك للكلمة حتى يحدد التطبيق موعد المراجعة التالية."),
            L("دفتر المفردات ودفتر الأخطاء يساعدانك على العودة إلى الكلمات والملاحظات التي تحتاجها لاحقًا.")
        ]),
        .init(title: L("تدرّب على مهارة محددة"), icon: "waveform.and.mic", tint: AppTheme.brandSecondary, points: [
            L("من مركز التدريب يمكنك فتح تدريب النطق أو الاستماع أو المحادثة أو الكتابة أو القراءة."),
            L("في التدريب الصوتي، ابدأ التسجيل وتحدث ثم أوقفه قبل طلب التحليل."),
            L("تقييم النطق تقريبي وتعليمي؛ يعتمد على التعرّف على الكلام والتوقيت ولا يقيس مخارج الحروف قياسًا مخبريًا.")
        ]),
        .init(title: L("استخدم المدرّب"), icon: "bubble.left.and.bubble.right.fill", tint: AppTheme.warning, points: [
            L("يمكنك سؤال المدرّب بالعربية أو الإنجليزية، وطلب مثال أو تصحيح أو متابعة محادثة."),
            L("عند تسجيل الدخول والمزامنة، قد يستفيد المدرّب عبر الإنترنت من ملخص أدائك لتخصيص التدريب والشرح."),
            L("إذا انقطع الإنترنت، تبقى الوظائف المحلية المتاحة في التطبيق قابلة للاستخدام.")
        ]),
        .init(title: L("الحساب والمزامنة"), icon: "person.crop.circle", tint: AppTheme.accentTeal, points: [
            L("الحساب اختياري للوظائف المحلية، لكنه مطلوب للمزامنة وبعض ميزات الذكاء الاصطناعي عبر الإنترنت."),
            L("يمكنك حفظ نسخة على حسابك أو استعادتها من شاشة الحساب والنسخ الاحتياطي."),
            L("قبل استعادة نسخة من الخادم على جهاز فيه تقدّم مهم، تأكد أنك تريد استبدال البيانات المحلية بالنسخة المحفوظة.")
        ]),
        .init(title: L("الخصوصية والوصولية"), icon: "lock.shield.fill", tint: AppTheme.success, points: [
            L("راجع سياسة الخصوصية لمعرفة البيانات التي تبقى على جهازك وما الذي يُرسل عند استخدام المزامنة أو الذكاء الاصطناعي."),
            L("EnglishNova يدعم VoiceOver وأحجام الخط الديناميكية، ولا يفترض الاعتماد على اللون وحده لفهم النتيجة."),
            L("يمكنك التواصل مع المطوّر من قسم المساعدة والتواصل في الإعدادات.")
        ])
    ]
}
