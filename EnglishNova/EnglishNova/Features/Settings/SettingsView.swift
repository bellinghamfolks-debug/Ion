import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: UserSession
    @EnvironmentObject private var reminderService: StudyReminderService
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var network: NetworkMonitor

    @State private var showResetConfirmation = false
    @State private var showLanguageNotice = false
    @State private var reminderTime = Date()

    var body: some View {
        Form {
            accountSection
            languageSection
            learningSection
            speechSection
            tutorSection
            reminderSection
            dataSection
            privacySection
            helpSection
            aboutSection
        }
        .navigationTitle(L("الإعدادات"))
        .task {
            reminderTime = Calendar.current.date(
                from: DateComponents(hour: settings.reminderHour, minute: settings.reminderMinute)
            ) ?? .now
            if settings.tutorProvider == .gemini { settings.tutorProvider = .smart }
            await reminderService.refreshAuthorization()
        }
        .alert(L("تغيير لغة الواجهة"), isPresented: $showLanguageNotice) {
            Button(L("حسنًا"), role: .cancel) {}
        } message: {
            Text(L("تغيّرت لغة التطبيق. قد تحتاج إلى إغلاق التطبيق وفتحه مرة أخرى حتى تظهر اللغة الجديدة في جميع عناصر iOS."))
        }
        .alert(L("إعادة إعداد البداية؟"), isPresented: $showResetConfirmation) {
            Button(L("إلغاء"), role: .cancel) {}
            Button(L("إعادة الإعداد"), role: .destructive) {
                session.hasCompletedOnboarding = false
                Task { await session.save() }
                ToastCenter.shared.show(L("ستظهر شاشة البداية عند فتح التطبيق"), style: .info)
            }
        } message: {
            Text(L("سيُعاد عرض خطوات البداية فقط. دروسك وتقدّمك والمفردات المحفوظة لن تُحذف."))
        }
    }

    private var accountSection: some View {
        Section {
            NavigationLink { AccountView() } label: {
                HStack(spacing: 14) {
                    Image(systemName: account.isAuthenticated ? "person.crop.circle.fill" : "person.crop.circle.badge.plus")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(AppTheme.brandGradient, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(accountTitle).font(.headline)
                        Text(account.isAuthenticated ? L("إدارة الحساب والمزامنة") : L("سجّل الدخول إذا أردت مزامنة تقدّمك بين أجهزتك"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var languageSection: some View {
        Section(L("اللغة")) {
            Picker(L("لغة الواجهة"), selection: $settings.interfaceLanguage) {
                ForEach(AppSettings.InterfaceLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            Text(L("تغيّر لغة القوائم والأزرار والشروحات. أمثلة الإنجليزية تبقى بالإنجليزية."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: settings.interfaceLanguage) { _, newValue in
            LanguageManager.apply(newValue)
            showLanguageNotice = true
        }
    }

    private var learningSection: some View {
        Section(L("تفضيلات التعلّم")) {
            Stepper(
                Lf("هدف اليوم: %@ دقيقة", "\(settings.dailyGoalMinutes)"),
                value: $settings.dailyGoalMinutes,
                in: 5...120,
                step: 5
            )

            Picker(L("نوع الخطة"), selection: $settings.studyMode) {
                ForEach(StudyMode.allCases) { mode in
                    Text(mode.titleAr).tag(mode)
                }
            }
            Text(settings.studyMode.detailAr)
                .font(.caption)
                .foregroundStyle(.secondary)

            NavigationLink { LearningPathwaysView() } label: {
                LabeledContent(L("المسار"), value: settings.selectedLearningPathway.titleAr)
            }

            Stepper(
                Lf("هدف الأسبوع: %@ أيام", "\(settings.weeklyTargetDays)"),
                value: $settings.weeklyTargetDays,
                in: 2...7
            )

            Toggle(L("اختصر خطة اليوم"), isOn: $settings.reduceLearningPressure)
            Text(L("عند تفعيله، يخفّض التطبيق عدد الأنشطة المقترحة ويحافظ على جلسة أقصر."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var speechSection: some View {
        Section(L("الصوت والمحادثة")) {
            Picker(L("اللكنة"), selection: $settings.accentVariant) {
                ForEach(AccentVariant.allCases) { accent in
                    Text("\(accent.titleAr) • \(accent.titleEn)").tag(accent)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L("سرعة النطق"))
                Slider(value: $settings.speechRate, in: 0.3...0.58)
            }

            Toggle(L("شغّل نموذج الدرس تلقائيًا"), isOn: $settings.autoPlayLessonAudio)
            Toggle(L("اقرأ سؤال المحادثة تلقائيًا"), isOn: $settings.autoSpeakCoachPrompts)
            Toggle(L("أظهر شرح المحادثة بالعربية"), isOn: $settings.showArabicCoachHints)
            Toggle(L("أظهر نص الاستماع بعد الإجابة"), isOn: $settings.revealListeningTranscriptAfterAnswer)
            Toggle(L("الاهتزازات"), isOn: $settings.hapticsEnabled)

            NavigationLink(L("إدارة الأصوات المحمّلة")) { AudioPacksView() }
        }
    }

    private var tutorSection: some View {
        Section(L("المدرّب والذكاء الاصطناعي")) {
            Picker(L("طريقة عمل المدرّب"), selection: $settings.tutorProvider) {
                ForEach(TutorProvider.allCases.filter { $0 != .gemini }) { provider in
                    Text(provider.titleAr).tag(provider)
                }
            }
            Text(settings.tutorProvider.detailAr)
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(L("خصّص الاقتراحات من أدائي"), isOn: $settings.adaptiveCoachEnabled)
            Toggle(L("اقرأ ردود المدرّب تلقائيًا"), isOn: $settings.autoSpeakTutorReplies)

            Label(
                network.isConnected ? L("الاتصال بالإنترنت متاح") : L("لا يوجد اتصال بالإنترنت الآن"),
                systemImage: network.isConnected ? "wifi" : "wifi.slash"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(L("عند استخدام المدرّب عبر الإنترنت، يمكن أن يستفيد من ملخص تعلّمك المتزامن، مثل مستواك وأخطائك ونتائجك الأخيرة. عند انقطاع الاتصال يبقى التدريب المحلي متاحًا."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var reminderSection: some View {
        Section(L("التذكيرات")) {
            Toggle(L("ذكّرني بالدراسة"), isOn: Binding(
                get: { settings.reminderEnabled },
                set: { enabled in Task { await setReminderEnabled(enabled) } }
            ))

            DatePicker(L("وقت التذكير"), selection: $reminderTime, displayedComponents: .hourAndMinute)
                .disabled(!settings.reminderEnabled)
                .onChange(of: reminderTime) { _, newValue in
                    let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                    settings.reminderHour = components.hour ?? 19
                    settings.reminderMinute = components.minute ?? 0
                    if settings.reminderEnabled {
                        Task {
                            try? await reminderService.schedule(
                                hour: settings.reminderHour,
                                minute: settings.reminderMinute
                            )
                        }
                    }
                }

            LabeledContent(L("إذن الإشعارات"), value: reminderService.authorization.titleAr)
        }
    }

    private var dataSection: some View {
        Section(L("البيانات والمزامنة")) {
            NavigationLink(L("الحساب والمزامنة")) { AccountView() }
            NavigationLink(L("النسخ الاحتياطي")) { BackupCenterView() }
            NavigationLink(L("دفتر الأخطاء")) { MistakeNotebookView() }
            NavigationLink(L("تحديث محتوى المنهج")) { ContentUpdatesView() }
            Button(L("إعادة خطوات البداية"), role: .destructive) {
                showResetConfirmation = true
            }
        }
    }

    private var privacySection: some View {
        Section(L("الخصوصية والمعلومات")) {
            NavigationLink(L("سياسة الخصوصية")) { PrivacyView() }
            NavigationLink(L("شروط الاستخدام")) { TermsOfUseView() }
            NavigationLink(L("بيان الوصولية")) { AccessibilityStatementView() }
            NavigationLink(L("دليل الاستخدام")) { UsageGuideView() }
        }
    }

    private var helpSection: some View {
        Section(L("المساعدة والتواصل")) {
            Link(destination: URL(string: "https://x.com/abdullahuksu")!) {
                Label(L("التواصل عبر X"), systemImage: "bubble.left.fill")
            }
            Link(destination: URL(string: "mailto:ubdallahalrashdee@gmail.com")!) {
                Label(L("البريد الإلكتروني"), systemImage: "envelope.fill")
            }
        }
    }

    private var aboutSection: some View {
        Section(L("عن EnglishNova")) {
            LabeledContent(L("الإصدار"), value: appVersion)
            Text(L("EnglishNova يساعدك على تعلّم الإنجليزية بالدروس والمراجعة والتدريب والمحادثة، مع ميزات اختيارية عبر الإنترنت."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var accountTitle: String {
        guard account.isAuthenticated else { return L("الحساب") }
        let display = account.currentUser?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !display.isEmpty { return display }
        return account.currentUser?.email ?? L("الحساب")
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private func setReminderEnabled(_ enabled: Bool) async {
        if enabled {
            let granted = await reminderService.requestAndSchedule(
                hour: settings.reminderHour,
                minute: settings.reminderMinute
            )
            settings.reminderEnabled = granted
            ToastCenter.shared.show(
                granted ? L("تم تفعيل التذكير") : L("لم يُسمح للتطبيق بإرسال الإشعارات"),
                style: granted ? .success : .error
            )
        } else {
            reminderService.cancel()
            settings.reminderEnabled = false
            ToastCenter.shared.show(L("تم إيقاف التذكير"), style: .info)
        }
    }
}
