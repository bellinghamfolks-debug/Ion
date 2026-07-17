import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: UserSession
    @EnvironmentObject private var reminderService: StudyReminderService
    @EnvironmentObject private var account: AccountService
    @State private var showResetConfirmation = false
    @State private var reminderTime = Date()
    @State private var geminiKeyEntry = ""

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
                            Text(account.isAuthenticated ? "الحساب والمزامنة" : "سجّل الدخول لمزامنة تعلّمك عبر أجهزتك")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("اللغة") {
                Picker("لغة الواجهة", selection: $settings.interfaceLanguage) {
                    ForEach(AppSettings.InterfaceLanguage.allCases) { Text($0.title).tag($0) }
                }
                Text("تُغيّر لغة عناصر الواجهة واتجاهها فورًا.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("التعلّم") {
                Stepper(
                    "الهدف اليومي: \(settings.dailyGoalMinutes) دقيقة",
                    value: $settings.dailyGoalMinutes,
                    in: 5...120,
                    step: 5
                )
                Picker("نمط الدراسة", selection: $settings.studyMode) {
                    ForEach(StudyMode.allCases) { mode in
                        Text(mode.titleAr).tag(mode)
                    }
                }
                NavigationLink { LearningPathwaysView() } label: {
                    LabeledContent("المسار الحالي", value: settings.selectedLearningPathway.titleAr)
                }
                Stepper(
                    "هدف الأسبوع: \(settings.weeklyTargetDays) أيام",
                    value: $settings.weeklyTargetDays,
                    in: 2...7
                )
                Text(settings.studyMode.detailAr)
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("المدرب الشخصي التكيفي", isOn: $settings.adaptiveCoachEnabled)
                Text("يستخدم نتائج الدروس والمراجعة والنطق ودفتر الأخطاء لترتيب الاقتراحات، ويعمل محليًا.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("تشغيل صوت النموذج تلقائيًا داخل الدرس", isOn: $settings.autoPlayLessonAudio)
                Toggle("وضع التعلّم الهادئ", isOn: $settings.reduceLearningPressure)
                Text("وضع التعلّم الهادئ يجعل الخطة اليومية أقصر ويخفف لغة الضغط والتحفيز المبالغ فيه.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("الاهتزازات", isOn: $settings.hapticsEnabled)
            }

            Section("النطق والمحادثة") {
                Picker("اللكنة الأساسية", selection: $settings.accentVariant) {
                    ForEach(AccentVariant.allCases) { accent in
                        Text("\(accent.titleAr) • \(accent.titleEn)").tag(accent)
                    }
                }
                VStack(alignment: .leading) {
                    Text("سرعة النطق")
                    Slider(value: $settings.speechRate, in: 0.3...0.58)
                }
                Toggle("نطق أسئلة المدرب تلقائيًا", isOn: $settings.autoSpeakCoachPrompts)
                Toggle("إظهار تلميحات المدرب بالعربية", isOn: $settings.showArabicCoachHints)
                Toggle("إظهار نص الاستماع بعد التصحيح", isOn: $settings.revealListeningTranscriptAfterAnswer)
                Text("تحليل النطق داخل التطبيق يقارن تفريغ الكلام وتوقيته وثقة نظام التعرف. لا يدّعي قياس مخارج الحروف مخبريًا.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("التذكير اليومي") {
                Toggle("تفعيل تذكير الدراسة", isOn: Binding(
                    get: { settings.reminderEnabled },
                    set: { enabled in Task { await setReminderEnabled(enabled) } }
                ))
                DatePicker("وقت التذكير", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    .disabled(!settings.reminderEnabled)
                    .onChange(of: reminderTime) { _, newValue in
                        let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                        settings.reminderHour = components.hour ?? 19
                        settings.reminderMinute = components.minute ?? 0
                        if settings.reminderEnabled {
                            Task { try? await reminderService.schedule(hour: settings.reminderHour, minute: settings.reminderMinute) }
                        }
                    }
                LabeledContent("إذن الإشعارات", value: reminderService.authorization.titleAr)
            }

            Section("الصوت والعمل دون إنترنت") {
                NavigationLink("إدارة حزم الصوت") { AudioPacksView() }
                Text("يبقى صوت iOS المحلي متاحًا عند عدم وجود حزمة مسجلة. المحتوى والدروس ودفتر الأخطاء والمدرب الاحتياطي تعمل دون خادم.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("المدرّس التفاعلي") {
                Picker("مصدر إجابات المدرّس", selection: $settings.tutorProvider) {
                    ForEach(TutorProvider.allCases) { provider in
                        Text(provider.titleAr).tag(provider)
                    }
                }
                Text(settings.tutorProvider.detailAr)
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("نطق ردود المدرّس تلقائيًا", isOn: $settings.autoSpeakTutorReplies)
                Text("يقرأ التطبيق رد المدرّس صوتيًا فور وصوله، ويبقى زر الاستماع متاحًا في كل رد لقارئ الشاشة.")
                    .font(.caption).foregroundStyle(.secondary)

                if settings.tutorProvider == .gemini {
                    SecureField(settings.hasGeminiAPIKey ? "المفتاح محفوظ — أدخل مفتاحًا جديدًا للتغيير" : "أدخل مفتاح Gemini API", text: $geminiKeyEntry)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight)
                    HStack {
                        Button("حفظ المفتاح") {
                            settings.setGeminiAPIKey(geminiKeyEntry)
                            geminiKeyEntry = ""
                        }
                        .disabled(geminiKeyEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if settings.hasGeminiAPIKey {
                            Spacer()
                            Button("حذف المفتاح", role: .destructive) {
                                settings.clearGeminiAPIKey()
                                geminiKeyEntry = ""
                            }
                        }
                    }
                    Label(
                        settings.hasGeminiAPIKey ? "المفتاح محفوظ بشكل مشفّر على هذا الجهاز فقط" : "لم يُحفظ مفتاح بعد",
                        systemImage: settings.hasGeminiAPIKey ? "lock.fill" : "lock.open"
                    )
                    .font(.caption).foregroundStyle(settings.hasGeminiAPIKey ? Color.green : Color.secondary)
                    TextField("اسم النموذج", text: $settings.geminiModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight)
                    Text("يُحفظ المفتاح في سلسلة المفاتيح المشفّرة (Keychain) ولا يُكتب في ملفات الإعداد ولا في النسخ الاحتياطي. مثال للنموذج: gemini-1.5-flash.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("الخدمات عبر الإنترنت") {
                Label("متصل بخادم EnglishNova", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(AppTheme.success)
                Text("يتصل التطبيق تلقائيًا بخادم EnglishNova لإنشاء الحساب وحفظ التقدّم عبر أجهزتك — دون أي إعداد.")
                    .font(.caption).foregroundStyle(.secondary)
                NavigationLink("تحديثات المنهج") { ContentUpdatesView() }
            }

            Section("الحساب المحلي والبيانات") {
                LabeledContent("المستوى", value: session.selectedLevel.rawValue)
                LabeledContent("النقاط", value: "\(session.points)")
                NavigationLink("دفتر الأخطاء") { MistakeNotebookView() }
                NavigationLink("النسخ الاحتياطي والاستعادة") { BackupCenterView() }
                Button("إعادة شاشة البداية", role: .destructive) { showResetConfirmation = true }
            }

            Section("الوصولية والخصوصية") {
                NavigationLink("بيان الوصولية") { AccessibilityStatementView() }
                NavigationLink("سياسة الخصوصية") { PrivacyView() }
            }

            Section("تواصل مع المطوّر") {
                Link(destination: URL(string: "https://x.com/abdullahuksu")!) {
                    Label("حساب X (تويتر)", systemImage: "bird")
                }
                Link(destination: URL(string: "mailto:ubdallahalrashdee@gmail.com")!) {
                    Label("البريد الإلكتروني", systemImage: "envelope.fill")
                }
            }

            Section("عن التطبيق") {
                NavigationLink("دليل الاستخدام") { UsageGuideView() }
                LabeledContent("الإصدار", value: "1.0.0")
                Text("EnglishNova — رحلتك لتعلّم الإنجليزية من الصفر إلى الاحتراف، مع مدرّب ذكي ومزامنة لتقدّمك عبر أجهزتك.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("الإعدادات")
        .task {
            reminderTime = Calendar.current.date(from: DateComponents(hour: settings.reminderHour, minute: settings.reminderMinute)) ?? .now
            await reminderService.refreshAuthorization()
        }
        .alert("العودة إلى شاشة البداية؟", isPresented: $showResetConfirmation) {
            Button("إلغاء", role: .cancel) {}
            Button("العودة", role: .destructive) {
                session.hasCompletedOnboarding = false
                Task { await session.save() }
            }
        } message: {
            Text("سيعيدك هذا إلى خطوات الإعداد الأولى. تقدّمك لن يُحذف، لكن ستمرّ بشاشة البداية من جديد.")
        }
    }

    private func setReminderEnabled(_ enabled: Bool) async {
        if enabled {
            let granted = await reminderService.requestAndSchedule(
                hour: settings.reminderHour,
                minute: settings.reminderMinute
            )
            settings.reminderEnabled = granted
        } else {
            reminderService.cancel()
            settings.reminderEnabled = false
        }
    }
}

struct AccessibilityStatementView: View {
    var body: some View {
        List {
            Text("يدعم التطبيق VoiceOver، أحجام الخط الديناميكية، ترتيب قراءة منطقي، وأزرارًا كبيرة.")
            Text("يمكن تنفيذ المحادثة والاختبارات بالكتابة أو أزرار التسجيل الواضحة، ولا توجد حركة سحب إلزامية لإكمال نشاط.")
            Text("تقارير النطق والقراءة والاستماع والكتابة تسرد النتيجة والملاحظات نصيًا، ولا تعتمد على مخطط بصري أو لون وحده.")
            Text("الاختيارات في مختبرات الفهم أزرار واضحة مع حالة منطوقة لقارئ الشاشة، ولا تتطلب سحبًا أو توقيتًا بصريًا.")
            Text("تمارين ترتيب الكلمات قابلة للاستخدام عبر أزرار مرقمة دون الحاجة إلى السحب.")
            Text("القصص المتفرعة والمحادثات تعرض النص الإنجليزي والترجمة والتغذية الراجعة بترتيب واضح لقارئ الشاشة.")
            Text("أي محتوى بصري يضاف لاحقًا يجب أن يحتوي وصفًا نصيًا دقيقًا، وإلا يُستبدل بوصف نصي كامل.")
        }
        .navigationTitle("بيان الوصولية")
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Text("يعمل المحتوى الأساسي والاختبار التكيفي والتقييم المحلي ودفتر الأخطاء دون حساب ودون خادم خاص بالتطبيق.")
            Text("تُحفظ بيانات التقدم والقاموس وتقارير النطق والأخطاء وجلسات القراءة والاستماع والكتابة وحالات الإتقان محليًا مع حماية ملفات النظام.")
            Text("لا يرسل EnglishNova التسجيل الصوتي الخام إلى الخادم الذي تعينه. عند استخدام التعرف على الكلام، قد تعالج خدمة النظام الصوت وفق إعدادات iOS وسياسات Apple وتوفر المعالجة على الجهاز.")
            Text("عند تعيين خادم خارجي واستخدام المدرب المتصل، يرسل التطبيق النص المفرغ وسياق الموقف والنتيجة المحلية، ولا يرسل التسجيل الخام ضمن العقد الحالي.")
            Text("ملفات النسخ الاحتياطي تُنشأ على الجهاز ولا تُرسل تلقائيًا. أنت تختار مكان حفظها أو مشاركتها.")
            Text("تُحفظ محادثات المدرّس التفاعلي على هذا الجهاز فقط للرجوع إليها، ويمكنك حذف أي محادثة في أي وقت.")
            Text("عند اختيار مزوّد Gemini، يُرسل نص رسالتك إلى خدمة Google عبر مفتاحك الخاص. يُحفظ المفتاح مشفّرًا في سلسلة المفاتيح (Keychain) على هذا الجهاز فقط، ولا يُكتب في ملفات الإعداد ولا في النسخ الاحتياطي.")
            Text("يمكن ترك عنوان الخادم فارغًا، وعندها يستخدم التطبيق محركاته المحلية والاحتياطية فقط.")
        }
        .navigationTitle("الخصوصية")
    }
}
