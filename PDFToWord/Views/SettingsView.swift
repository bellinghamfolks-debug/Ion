import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var settings: AppSettings
    @State private var enteredKey = ""
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                apiSection
                modelSection
                visualSection
                wordSection
                reliabilitySection
                promptSection
                privacySection
                resetSection
            }
            .navigationTitle(L10n.text("الإعدادات"))
            .alert(L10n.text("إعادة الإعدادات الافتراضية؟"), isPresented: $confirmReset) {
                Button(L10n.text("إلغاء"), role: .cancel) {}
                Button(L10n.text("إعادة"), role: .destructive) { settings.restoreDefaults() }
            } message: {
                Text(L10n.text("لن يُحذف مفتاح Gemini أو سجل التحويل."))
            }
        }
    }

    private var apiSection: some View {
        Section(L10n.text("مفتاح Gemini API")) {
            SecureField(L10n.text("ألصق المفتاح هنا"), text: $enteredKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .privacySensitive()
                .accessibilityLabel(L10n.text("مفتاح Gemini API"))
                .accessibilityHint(L10n.text("المفتاح لا يظهر على الشاشة ويُحفظ في Keychain عند الضغط على حفظ"))

            HStack {
                Button(L10n.text("حفظ في Keychain")) {
                    if appModel.saveAPIKey(enteredKey) {
                        enteredKey = ""
                    }
                }
                .disabled(enteredKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    appModel.testAPIKey(enteredKey, model: settings.options.model)
                } label: {
                    if appModel.isTestingKey {
                        ProgressView().accessibilityLabel(L10n.text("جارٍ اختبار المفتاح"))
                    } else {
                        Text(L10n.text("اختبار المفتاح والنموذج"))
                    }
                }
                .disabled(appModel.isTestingKey)
            }

            if appModel.hasAPIKey {
                Label(L10n.text("يوجد مفتاح محفوظ على هذا الجهاز"), systemImage: "lock.shield.fill")
                    .foregroundStyle(.secondary)
            }

            if let message = appModel.keyStatusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLiveRegion(.polite)
            }

            Button(L10n.text("حذف المفتاح المحفوظ"), role: .destructive) {
                appModel.deleteAPIKey()
            }
            .disabled(!appModel.hasAPIKey)
        }
    }

    private var modelSection: some View {
        Section(L10n.text("النموذج والتحليل")) {
            Picker(L10n.text("نموذج Gemini"), selection: $settings.model) {
                ForEach(settings.availableModels, id: \.self) { model in
                    Text(settings.displayName(forModel: model)).tag(model)
                }
            }

            if settings.model == AppSettings.customModelIdentifier {
                TextField(L10n.text("معرّف النموذج"), text: $settings.customModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Picker(L10n.text("مستوى التفكير"), selection: $settings.thinkingLevel) {
                Text(L10n.text("أدنى، أسرع")).tag("minimal")
                Text(L10n.text("منخفض")).tag("low")
                Text(L10n.text("متوسط")).tag("medium")
                Text(L10n.text("مرتفع، الافتراضي للدقة")).tag("high")
            }

            Text(L10n.text("كل صفحة تُقرأ مرتين بصورة مستقلة ثم تُحسم بقراءة ثالثة. مستوى التفكير المرتفع هو الأنسب، والنتيجة لا تُقبل إذا نزلت بوابة الاتفاق الداخلية عن 95٪."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var visualSection: some View {
        Section(L10n.text("الصور والعناصر البصرية")) {
            Toggle(L10n.text("إنشاء أوصاف تفصيلية للصور"), isOn: $settings.describeImages)
            Toggle(L10n.text("إدراج الصور داخل Word"), isOn: $settings.embedImages)
                .disabled(!settings.describeImages)
            Toggle(L10n.text("إضافة الوصف كنص ظاهر"), isOn: $settings.showImageDescriptions)
                .disabled(!settings.describeImages)
            Toggle(L10n.text("إدراج الصور الزخرفية"), isOn: $settings.includeDecorativeImages)
                .disabled(!settings.describeImages)
            Toggle(L10n.text("الاحتفاظ بالرؤوس والتذييلات كنص"), isOn: $settings.preserveHeadersAndFooters)
            Toggle(L10n.text("فواصل صفحات مطابقة للـ PDF"), isOn: $settings.preservePageBreaks)
            Toggle(L10n.text("حفظ مقاس الصفحة واتجاهها"), isOn: $settings.preservePageSizeAndOrientation)
                .disabled(!settings.preservePageBreaks)
            Toggle(L10n.text("إضافة أرقام الصفحات"), isOn: $settings.addPageNumbers)

            Text(L10n.text("يُكتب الوصف في خاصية النص البديل داخل Word. ويمكن أيضًا إظهاره أسفل العنصر لضمان قراءته في التطبيقات التي لا تعلن النص البديل جيدًا."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var wordSection: some View {
        Section(L10n.text("تنسيق ملف Word")) {
            TextField(L10n.text("خط النص العربي"), text: $settings.bodyFontArabic)
            TextField(L10n.text("خط النص اللاتيني"), text: $settings.bodyFontLatin)

            VStack(alignment: .leading) {
                Text(L10n.format("حجم النص: %.0f نقطة", settings.bodyFontSize))
                Slider(value: $settings.bodyFontSize, in: 9...20, step: 1)
                    .accessibilityValue(L10n.format("القيمة بالنقاط: %d", Int(settings.bodyFontSize)))
            }

            VStack(alignment: .leading) {
                Text(L10n.format("حجم العنوان الرئيسي: %.0f نقطة", settings.headingFontSize))
                Slider(value: $settings.headingFontSize, in: 14...32, step: 1)
                    .accessibilityValue(L10n.format("القيمة بالنقاط: %d", Int(settings.headingFontSize)))
            }

            VStack(alignment: .leading) {
                Text(L10n.format("هوامش الصفحة: %.0f نقطة", settings.pageMarginPoints))
                Slider(value: $settings.pageMarginPoints, in: 24...90, step: 6)
                    .accessibilityValue(L10n.format("القيمة بالنقاط: %d", Int(settings.pageMarginPoints)))
            }
        }
    }

    private var reliabilitySection: some View {
        Section(L10n.text("الدقة والاعتمادية")) {
            Stepper(
                L10n.format("عدد الصفحات المتزامنة: %d", settings.concurrency),
                value: $settings.concurrency,
                in: 1...3
            )
            Stepper(
                L10n.format("إعادة المحاولة لكل صفحة: %d", settings.retryCount),
                value: $settings.retryCount,
                in: 0...6
            )

            Label(L10n.text("صورة عالية الدقة مع ملف PDF الأصلي"), systemImage: "viewfinder")
            Label(L10n.text("مرجع OCR محلي دون اعتباره حقيقة نهائية"), systemImage: "text.viewfinder")
            Label(L10n.text("قراءتان مستقلتان وتحكيم ثالث"), systemImage: "checkmark.seal")
            Label(L10n.text("بوابة قبول داخلية ثابتة: 95٪"), systemImage: "shield.checkered")

            Text(L10n.text("لا يستخدم هذا الإصدار النص المحلي كبديل صامت، ولا ينشئ ملف Word إذا كانت إحدى الصفحات دون حد القبول. درجة 95٪ هنا مقياس اتفاق وفحص داخلي، وليست ضمانًا علميًا لدقة كل خط يدوي دون عينة مرجعية بشرية."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var promptSection: some View {
        Section(L10n.text("تعليمات مخصصة")) {
            TextEditor(text: $settings.promptAddendum)
                .frame(minHeight: 120)
                .accessibilityLabel(L10n.text("تعليمات إضافية لنموذج Gemini"))
            Text(L10n.text("مثال: اجعل عناوين المواد القانونية من المستوى الأول، ولا تفصل رقم المادة عن نصها. لا تطلب التلخيص لأن وظيفة التطبيق هي النقل الكامل."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var privacySection: some View {
        Section(L10n.text("الخصوصية والأمان")) {
            Label(L10n.text("المفتاح محفوظ في Keychain بوضع هذا الجهاز فقط"), systemImage: "key.horizontal.fill")
            Label(L10n.text("ملف PDF ونتائج الصفحات محمية بحماية ملفات iOS الكاملة"), systemImage: "lock.doc.fill")
            Label(L10n.text("تُرسل كل صفحة إلى Gemini، ثم يُنشأ DOCX محليًا"), systemImage: "iphone.and.arrow.forward")

            Text(L10n.text("Keychain يمنع التخزين المكشوف، لكنه لا يجعل مفتاح API مستحيل الاستخراج من جهاز مخترق أو معدل. هذا الأسلوب مناسب لتطبيقك الشخصي بمفتاحك، وليس لتوزيع مفتاح مشترك على المستخدمين."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var resetSection: some View {
        Section {
            Button(L10n.text("إعادة إعدادات التحويل الافتراضية"), role: .destructive) {
                confirmReset = true
            }
        }
    }
}
