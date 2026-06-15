import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: BasirSettings
    @State private var apiKey = ""
    @State private var showSavedToast = false
    @State private var showClearedKeyToast = false
    @State private var pendingLanguage: AppLanguage?
    @State private var showLanguageConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showDeletedToast = false

    var body: some View {
        Form {
            Section {
                BasirStatusBanner(
                    text: settings.isConfigured
                        ? L10n.t("الاتصال بالذكاء الاصطناعي مُعدّ وجاهز للاستخدام.",
                                 "The AI connection is configured and ready to use.")
                        : L10n.t("أكمل قسم الاتصال أدناه حتى تعمل ميزات الوصف والتحليل.",
                                 "Complete the connection section below to use description and analysis features."),
                    tone: settings.isConfigured ? .success : .warning,
                    title: settings.isConfigured
                        ? L10n.t("جاهز للعمل", "Ready")
                        : L10n.t("الإعداد غير مكتمل", "Setup incomplete")
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                Picker(L10n.t("لغة الواجهة", "Interface language"),
                       selection: Binding(
                        get: { settings.language },
                        set: { newValue in
                            guard newValue != settings.language else { return }
                            pendingLanguage = newValue
                            showLanguageConfirm = true
                        }
                       )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }

                Picker(L10n.t("المظهر", "Appearance"), selection: $settings.appearance) {
                    Text(L10n.t("تلقائي حسب iPhone", "Follow iPhone")).tag("system")
                    Text(L10n.t("فاتح", "Light")).tag("light")
                    Text(L10n.t("داكن", "Dark")).tag("dark")
                }

                Picker(L10n.t("حجم النص داخل بصير", "Text size in Basir"), selection: $settings.fontStep) {
                    Text(L10n.t("الافتراضي", "Default")).tag(0)
                    Text(L10n.t("كبير", "Large")).tag(1)
                    Text(L10n.t("أكبر", "Larger")).tag(2)
                    Text(L10n.t("كبير جدًا", "Extra large")).tag(3)
                    Text(L10n.t("حجم وصول", "Accessibility size")).tag(4)
                }
            } header: {
                Label(L10n.t("اللغة والمظهر", "Language and appearance"), systemImage: "textformat.size")
            } footer: {
                Text(L10n.t(
                    "يتغير اتجاه الواجهة تلقائيًا عند اختيار العربية أو الإنجليزية. يحترم بصير أيضًا إعدادات تكبير النص والتباين في iPhone.",
                    "The interface direction changes automatically for Arabic or English. Basir also respects iPhone text-size and contrast settings."
                ))
            }

            Section {
                Toggle(L10n.t("نطق النتائج المهمة تلقائيًا", "Speak important results automatically"),
                       isOn: $settings.speechEnabled)
                Toggle(L10n.t("اهتزاز عند اكتمال مهمة أو ظهور تنبيه", "Vibrate when a task finishes or an alert appears"),
                       isOn: $settings.vibrationEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.t("سرعة النطق", "Speech rate"))
                        Spacer()
                        Text(String(format: "%.1f×", settings.ttsRate))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.ttsRate, in: 0.5...1.5, step: 0.1)
                        .accessibilityLabel(L10n.t("سرعة النطق", "Speech rate"))
                        .accessibilityValue(String(format: "%.1f", settings.ttsRate))
                }
            } header: {
                Label(L10n.t("الصوت والاهتزاز", "Speech and vibration"), systemImage: "speaker.wave.2.fill")
            }

            Section {
                Toggle(L10n.t("وضع الخصوصية: عدم إضافة نشاط جديد إلى السجل", "Privacy mode: do not add new activity to history"),
                       isOn: $settings.privacyMode)
                Toggle(L10n.t("حفظ النتائج الجديدة تلقائيًا على الجهاز", "Automatically save new results on this device"),
                       isOn: $settings.autoSaveResults)
            } header: {
                Label(L10n.t("الخصوصية والحفظ", "Privacy and saving"), systemImage: "hand.raised.fill")
            } footer: {
                Text(L10n.t(
                    "وضع الخصوصية يمنع إنشاء سجلات جديدة ولا يحذف السجل السابق. الحفظ التلقائي يضيف النتائج إلى قسم النتائج المحفوظة. كلا الخيارين محليان ولا يغيّران المحتوى المرسل عند تشغيل الذكاء الاصطناعي.",
                    "Privacy mode stops new history entries but does not delete existing history. Automatic saving adds results to Saved Results. Both are local settings and do not change the content sent when AI runs."
                ))
            }

            Section {
                Picker(L10n.t("طريقة الاتصال", "Connection method"), selection: $settings.aiMode) {
                    Label(L10n.t("مباشر باستخدام مفتاحي", "Direct with my key"),
                          systemImage: "key.fill").tag("direct")
                    Label(L10n.t("عبر خادم وسيط", "Through a proxy server"),
                          systemImage: "server.rack").tag("proxy")
                }
                .pickerStyle(.inline)
            } header: {
                Label(L10n.t("الاتصال بالذكاء الاصطناعي", "AI connection"), systemImage: "network")
            } footer: {
                Text(settings.aiMode == "direct"
                     ? L10n.t("تُرسل الطلبات مباشرة إلى Google Gemini باستخدام المفتاح المحفوظ في سلسلة مفاتيح iPhone.",
                              "Requests are sent directly to Google Gemini using the key stored in the iPhone Keychain.")
                     : L10n.t("تُرسل الطلبات إلى الخادم الذي تحدده. استخدم خادمًا موثوقًا يدعم HTTPS.",
                              "Requests are sent to the server you specify. Use a trusted server that supports HTTPS."))
            }

            if settings.aiMode == "direct" {
                directConnectionSection
            } else {
                proxyConnectionSection
            }

            Section {
                Picker(L10n.t("الأسئلة والصور", "Questions and images"), selection: $settings.quickQuality) {
                    Text(L10n.t("اقتصادي وأسرع", "Economical and fastest")).tag("fast")
                    Text(L10n.t("متوازن", "Balanced")).tag("balanced")
                    Text(L10n.t("أعلى دقة", "Highest accuracy")).tag("best")
                }
                Picker(L10n.t("المستندات والمعادلات", "Documents and equations"), selection: $settings.docQuality) {
                    Text(L10n.t("اقتصادي وأسرع", "Economical and fastest")).tag("fast")
                    Text(L10n.t("متوازن", "Balanced")).tag("balanced")
                    Text(L10n.t("أعلى دقة", "Highest accuracy")).tag("best")
                }
            } header: {
                Label(L10n.t("السرعة والدقة", "Speed and accuracy"), systemImage: "speedometer")
            } footer: {
                Text(L10n.t(
                    "الدقة الأعلى أبطأ وقد تستهلك حصة أو تكلفة أكبر. في وضع الخادم الوسيط قد يختار مشغل الخادم نموذجًا مختلفًا.",
                    "Higher accuracy is slower and may use more quota or cost. In proxy mode, the server operator may choose a different model."
                ))
            }

            Section {
                TextField(L10n.t("مثال: +9665XXXXXXXX", "Example: +9665XXXXXXXX"),
                          text: $settings.emergencyContact)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            } header: {
                Label(L10n.t("جهة موثوقة للمساعدة", "Trusted help contact"), systemImage: "person.crop.circle.badge.checkmark")
            } footer: {
                Text(L10n.t(
                    "يُستخدم الرقم فقط لتعبئة مستلم رسالة المساعدة. يفتح تطبيق الرسائل لتراجع النص والمستلم، ولا يتم الإرسال تلقائيًا.",
                    "The number is used only to fill the recipient of a help message. Messages opens for review, and nothing is sent automatically."
                ))
            }

            Section {
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Label(L10n.t("حذف الملاحظات والنتائج والسجل المحلي", "Delete local notes, results, and history"),
                          systemImage: "trash.fill")
                }
            } header: {
                Label(L10n.t("إدارة البيانات المحلية", "Manage local data"), systemImage: "internaldrive.fill")
            } footer: {
                Text(L10n.t(
                    "يحذف البيانات التي أنشأها بصير على هذا الجهاز، ولا يحذف مفتاح Gemini أو الملفات التي حفظتها بنفسك في تطبيق الملفات.",
                    "Deletes data created by Basir on this device. It does not delete your Gemini key or files you saved in the Files app."
                ))
            }
        }
        .scrollContentBackground(.hidden)
        .background(BasirTheme.screenBackground)
        .navigationTitle(L10n.t("الإعدادات", "Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .alert(L10n.t("تم حفظ المفتاح", "Key saved"), isPresented: $showSavedToast) {
            Button(L10n.t("حسنًا", "OK"), role: .cancel) {}
        } message: {
            Text(L10n.t("حُفظ المفتاح في سلسلة مفاتيح iPhone على هذا الجهاز.",
                        "The key was saved in the iPhone Keychain on this device."))
        }
        .alert(L10n.t("تم مسح المفتاح", "Key removed"), isPresented: $showClearedKeyToast) {
            Button(L10n.t("حسنًا", "OK"), role: .cancel) {}
        } message: {
            Text(L10n.t("لن يعمل الاتصال المباشر حتى تضيف مفتاحًا جديدًا.",
                        "Direct connection will not work until you add a new key."))
        }
        .confirmationDialog(
            L10n.t("تغيير لغة الواجهة؟", "Change interface language?"),
            isPresented: $showLanguageConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.t("تغيير اللغة", "Change language")) {
                if let pendingLanguage { settings.language = pendingLanguage }
                pendingLanguage = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { pendingLanguage = nil }
        } message: {
            Text(L10n.t("ستتغير النصوص واتجاه الواجهة فورًا.",
                        "Text and interface direction will change immediately."))
        }
        .confirmationDialog(
            L10n.t("حذف البيانات المحلية نهائيًا؟", "Permanently delete local data?"),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.t("حذف البيانات", "Delete data"), role: .destructive) {
                ArchiveStore.shared.clearAll()
                LastDocumentStore.shared.clear()
                clearTempFiles()
                showDeletedToast = true
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("سيُحذف السجل والملاحظات والنتائج المحلية، ولا يمكن التراجع عن ذلك.",
                        "Local history, notes, and results will be deleted and cannot be restored."))
        }
        .alert(L10n.t("اكتمل الحذف", "Deletion complete"), isPresented: $showDeletedToast) {
            Button(L10n.t("حسنًا", "OK"), role: .cancel) {}
        } message: {
            Text(L10n.t("حُذفت البيانات المحلية من هذا الجهاز.",
                        "Local data was deleted from this device."))
        }
    }

    private var directConnectionSection: some View {
        Section {
            SecureField(L10n.t("ألصق مفتاح Gemini API", "Paste Gemini API key"), text: $apiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .privacySensitive()

            Button {
                KeychainStore.setGeminiKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                apiKey = ""
                showSavedToast = true
            } label: {
                Label(L10n.t("حفظ المفتاح بأمان", "Save key securely"), systemImage: "key.fill")
            }
            .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if !KeychainStore.geminiKey().isEmpty {
                Button(role: .destructive) {
                    KeychainStore.setGeminiKey("")
                    showClearedKeyToast = true
                } label: {
                    Label(L10n.t("مسح المفتاح المحفوظ", "Remove saved key"), systemImage: "key.slash.fill")
                }
            }
        } header: {
            Text(L10n.t("مفتاح Google Gemini", "Google Gemini key"))
        } footer: {
            Text(L10n.t(
                "المفتاح مخفي ومحفوظ محليًا. قد تختلف معالجة Google للمحتوى بحسب نوع مشروعك وفوترته؛ لا ترسل معلومات سرية قبل مراجعة شروط حسابك.",
                "The key is hidden and stored locally. Google's handling of content may vary by project and billing status; do not send confidential information before reviewing your account terms."
            ))
        }
    }

    private var proxyConnectionSection: some View {
        Section {
            TextField(L10n.t("عنوان الخادم، يبدأ بـ https://", "Server URL, starting with https://"),
                      text: $settings.proxyURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField(L10n.t("رمز وصول مشترك، اختياري", "Shared access token, optional"),
                        text: $settings.proxyToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .privacySensitive()
        } header: {
            Text(L10n.t("الخادم الوسيط", "Proxy server"))
        } footer: {
            Text(L10n.t(
                "يجب أن يستخدم العنوان HTTPS. بصير لا يستطيع التحقق من سياسة الخادم أو مدة احتفاظه بالبيانات.",
                "The address must use HTTPS. Basir cannot verify the server's policy or data-retention period."
            ))
        }
    }

    private func clearTempFiles() {
        let manager = FileManager.default
        if let items = try? manager.contentsOfDirectory(
            at: manager.temporaryDirectory,
            includingPropertiesForKeys: nil
        ) {
            for url in items { try? manager.removeItem(at: url) }
        }
    }
}
