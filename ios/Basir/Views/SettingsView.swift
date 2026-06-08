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
                Text(L10n.t("المظهر والخط", "Appearance and text"))
            }

            Section(L10n.t("الصوت والاهتزاز", "Voice and vibration")) {
                Toggle(L10n.t("نطق النتائج والتنبيهات", "Speak results and alerts"),
                       isOn: $settings.speechEnabled)
                Toggle(L10n.t("الاهتزاز للتأكيد والتنبيه", "Vibration for confirmation and alerts"),
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
                Toggle(L10n.t("عدم حفظ سجل النشاط", "Don't save activity history"),
                       isOn: $settings.privacyMode)
                Toggle(L10n.t("حفظ نتائج التحليل تلقائيًا", "Automatically save analysis results"),
                       isOn: $settings.autoSaveResults)
            } header: {
                Text(L10n.t("الخصوصية والتخزين المحلي", "Privacy and local storage"))
            } footer: {
                Text(L10n.t(
                    "الخيار الأول يمنع إضافة عمليات جديدة إلى سجل النشاط، ولا يحذف السجل السابق. الخيار الثاني يتحكم في إضافة النتائج الجديدة إلى المحفوظات المحلية. لا يمنع أي منهما إرسال المحتوى إلى Gemini عند تشغيل ميزة تعتمد عليه.",
                    "The first option prevents new activity-log entries but does not delete existing history. The second controls whether new results are added to the local archive. Neither option prevents content from being sent to Gemini when you use an AI-powered feature."
                ))
            }

            Section {
                Picker(L10n.t("وضع الاتصال", "Connection mode"),
                       selection: $settings.aiMode) {
                    Text(L10n.t("اتصال مباشر بـ Gemini",
                                 "Direct connection to Gemini")).tag("direct")
                    Text(L10n.t("عبر خادم وسيط",
                                 "Through a proxy server")).tag("proxy")
                }
                .pickerStyle(.segmented)
            } header: {
                Text(L10n.t("وضع الاتصال بالذكاء الاصطناعي",
                             "AI connection mode"))
            } footer: {
                Text(L10n.t(
                    "الاتصال المباشر يرسل طلباتك إلى Google Gemini مباشرة باستخدام مفتاحك. الخادم الوسيط يحتفظ بالمفتاح في خادمك أو خادم منظمتك، فلا تكتب أنت أي مفتاح على الجهاز.",
                    "Direct mode sends your requests to Google Gemini using your own key. Proxy mode keeps the key on a server you or your organization run, so you do not enter any key on this device."
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
                    Button(L10n.t("حفظ المفتاح على هذا الجهاز", "Save key on this device")) {
                        KeychainStore.setGeminiKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                        showSavedToast = true
                        apiKey = ""
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text(L10n.t("إعداد Google Gemini", "Google Gemini setup"))
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
                        "يجب أن يكون العنوان على بروتوكول HTTPS لمنع التنصت. إذا فعّل مشغل الخادم رمزًا مشتركًا فأدخله هنا؛ يُرسَل ضمن الترويسة X-Basir-Client-Token. بصير لا يصادق هوية الخادم أو سياسته — أنت مسؤول عن اختيار خادم تثق به.",
                        "The URL must be HTTPS to prevent eavesdropping. If your server requires a shared token, paste it here; it is sent in the X-Basir-Client-Token header. Basir does not authenticate the server's identity or policy — you are responsible for choosing a server you trust."
                    ))
                }
            }

            Section {
                Picker(L10n.t("جودة المهام السريعة", "Quick-task quality"),
                       selection: $settings.quickQuality) {
                    Text(L10n.t("أسرع · Flash Lite", "Fastest · Flash Lite")).tag("fast")
                    Text(L10n.t("متوازن · Flash", "Balanced · Flash")).tag("balanced")
                    Text(L10n.t("أعلى جودة · Pro", "Best quality · Pro")).tag("best")
                }
                Picker(L10n.t("جودة معالجة المستندات", "Document-processing quality"),
                       selection: $settings.docQuality) {
                    Text(L10n.t("أسرع · Flash Lite", "Fastest · Flash Lite")).tag("fast")
                    Text(L10n.t("متوازن · Flash", "Balanced · Flash")).tag("balanced")
                    Text(L10n.t("أعلى جودة · Pro", "Best quality · Pro")).tag("best")
                }
            } header: {
                Text(L10n.t("جودة النموذج", "Model quality"))
            } footer: {
                Text(L10n.t(
                    "في الوضع المباشر يحدد هذا الخيار الموديل الذي يطلبه بصير من Gemini. في وضع الخادم الوسيط، يحدد مشغل الخادم الموديل الفعلي وقد يتجاهل هذا الاختيار.",
                    "In Direct mode this controls which Gemini model Basir requests. In Proxy mode the server operator decides which model is actually called and may ignore this preference."
                ))
            }

            Section {
                TextField(L10n.t("رقم جهة المساعدة، مثال: +9665XXXXXXXX",
                                  "Help contact number, e.g. +9665XXXXXXXX"),
                          text: $settings.emergencyContact)
                    .keyboardType(.phonePad)
            } header: {
                Text(L10n.t("جهة طلب المساعدة", "Help contact"))
            } footer: {
                Text(L10n.t(
                    "لا يرسل بصير الرسالة تلقائيًا. يفتح تطبيق الرسائل لتراجع المستلم والنص ثم تضغط إرسال بنفسك.",
                    "Basir does not send a message automatically. It opens the messaging app so you can review the recipient and text and then tap Send yourself."
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
                Text(L10n.t("البيانات المحلية", "Local data"))
            } footer: {
                Text(L10n.t(
                    "يحذف المحفوظات والنتائج وسجل النشاط والمستند الأخير والملفات المؤقتة من هذا الجهاز. لا يحذف مفتاح Gemini ولا الملفات التي صدّرتها إلى تطبيق الملفات.",
                    "Deletes saved items, results, activity history, the last document, and temporary files from this device. It does not delete the Gemini key or files you exported to the Files app."
                ))
            }
        }
        .navigationTitle(L10n.t("الإعدادات", "Settings"))
        .toolbar(.hidden, for: .tabBar)
        .alert(L10n.t("تم حفظ المفتاح", "Key saved"), isPresented: $showSavedToast) {
            Button(L10n.t("حسنًا", "OK"), role: .cancel) {}
        } message: {
            Text(L10n.t("حُفظ المفتاح في iOS Keychain على هذا الجهاز.",
                        "The key was saved in the iOS Keychain on this device."))
        }
        .confirmationDialog(
            L10n.t("تغيير لغة التطبيق؟", "Change app language?"),
            isPresented: $showLanguageConfirm, titleVisibility: .visible
        ) {
            Button(L10n.t("تغيير", "Change")) {
                if let lang = pendingLanguage { settings.language = lang }
                pendingLanguage = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { pendingLanguage = nil }
        } message: {
            Text(L10n.t("ستُعاد تهيئة اتجاه الواجهة ونصوصها باللغة الجديدة.",
                        "The interface direction and text will be reloaded in the new language."))
        }
        .confirmationDialog(
            L10n.t("حذف جميع البيانات المحلية؟", "Delete all local data?"),
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
            Text(L10n.t("لا يمكن التراجع عن هذا الإجراء.",
                        "This action cannot be undone."))
        }
        .alert(L10n.t("تم الحذف", "Deleted"), isPresented: $showDeletedToast) {
            Button(L10n.t("حسنًا", "OK"), role: .cancel) {}
        } message: {
            Text(L10n.t("حُذفت البيانات المحلية من هذا الجهاز.",
                        "Local data was deleted from this device."))
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
