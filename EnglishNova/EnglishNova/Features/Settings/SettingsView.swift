import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: UserSession
    @EnvironmentObject private var reminderService: StudyReminderService
    @EnvironmentObject private var account: AccountService
    @State private var showResetConfirmation = false
    @State private var showLanguageRestart = false
    @State private var reminderTime = Date()

    var body: some View {
        Form {
            Section {
                NavigationLink { AccountView() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: account.isAuthenticated ? "person.crop.circle.fill" : "person.crop.circle.badge.plus")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(AppTheme.brandGradient, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.isAuthenticated
                                 ? (account.currentUser?.displayName.isEmpty == false ? account.currentUser!.displayName : (account.currentUser?.email ?? "حسابك"))
                                 : "إنشاء حساب وحفظ التقدّم")
                                .font(.headline)
                            Text(account.isAuthenticated ? L("الحساب والمزامنة") : L("سجّل الدخول لمزامنة تعلّمك عبر أجهزتك"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section(L("اللغة")) {
                Picker(L("لغة الواجهة"), selection: $settings.interfaceLanguage) {
                    ForEach(AppSettings.InterfaceLanguage.allCases) { Text($0.title).tag($0) }
                }
                Text(L("لتطبيق تغيير اللغة بالكامل سيُطلب إعادة تشغيل التطبيق."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .onChange(of: settings.interfaceLanguage) { _, newValue in
                LanguageManager.apply(newValue)
                showLanguageRestart = true
            }

            Section(L("التعلّم")) {
                Stepper(
                    "الهدف اليومي: \(settings.dailyGoalMinutes) دقيقة",
                    value: $settings.dailyGoalMinutes,
                    in: 5...120,
                    step: 5
                )
                Picker(L("نمط الدراسة"), selection: $settings.studyMode) {
                    ForEach(StudyMode.allCases) { mode in
                        Text(L(mode.titleAr)).tag(mode)
                    }
                }
                NavigationLink { LearningPathwaysView() } label: {
                    LabeledContent(L("المسار الحالي"), value: settings.selectedLearningPathway.titleAr)
                }
                Stepper(
                    "هدف الأسبوع: \(settings.weeklyTargetDays) أيام",
                    value: $settings.weeklyTargetDays,
                    in: 2...7
                )
                Text(settings.studyMode.detailAr)
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(L("المدرب الشخصي التكيفي"), isOn: $settings.adaptiveCoachEnabled)
                Text(L("يستخدم نتائج الدروس والمراجعة والنطق ودفتر الأخطاء لترتيب الاقتراحات، ويعمل محليًا."))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(L("تشغيل صوت النموذج تلقائيًا داخل الدرس"), isOn: $settings.autoPlayLessonAudio)
                Toggle(L("وضع التعلّم الهادئ"), isOn: $settings.reduceLearningPressure)
                Text(L("وضع التعلّم الهادئ يجعل الخطة اليومية أقصر ويخفف لغة الضغط والتحفيز المبالغ فيه."))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(L("الاهتزازات"), isOn: $settings.hapticsEnabled)
            }

            Section(L("النطق والمحادثة")) {
                Picker(L("اللكنة الأساسية"), selection: $settings.accentVariant) {
                    ForEach(AccentVariant.allCases) { accent in
                        Text("\(accent.titleAr) • \(accent.titleEn)").tag(accent)
                    }
                }
                VStack(alignment: .leading) {
                    Text(L("سرعة النطق"))
                    Slider(value: $settings.speechRate, in: 0.3...0.58)
                }
                Toggle(L("نطق أسئلة المدرب تلقائيًا"), isOn: $settings.autoSpeakCoachPrompts)
                Toggle(L("إظهار تلميحات المدرب بالعربية"), isOn: $settings.showArabicCoachHints)
                Toggle(L("إظهار نص الاستماع بعد التصحيح"), isOn: $settings.revealListeningTranscriptAfterAnswer)
                Text(L("تحليل النطق داخل التطبيق يقارن تفريغ الكلام وتوقيته وثقة نظام التعرف. لا يدّعي قياس مخارج الحروف مخبريًا."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L("التذكير اليومي")) {
                Toggle(L("تفعيل تذكير الدراسة"), isOn: Binding(
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
                            Task { try? await reminderService.schedule(hour: settings.reminderHour, minute: settings.reminderMinute) }
                        }
                    }
                LabeledContent(L("إذن الإشعارات"), value: reminderService.authorization.titleAr)
            }

            Section(L("الصوت والعمل دون إنترنت")) {
                NavigationLink(L("إدارة حزم الصوت")) { AudioPacksView() }
                Text(L("يبقى صوت iOS المحلي متاحًا عند عدم وجود حزمة مسجلة. المحتوى والدروس ودفتر الأخطاء والمدرب الاحتياطي تعمل دون خادم."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L("المدرّس التفاعلي")) {
                // The AI tutor now runs on the server (one shared key), so the
                // personal Gemini key + model fields are gone. Users only choose
                // between the smart (server) tutor and the offline local tutor.
                Picker(L("مصدر إجابات المدرّس"), selection: $settings.tutorProvider) {
                    ForEach(TutorProvider.allCases.filter { $0 != .gemini }) { provider in
                        Text(L(provider.titleAr)).tag(provider)
                    }
                }
                Text(settings.tutorProvider.detailAr)
                    .font(.caption).foregroundStyle(.secondary)

                Toggle(L("نطق ردود المدرّس تلقائيًا"), isOn: $settings.autoSpeakTutorReplies)
                Text(L("يقرأ التطبيق رد المدرّس صوتيًا فور وصوله، ويبقى زر الاستماع متاحًا في كل رد لقارئ الشاشة."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L("الخدمات عبر الإنترنت")) {
                Label(L("متصل بخادم EnglishNova"), systemImage: "checkmark.seal.fill")
                    .foregroundStyle(AppTheme.success)
                Text(L("يتصل التطبيق تلقائيًا بخادم EnglishNova لإنشاء الحساب وحفظ التقدّم والمدرّب الذكي عبر أجهزتك — دون أي إعداد."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L("الحساب المحلي والبيانات")) {
                LabeledContent(L("المستوى"), value: session.selectedLevel.rawValue)
                LabeledContent(L("النقاط"), value: "\(session.points)")
                NavigationLink(L("دفتر الأخطاء")) { MistakeNotebookView() }
                NavigationLink(L("النسخ الاحتياطي والاستعادة")) { BackupCenterView() }
                Button(L("إعادة شاشة البداية"), role: .destructive) { showResetConfirmation = true }
            }

            Section(L("الوصولية والخصوصية")) {
                NavigationLink(L("بيان الوصولية")) { AccessibilityStatementView() }
                NavigationLink(L("سياسة الخصوصية")) { PrivacyView() }
            }

            Section(L("تواصل مع المطوّر")) {
                Link(destination: URL(string: "https://x.com/abdullahuksu")!) {
                    Label(L("حساب X (تويتر)"), systemImage: "bird")
                }
                Link(destination: URL(string: "mailto:ubdallahalrashdee@gmail.com")!) {
                    Label(L("البريد الإلكتروني"), systemImage: "envelope.fill")
                }
            }

            Section(L("عن التطبيق")) {
                NavigationLink(L("دليل الاستخدام")) { UsageGuideView() }
                LabeledContent(L("الإصدار"), value: "1.0.0")
                Text(L("EnglishNova — رحلتك لتعلّم الإنجليزية من الصفر إلى الاحتراف، مع مدرّب ذكي ومزامنة لتقدّمك عبر أجهزتك."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L("الإعدادات"))
        .task {
            reminderTime = Calendar.current.date(from: DateComponents(hour: settings.reminderHour, minute: settings.reminderMinute)) ?? .now
            // Migrate anyone still on the retired personal-Gemini provider to the
            // server-backed smart tutor.
            if settings.tutorProvider == .gemini { settings.tutorProvider = .smart }
            await reminderService.refreshAuthorization()
        }
        .alert(L("إعادة تشغيل مطلوبة"), isPresented: $showLanguageRestart) {
            Button(L("أعد التشغيل الآن"), role: .destructive) { LanguageManager.restart() }
            Button(L("لاحقًا"), role: .cancel) {}
        } message: {
            Text(L("لتطبيق اللغة الجديدة بالكامل سيُغلق التطبيق الآن، ثم أعد فتحه."))
        }
        .alert(L("العودة إلى شاشة البداية؟"), isPresented: $showResetConfirmation) {
            Button(L("إلغاء"), role: .cancel) {}
            Button(L("العودة"), role: .destructive) {
                session.hasCompletedOnboarding = false
                Task { await session.save() }
                ToastCenter.shared.show("ستبدأ من شاشة الإعداد", style: .info)
            }
        } message: {
            Text(L("سيعيدك هذا إلى خطوات الإعداد الأولى. تقدّمك لن يُحذف، لكن ستمرّ بشاشة البداية من جديد."))
        }
    }

    private func setReminderEnabled(_ enabled: Bool) async {
        if enabled {
            let granted = await reminderService.requestAndSchedule(
                hour: settings.reminderHour,
                minute: settings.reminderMinute
            )
            settings.reminderEnabled = granted
            ToastCenter.shared.show(granted ? L("تم تفعيل التذكير اليومي") : L("لم يُمنح إذن الإشعارات"),
                                    style: granted ? .success : .error)
        } else {
            reminderService.cancel()
            settings.reminderEnabled = false
            ToastCenter.shared.show("تم إيقاف التذكير", style: .info)
        }
    }
}

struct AccessibilityStatementView: View {
    var body: some View {
        List {
            Text(L("يدعم التطبيق VoiceOver، أحجام الخط الديناميكية، ترتيب قراءة منطقي، وأزرارًا كبيرة."))
            Text(L("يمكن تنفيذ المحادثة والاختبارات بالكتابة أو أزرار التسجيل الواضحة، ولا توجد حركة سحب إلزامية لإكمال نشاط."))
            Text(L("تقارير النطق والقراءة والاستماع والكتابة تسرد النتيجة والملاحظات نصيًا، ولا تعتمد على مخطط بصري أو لون وحده."))
            Text(L("الاختيارات في مختبرات الفهم أزرار واضحة مع حالة منطوقة لقارئ الشاشة، ولا تتطلب سحبًا أو توقيتًا بصريًا."))
            Text(L("تمارين ترتيب الكلمات قابلة للاستخدام عبر أزرار مرقمة دون الحاجة إلى السحب."))
            Text(L("القصص المتفرعة والمحادثات تعرض النص الإنجليزي والترجمة والتغذية الراجعة بترتيب واضح لقارئ الشاشة."))
            Text(L("أي محتوى بصري يضاف لاحقًا يجب أن يحتوي وصفًا نصيًا دقيقًا، وإلا يُستبدل بوصف نصي كامل."))
        }
        .navigationTitle(L("بيان الوصولية"))
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section(L("الحساب")) {
                Text(L("عند إنشاء حساب، نحفظ بريدك الإلكتروني واسمك المعروض في خادم EnglishNova. تُحفظ كلمة المرور **مشفّرة (bcrypt)** ولا يستطيع أحد — بمن فيهم نحن — قراءتها."))
                Text(L("عند استخدام «الدخول عبر Apple»، نحفظ معرّفًا مجهولًا من Apple لربط حسابك، ولا نطّلع على بيانات إضافية."))
            }
            Section(L("حفظ التقدّم والمزامنة")) {
                Text(L("يُرفع تقدّمك (النقاط، السلسلة، نتائج المهارات، القاموس، الإعدادات) إلى حسابك في الخادم لتستعيده على أي جهاز. لا نبيع بياناتك ولا نشاركها مع أطراف إعلانية."))
                Text(L("يمكنك أيضًا تصدير نسخة محلية كملف تتحكّم أنت بمكانها ومشاركتها."))
            }
            Section(L("المدرّب الذكي (AI)")) {
                Text(L("عند استخدام المدرّب الذكي، يُرسَل **نص رسالتك ومستواك** إلى خادمنا ثم إلى خدمة Google Gemini لإنشاء الرد. لا نرسل تسجيلك الصوتي الخام. إن تعذّر الاتصال يعمل مدرّب محلي على جهازك."))
            }
            Section(L("الصوت والنطق")) {
                Text(L("يُعالَج التعرّف على الكلام عبر نظام iOS وفق سياسات Apple (قد يكون على الجهاز)، ولا نرسل التسجيل الصوتي الخام إلى خادمنا."))
            }
            Section(L("بيانات على جهازك")) {
                Text(L("صورة ملفك الشخصي تُحفظ على جهازك فقط ولا تُرفع إلى الخادم."))
                Text(L("رمز جلسة الدخول يُحفظ مشفّرًا في سلسلة المفاتيح (Keychain) على هذا الجهاز فقط."))
                Text(L("تُحفظ محادثات المدرّب على جهازك للرجوع إليها، ويمكنك حذفها في أي وقت."))
            }
            Section(L("حقوقك")) {
                Text(L("لطلب حذف حسابك وبياناتك من الخادم، تواصل مع المطوّر عبر X (‎@abdullahuksu‎) أو البريد ubdallahalrashdee@gmail.com."))
            }
        }
        .navigationTitle(L("سياسة الخصوصية"))
    }
}
