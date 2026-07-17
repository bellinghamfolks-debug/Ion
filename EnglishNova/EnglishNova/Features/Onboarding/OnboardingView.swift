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

                PrimaryButton(title: page < 2 ? "متابعة" : "ابدأ التعلّم", systemImage: "arrow.forward", isLoading: saving) {
                    if page < 2 { withAnimation { page += 1 } }
                    else {
                        saving = true
                        Task {
                            await session.completeOnboarding(name: name.trimmingCharacters(in: .whitespacesAndNewlines), level: level)
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
            Image(systemName: "sparkles.rectangle.stack.fill").accessibilityHidden(true).font(.system(size: 64)).foregroundStyle(.tint)
            Text("رحلتك الإنجليزية، من أول كلمة إلى الطلاقة").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("دروس قصيرة، نطق، مراجعة ذكية، ومعلّم تفاعلي. تعمل الأساسيات دون إنترنت.")
                .font(.title3).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var levelSelection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("اختر نقطة البداية").font(.largeTitle.bold())
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(CEFRLevel.allCases) { item in
                        Button {
                            level = item
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("\(item.rawValue) • \(item.titleAr)").font(.headline)
                                    Text(item.summaryAr).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: level == item ? "checkmark.circle.fill" : "circle")
                            }
                            .padding()
                            .background(.background, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.rawValue)، \(item.titleAr)، \(item.summaryAr)")
                        .accessibilityValue(level == item ? "محدد" : "غير محدد")
                    }
                }
            }
        }
    }

    private var profile: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("كيف نناديك؟").font(.largeTitle.bold())
            TextField("الاسم اختياري", text: $name).textContentType(.name).textFieldStyle(.roundedBorder)
            InfoCard(title: "خصوصيتك أولا", systemImage: "lock.shield.fill") {
                Text("يمكنك استخدام التطبيق دون حساب، وإنشاء حساب لاحقًا لحفظ تقدّمك عبر أجهزتك. لا تُرفع تسجيلاتك الصوتية الخام، وكلمة المرور محفوظة مشفّرة.")
            }
        }
    }
}
