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
        .navigationTitle("دليل الاستخدام")
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
        .init(title: "البداية والحساب", icon: "person.crop.circle", tint: AppTheme.brand, points: [
            "أنشئ حسابًا (بريد وكلمة مرور) من الإعدادات ← الحساب، ليُحفظ تقدّمك في السحابة.",
            "سجّل الدخول على أي جهاز لاستعادة تقدّمك تلقائيًا.",
            "يُحفظ تقدّمك تلقائيًا بعد كل درس — لا حاجة للحفظ اليدوي.",
        ]),
        .init(title: "الدروس والمستويات", icon: "graduationcap.fill", tint: AppTheme.accentTeal, points: [
            "اختر مستواك من تبويب «المنهج» (A0 للمبتدئ حتى C1 للمتقدّم)، وسيتبعه باقي التطبيق.",
            "كل درس: تمهيد، بطاقات كلمات، تمارين متنوعة، ثم تقييم بنسبة مئوية وتوصيات.",
            "زر «إنهاء» أعلى الدرس يخرجك بعد تأكيد؛ أكمل الدرس ليُحتسب تقدّمك.",
        ]),
        .init(title: "التدريب والمحادثة", icon: "waveform", tint: AppTheme.brandSecondary, points: [
            "تبويب «التدريب»: نطق، محادثة صوتية، قصص، ومختبرات مهارات.",
            "في المحادثة الصوتية اضغط «ابدأ الإجابة» وتحدّث، ثم أوقف التسجيل لتحصل على ملاحظات.",
            "اسمح بالميكروفون والتعرّف على الكلام عند الطلب.",
        ]),
        .init(title: "المراجعة والتقدّم", icon: "arrow.triangle.2.circlepath", tint: AppTheme.success, points: [
            "تبويب «المراجعة» يعيد الكلمات في الوقت المناسب لتثبيتها (تكرار متباعد).",
            "الشاشة الرئيسية تعرض هدفك اليومي، نقاطك، وسلسلة أيامك.",
            "دفتر الأخطاء يجمع ما أخطأت فيه لتراجعه لاحقًا.",
        ]),
        .init(title: "النسخ الاحتياطي والإعدادات", icon: "gearshape.fill", tint: AppTheme.warning, points: [
            "النسخ الاحتياطي عبر حسابك تلقائيًا؛ يمكنك أيضًا تصدير نسخة كملف اختياريًا.",
            "غيّر لغة الواجهة (عربي/إنجليزي)، الهدف اليومي، والتذكيرات من الإعدادات.",
            "للتواصل مع المطوّر: الإعدادات ← تواصل مع المطوّر.",
        ]),
    ]
}
