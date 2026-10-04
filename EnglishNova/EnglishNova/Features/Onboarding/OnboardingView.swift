import SwiftUI

/// About a minute from install to the first lesson: goal, level, daily time
/// with an optional reminder, then an optional name. Each step is its own
/// screen (no swipe paging), so VoiceOver and Switch Control users always
/// know where they are and can go back with a visible button.
struct OnboardingView: View {
    @EnvironmentObject private var session: UserSession
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var reminderService: StudyReminderService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step = 0
    @State private var name = ""
    @State private var level: CEFRLevel = .a0
    @State private var pathway: LearningPathwayID = .foundations
    @State private var minutes = 10
    @State private var reminderOn = true
    @State private var reminderTime = Calendar.current.date(from: DateComponents(hour: 19, minute: 0)) ?? .now
    @State private var saving = false

    private let stepCount = 5
    private let minuteOptions = [5, 10, 15, 20, 30]

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if step > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LfE("الخطوة %@ من %@", "Step %@ of %@", "\(step)", "\(stepCount - 1)"))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ProgressView(value: Double(step), total: Double(stepCount - 1))
                            .tint(AppTheme.brand)
                            .accessibilityHidden(true)
                    }
                }

                ScrollView {
                    Group {
                        switch step {
                        case 0: welcome
                        case 1: goal
                        case 2: levelStep
                        case 3: timeStep
                        default: nameStep
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(reduceMotion ? .identity : .opacity)
                }

                PrimaryButton(
                    title: step == 0 ? LE("لنبدأ", "Let's start") : (step < stepCount - 1 ? L("متابعة") : LE("ابدأ أول درس", "Start my first lesson")),
                    systemImage: "arrow.forward",
                    isLoading: saving
                ) { advance() }
            }
            .padding(AppTheme.screenPadding)
            .screenBackground()
            .toolbar {
                if step > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            move(to: step - 1)
                        } label: {
                            Label(LE("رجوع", "Back"), systemImage: "chevron.backward")
                        }
                    }
                }
            }
            .accessibilityAction(.escape) { if step > 0 { move(to: step - 1) } }
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 22) {
            CelebrationView(systemImage: "character.book.closed.fill", tint: AppTheme.brand, size: 110)
                .frame(maxWidth: .infinity)
            Text(L("تعلّم الإنجليزية بخطوات واضحة"))
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            Text(LE("جلسة يومية قصيرة تختارها لك: مراجعة، ثم درس، ثم تدريب على أخطائك. أربعة أسئلة سريعة ونبدأ.",
                    "A short daily session picked for you: review, a lesson, then practice on your mistakes. Four quick questions and we begin."))
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 20)
    }

    private var goal: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading(LE("لماذا تتعلم الإنجليزية؟", "Why are you learning English?"),
                    LE("نرتّب لك الأولويات بحسب هدفك. يمكنك تغييره لاحقًا.", "We order your priorities around your goal. You can change it later."))
            ForEach(LearningPathwayID.allCases) { item in
                OptionRow(title: item.titleAr, systemImage: item.systemImage, selected: pathway == item) { pathway = item }
            }
        }
    }

    private var levelStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading(L("من أين تريد أن تبدأ؟"),
                    L("اختر أقرب مستوى لك الآن. يمكنك تغييره لاحقًا أو إجراء اختبار تحديد المستوى."))
            ForEach(CEFRLevel.allCases) { item in
                OptionRow(title: "\(item.rawValue) • \(item.titleAr)", detail: item.summaryAr, systemImage: nil, selected: level == item) { level = item }
            }
        }
    }

    private var timeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading(LE("كم دقيقة في اليوم؟", "How many minutes a day?"),
                    LE("القليل كل يوم أفضل من الكثير مرة واحدة.", "A little every day beats a lot once in a while."))
            ForEach(minuteOptions, id: \.self) { value in
                OptionRow(title: LfE("%@ دقائق", "%@ minutes", "\(value)"), detail: minutesDetail(value),
                          systemImage: "clock.fill", selected: minutes == value) { minutes = value }
            }
            Toggle(isOn: $reminderOn) {
                Label(LE("ذكّرني يوميًا", "Remind me daily"), systemImage: "bell.fill")
                    .font(.headline)
            }
            .padding()
            .background(AppTheme.cardSurface, in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius))
            if reminderOn {
                DatePicker(LE("وقت التذكير", "Reminder time"), selection: $reminderTime, displayedComponents: .hourAndMinute)
                    .padding(.horizontal)
            }
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading(L("ما الاسم الذي تفضله؟"), L("يمكنك تركه فارغًا."))
            TextField(L("اسم العرض"), text: $name)
                .textContentType(.name)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.go)
                .onSubmit { advance() }
            InfoCard(title: L("قبل أن تبدأ"), systemImage: "lock.shield.fill") {
                Text(L("لا تحتاج إلى حساب لاستخدام الدروس المحلية. إذا أنشأت حسابًا لاحقًا، يمكنك مزامنة تقدّمك واستخدام الميزات المتصلة بالإنترنت."))
                Text(L("في التدريب الصوتي الحالي، لا يرفع EnglishNova ملف التسجيل الصوتي الخام إلى خادمه؛ تُستخدم نتائج التعرّف على الكلام لأغراض التدريب."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private func minutesDetail(_ value: Int) -> String {
        switch value {
        case ...5: return LE("خفيف: مراجعة ودرس قصير", "Light: a review and a short lesson")
        case ...10: return LE("منتظم: جلسة يومية كاملة", "Steady: a full daily session")
        case ...15: return LE("جاد: جلسة وتدريب إضافي", "Serious: a session plus extra practice")
        default: return LE("مكثّف: تقدّم أسرع", "Intensive: faster progress")
        }
    }

    // MARK: - Flow

    private func move(to newStep: Int) {
        if reduceMotion { step = newStep } else { withAnimation(.easeInOut(duration: 0.2)) { step = newStep } }
    }

    private func advance() {
        guard !saving else { return }
        if step < stepCount - 1 {
            move(to: step + 1)
            return
        }
        saving = true
        Task {
            settings.selectedLearningPathway = pathway
            settings.dailyGoalMinutes = minutes
            if reminderOn {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
                let hour = parts.hour ?? 19
                let minute = parts.minute ?? 0
                settings.reminderHour = hour
                settings.reminderMinute = minute
                settings.reminderEnabled = await reminderService.requestAndSchedule(hour: hour, minute: minute)
            }
            await session.completeOnboarding(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                level: level
            )
            saving = false
        }
    }
}

/// A large selectable row used by onboarding choices.
private struct OptionRow: View {
    let title: String
    var detail: String? = nil
    let systemImage: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.headline)
                        .foregroundStyle(selected ? .white : AppTheme.brand)
                        .frame(width: 38, height: 38)
                        .background(selected ? AnyShapeStyle(AppTheme.brand) : AnyShapeStyle(AppTheme.brand.opacity(0.12)),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    if let detail {
                        Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? AppTheme.brand : .secondary)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(minHeight: AppTheme.minimumTapHeight)
            .background(AppTheme.cardSurface, in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
                    .stroke(selected ? AppTheme.brand : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
