import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: UserSession
    @EnvironmentObject private var reminderService: StudyReminderService
    @State private var showResetConfirmation = false
    @State private var reminderTime = Date()

    var body: some View {
        Form {
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

            Section("الخدمات عبر الإنترنت") {
                TextField("عنوان الخادم، مثال https://api.example.com", text: $settings.serverURLString)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .environment(\.layoutDirection, .leftToRight)
                Text("اتركه فارغًا لاستخدام المدرّس والمدرب المحليين. يجب أن يكون العنوان HTTPS، ولا تضع مفتاح API سريًا هنا.")
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
                NavigationLink("سياسة الخصوصية المحلية") { PrivacyView() }
            }

            Section("عن التطبيق") {
                LabeledContent("الإصدار", value: "0.4.0")
                Text("الدفعة الرابعة مدمجة داخل مشروع EnglishNova نفسه")
            }
        }
        .navigationTitle("الإعدادات")
        .task {
            reminderTime = Calendar.current.date(from: DateComponents(hour: settings.reminderHour, minute: settings.reminderMinute)) ?? .now
            await reminderService.refreshAuthorization()
        }
        .confirmationDialog("هل تريد العودة إلى شاشة البداية؟", isPresented: $showResetConfirmation) {
            Button("إعادة", role: .destructive) {
                session.hasCompletedOnboarding = false
                Task { await session.save() }
            }
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
            Text("يمكن ترك عنوان الخادم فارغًا، وعندها يستخدم التطبيق محركاته المحلية والاحتياطية فقط.")
        }
        .navigationTitle("الخصوصية")
    }
}
