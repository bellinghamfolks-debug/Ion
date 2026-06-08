// SettingsView.swift
// Native, VoiceOver-friendly settings for Basir on iOS.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: BasirSettings
    @State private var apiKey: String = ""
    @State private var showSavedToast = false
    @State private var pendingLanguage: AppLanguage?
    @State private var showLanguageConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showDeletedToast = false

    var body: some View {
        Form {
            Section(L10n.t("اللغة", "Language")) {
                // Confirm before switching, since it re-lays out the whole
                // app (RTL/LTR) — a deliberate confirmation step.
                Picker(L10n.t("لغة التطبيق", "App language"),
                       selection: Binding(
                        get: { settings.language },
                        set: { newValue in
                            if newValue != settings.language {
                                pendingLanguage = newValue
                                showLanguageConfirm = true
                            }
                        }
                       )) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            }

            Section {
                Picker(L10n.t("المظهر", "Appearance"), selection: $settings.appearance) {
                    Text(L10n.t("حسب النظام", "Match system")).tag("system")
                    Text(L10n.t("فاتح", "Light")).tag("light")
                    Text(L10n.t("داكن", "Dark")).tag("dark")
                }
                Stepper(value: $settings.fontStep, in: 0...4) {
                    Text(L10n.t("حجم الخط", "Text size") + ": \(settings.fontStep)/4")
                }
                .accessibilityLabel(L10n.t("حجم الخط، المستوى \(settings.fontStep) من 4",
                                           "Text size, level \(settings.fontStep) of 4"))
            } header: {
                Text(L10n.t("المظهر وحجم النص", "Appearance and text size"))
            }

            Section(L10n.t("الصوت والاهتزاز", "Voice and vibration")) {
                Toggle(L10n.t("نطق النتائج والتنبيهات تلقائيًا", "Speak results and alerts automatically"),
                       isOn: $settings.speechEnabled)
                Toggle(L10n.t("اهتزاز عند اكتمال العملية أو حدوث تنبيه", "Vibrate when a task finishes or an alert occurs"),
                       isOn: $settings.vibrationEnabled)
                HStack {
                    Text(L10n.t("سرعة النطق", "Speech rate"))
                    Slider(value: $settings.ttsRate, in: 0.5...1.5, step: 0.1)
                        .accessibilityLabel(L10n.t("سرعة النطق", "Speech rate"))
                    Text(String(format: "%.1f×", settings.ttsRate))
                        .monospacedDigit()
                }
            }

            Section {
                Toggle(L10n.t("عدم تسجيل النشاط", "Do not record activity"),
                       isOn: $settings.privacyMode)
                Toggle(L10n.t("حفظ النتائج الجديدة تلقائيًا", "Automatically save new results"),
                       isOn: $settings.autoSaveResults)
            } header: {
                Text(L10n.t("الخصوصية والتخزين المحلي", "Privacy and local storage"))
            } footer: {
                Text(L10n.t(
                    "منع تسجيل النشاط يوقف إضافة عمليات جديدة فقط، ولا يحذف السجل السابق. الحفظ التلقائي يضيف النتائج الجديدة إلى قسم النتائج المحفوظة. لا يغيّر أي من الخيارين طريقة إرسال المحتوى عند استخدام ميزات الذكاء الاصطناعي.",
                    "Disabling activity recording stops new log entries but does not delete existing history. Automatic saving adds new results to Saved Results. Neither setting changes how content is sent when you use AI features."
                ))
            }

            Section {
                Picker(L10n.t("وضع الاتصال", "Connection mode"),
                       selection: $settings.aiMode) {
                    Text(L10n.t("مباشر باستخدام مفتاحي",
                                 "Direct with my API key")).tag("direct")
                    Text(L10n.t("عبر خادم وسيط",
                                 "Through a proxy server")).tag("proxy")
                }
                .pickerStyle(.segmented)
            } header: {
                Text(L10n.t("الاتصال بخدمة الذكاء الاصطناعي",
                             "AI service connection"))
            } footer: {
                Text(L10n.t(
                    "في الاتصال المباشر، يرسل بصير الطلب إلى Google Gemini باستخدام مفتاحك المحفوظ على الجهاز. أما الخادم الوسيط فيحتفظ بالمفتاح على خادمك أو خادم منظمتك، فلا تحتاج إلى إدخاله هنا.",
                    "With a direct connection, Basir sends requests to Google Gemini using the key saved on this device. A proxy keeps the key on your server or your organization's server, so you do not enter it here."
                ))
            }

            if settings.aiMode == "direct" {
                Section {
                    SecureField(L10n.t("مفتاح Gemini API", "Gemini API key"),
                                text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel(L10n.t(
                            "حقل مفتاح Gemini API. الأحرف مخفية.",
                            "Gemini API key field. Characters are hidden."
                        ))
                    Button(L10n.t("حفظ المفتاح بأمان", "Save key securely")) {
                        KeychainStore.setGeminiKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                        showSavedToast = true
                        apiKey = ""
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text(L10n.t("مفتاح Google Gemini", "Google Gemini API key"))
                } footer: {
                    Text(L10n.t(
                        "تشترط Google حاليًا أن يكون استخدام Gemini API لمن بلغ 18 عامًا ولأغراض مهنية أو تجارية مسموحة. وقد تستخدم محتوى الخدمات غير المدفوعة لتحسين منتجاتها ويجوز أن يراجعه أشخاص مخولون. لا ترسل معلومات شخصية أو سرية قبل مراجعة سياسة الخصوصية وشروط مشروعك.",
                        "Google currently requires Gemini API users to be 18 or older and to use the service for permitted professional or business purposes. Google may use content from unpaid services to improve its products, and authorized people may review it. Do not submit personal or confidential information before reviewing the Privacy Policy and your project terms."
                    ))
                }
            } else {
                Section {
                    TextField(L10n.t("عنوان الخادم الوسيط (HTTPS)",
                                      "Proxy server URL (HTTPS)"),
                              text: $settings.proxyURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(L10n.t("الرمز السري المشترك (اختياري)",
                                         "Shared client token (optional)"),
                                text: $settings.proxyToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text(L10n.t("إعداد الخادم الوسيط", "Proxy server setup"))
                } footer: {
                    Text(L10n.t(
                        "يجب أن يبدأ العنوان بـ HTTPS. إذا كان الخادم يتطلب رمزًا مشتركًا، فأدخله في الحقل المخصص. استخدم خادمًا تثق به، لأن بصير لا يستطيع التحقق من سياساته أو طريقة حفظه للبيانات.",
                        "The address must use HTTPS. If the server requires a shared token, enter it in the field above. Use a server you trust, because Basir cannot verify its policies or data-handling practices."
                    ))
                }
            }

            Section {
                Picker(L10n.t("جودة الصور والأسئلة", "Image and question quality"),
                       selection: $settings.quickQuality) {
                    Text(L10n.t("الأسرع · Flash Lite", "Fastest · Flash Lite")).tag("fast")
                    Text(L10n.t("متوازن · Flash", "Balanced · Flash")).tag("balanced")
                    Text(L10n.t("الأدق · Pro", "Most accurate · Pro")).tag("best")
                }
                Picker(L10n.t("جودة المستندات", "Document quality"),
                       selection: $settings.docQuality) {
                    Text(L10n.t("الأسرع · Flash Lite", "Fastest · Flash Lite")).tag("fast")
                    Text(L10n.t("متوازن · Flash", "Balanced · Flash")).tag("balanced")
                    Text(L10n.t("الأدق · Pro", "Most accurate · Pro")).tag("best")
                }
            } header: {
                Text(L10n.t("سرعة وجودة النتائج", "Speed and result quality"))
            } footer: {
                Text(L10n.t(
                    "عند استخدام الاتصال المباشر، يحدد هذا الاختيار توازن السرعة والدقة والتكلفة. أما في وضع الخادم الوسيط، فقد يحدد مشغل الخادم نموذجًا مختلفًا.",
                    "With a direct connection, this controls the balance of speed, accuracy, and cost. In proxy mode, the server operator may choose a different model."
                ))
            }

            Section {
                TextField(L10n.t("رقم شخص موثوق، مثال: +9665XXXXXXXX",
                                  "Trusted contact number, e.g. +9665XXXXXXXX"),
                          text: $settings.emergencyContact)
                    .keyboardType(.phonePad)
            } header: {
                Text(L10n.t("جهة موثوقة للمساعدة", "Trusted help contact"))
            } footer: {
                Text(L10n.t(
                    "يستخدم بصير هذا الرقم عند إنشاء رسالة مساعدة. سيفتح تطبيق الرسائل لتراجع المستلم والنص، ولن يتم الإرسال تلقائيًا.",
                    "Basir uses this number when creating a help message. The Messages app opens so you can review the recipient and text; nothing is sent automatically."
                ))
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label(L10n.t("حذف جميع البيانات المحلية",
                                 "Delete all local data"),
                          systemImage: "trash")
                }
            } header: {
                Text(L10n.t("إدارة البيانات المحلية", "Manage local data"))
            } footer: {
                Text(L10n.t(
                    "يحذف الملاحظات والنتائج المحفوظة وسجل النشاط والمستند الأخير والملفات المؤقتة من هذا الجهاز. لن يحذف مفتاح Gemini أو الملفات التي حفظتها في تطبيق الملفات.",
                    "Deletes notes, saved results, activity history, the last document, and temporary files from this device. It does not delete your Gemini key or files saved in the Files app."
                ))
            }
        }
        .navigationTitle(L10n.t("الإعدادات", "Settings"))
        .toolbar(.hidden, for: .tabBar)
        .alert(L10n.t("حُفظ المفتاح", "Key saved"), isPresented: $showSavedToast) {
            Button(L10n.t("حسنًا", "OK"), role: .cancel) {}
        } message: {
            Text(L10n.t("حُفظ المفتاح بأمان في سلسلة مفاتيح iPhone على هذا الجهاز.",
                        "The key was saved securely in the iPhone Keychain on this device."))
        }
        .confirmationDialog(
            L10n.t("تغيير لغة بصير؟", "Change Basir language?"),
            isPresented: $showLanguageConfirm, titleVisibility: .visible
        ) {
            Button(L10n.t("تغيير", "Change")) {
                if let lang = pendingLanguage { settings.language = lang }
                pendingLanguage = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { pendingLanguage = nil }
        } message: {
            Text(L10n.t("ستتغير نصوص الواجهة واتجاهها فورًا إلى اللغة الجديدة.",
                        "The interface text and direction will switch immediately to the new language."))
        }
        .confirmationDialog(
            L10n.t("حذف البيانات المحفوظة على هذا الجهاز؟", "Delete data saved on this device?"),
            isPresented: $showDeleteConfirm, titleVisibility: .visible
        ) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                ArchiveStore.shared.clearAll()
                LastDocumentStore.shared.text = nil
                LastDocumentStore.shared.sourceName = nil
                clearTempFiles()
                showDeletedToast = true
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("سيُحذف السجل والملاحظات والنتائج المحلية نهائيًا، ولا يمكن التراجع عن ذلك.",
                        "Local history, notes, and saved results will be permanently deleted. This cannot be undone."))
        }
        .alert(L10n.t("اكتمل الحذف", "Deletion complete"), isPresented: $showDeletedToast) {
            Button(L10n.t("حسنًا", "OK"), role: .cancel) {}
        } message: {
            Text(L10n.t("حُذفت البيانات المحلية المحفوظة على هذا الجهاز.",
                        "Data saved locally on this device was deleted."))
        }
    }

    /// Best-effort cleanup of the app's temporary directory.
    private func clearTempFiles() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        if let items = try? fm.contentsOfDirectory(at: tmp,
                                                   includingPropertiesForKeys: nil) {
            for url in items { try? fm.removeItem(at: url) }
        }
    }
}
