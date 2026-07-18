import SwiftUI

/// A detailed, friendly usage guide covering the whole app.
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
                                Text(point).font(.subheadline)
                            }
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

    private struct Section: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let tint: Color
        let points: [String]
    }

    private static let sections: [Section] = [
        .init(title: L("البداية والحساب"), icon: "person.crop.circle", tint: AppTheme.brand, points: [
            L("أنشئ حسابًا (بريد وكلمة مرور) من الإعدادات ← الحساب، ليُحفظ تقدّمك في السحابة."),
            L("سجّل الدخول على أي جهاز لاستعادة تقدّمك تلقائيًا."),
            L("يُحفظ تقدّمك تلقائيًا بعد كل درس — لا حاجة للحفظ اليدوي."),
        ]),
        .init(title: L("الدروس والمستويات"), icon: "graduationcap.fill", tint: AppTheme.accentTeal, points: [
            L("اختر مستواك من تبويب «المنهج» (A0 للمبتدئ حتى C1 للمتقدّم)، وسيتبعه باقي التطبيق."),
            L("كل درس: تمهيد، بطاقات كلمات، تمارين متنوعة، ثم تقييم بنسبة مئوية وتوصيات."),
            L("زر «إنهاء» أعلى الدرس يخرجك بعد تأكيد؛ أكمل الدرس ليُحتسب تقدّمك."),
        ]),
        .init(title: L("التدريب والمحادثة"), icon: "waveform", tint: AppTheme.brandSecondary, points: [
            L("تبويب «التدريب»: نطق، محادثة صوتية، قصص، ومختبرات مهارات."),
            L("في المحادثة الصوتية اضغط «ابدأ الإجابة» وتحدّث، ثم أوقف التسجيل لتحصل على ملاحظات."),
            L("اسمح بالميكروفون والتعرّف على الكلام عند الطلب."),
        ]),
        .init(title: L("المراجعة والتقدّم"), icon: "arrow.triangle.2.circlepath", tint: AppTheme.success, points: [
            L("تبويب «المراجعة» يعيد الكلمات في الوقت المناسب لتثبيتها (تكرار متباعد)."),
            L("الشاشة الرئيسية تعرض هدفك اليومي، نقاطك، وسلسلة أيامك."),
            L("دفتر الأخطاء يجمع ما أخطأت فيه لتراجعه لاحقًا."),
        ]),
        .init(title: L("النسخ الاحتياطي والإعدادات"), icon: "gearshape.fill", tint: AppTheme.warning, points: [
            L("النسخ الاحتياطي عبر حسابك تلقائيًا؛ يمكنك أيضًا تصدير نسخة كملف اختياريًا."),
            L("غيّر لغة الواجهة (عربي/إنجليزي)، الهدف اليومي، والتذكيرات من الإعدادات."),
            L("للتواصل مع المطوّر: الإعدادات ← تواصل مع المطوّر."),
        ]),
    ]
}
