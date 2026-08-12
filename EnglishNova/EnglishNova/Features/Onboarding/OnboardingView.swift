import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var session: UserSession
    @State private var page = 0
    @State private var name = ""
    @State private var level: CEFRLevel = .a0
    @State private var saving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                TabView(selection: $page) {
                    intro.tag(0)
                    levelSelection.tag(1)
                    profile.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                PrimaryButton(
                    title: page < 2 ? L("متابعة") : L("ابدأ التعلّم"),
                    systemImage: "arrow.forward",
                    isLoading: saving
                ) {
                    if page < 2 {
                        withAnimation { page += 1 }
                    } else {
                        saving = true
                        Task {
                            await session.completeOnboarding(
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                level: level
                            )
                            saving = false
                        }
                    }
                }
            }
            .padding(AppTheme.screenPadding)
            .screenBackground()
            .navigationTitle("EnglishNova")
        }
    }

    private var intro: some View {
        VStack(spacing: 20) {
            Image(systemName: "character.book.closed.fill")
                .accessibilityHidden(true)
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text(L("تعلّم الإنجليزية بخطوات واضحة"))
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            Text(L("دروس قصيرة، مراجعة في وقتها، وتدريب على الاستماع والنطق والكتابة والمحادثة. ويمكن استخدام الأساسيات دون حساب."))
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var levelSelection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("من أين تريد أن تبدأ؟"))
                .font(.largeTitle.bold())

            Text(L("اختر أقرب مستوى لك الآن. يمكنك تغييره لاحقًا أو إجراء اختبار تحديد المستوى."))
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(CEFRLevel.allCases) { item in
                        Button {
                            level = item
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(item.rawValue) • \(item.titleAr)")
                                        .font(.headline)
                                    Text(item.summaryAr)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: level == item ? "checkmark.circle.fill" : "circle")
                            }
                            .padding()
                            .background(.background, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.rawValue)، \(item.titleAr)، \(item.summaryAr)")
                        .accessibilityValue(level == item ? L("محدد") : L("غير محدد"))
                    }
                }
            }
        }
    }

    private var profile: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("ما الاسم الذي تفضله؟"))
                .font(.largeTitle.bold())

            Text(L("يمكنك تركه فارغًا."))
                .foregroundStyle(.secondary)

            TextField(L("اسم العرض"), text: $name)
                .textContentType(.name)
                .textFieldStyle(.roundedBorder)

            InfoCard(title: L("قبل أن تبدأ"), systemImage: "lock.shield.fill") {
                Text(L("لا تحتاج إلى حساب لاستخدام الدروس المحلية. إذا أنشأت حسابًا لاحقًا، يمكنك مزامنة تقدّمك واستخدام الميزات المتصلة بالإنترنت."))
                Text(L("في التدريب الصوتي الحالي، لا يرفع EnglishNova ملف التسجيل الصوتي الخام إلى خادمه؛ تُستخدم نتائج التعرّف على الكلام لأغراض التدريب."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
