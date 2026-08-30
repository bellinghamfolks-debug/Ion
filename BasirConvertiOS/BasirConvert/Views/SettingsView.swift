import SwiftUI
import Foundation

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var network: NetworkMonitor
    @State private var showDocumentAdvanced = false

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        BasirHeroCard(
                            title: l10n.t("الإعدادات", "Settings"),
                            systemImage: "gearshape.fill"
                        )
                        languageCard
                        modelCard
                        outputCard
                        documentAdvancedCard
                        networkCard
                        feedbackCard
                        legalCard
                        publicInfoCard
                        InfoCard(
                            title: l10n.t("الخصوصية", "Privacy"),
                            text: l10n.t(
                                "يتصل التطبيق بالاتصال المشفّر فقط. لا توجد إعلانات أو أدوات تتبع. اختيار النموذج يُرسل كمعرّف نموذج فقط ولا يضيف أي بيانات شخصية.",
                                "The app connects only to the encrypted Connection. It has no ads or tracking. Model selection sends only a model identifier and adds no personal data."
                            ),
                            systemImage: "hand.raised.fill"
                        )
                        PrimaryActionButton(
                            title: l10n.t("حفظ وإغلاق", "Save and close"),
                            systemImage: "checkmark.circle.fill"
                        ) {
                            settings.save()
                            dismiss()
                        }
                    }
                    .appScreenContent(bottomPadding: 24)
                }
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 8) }
            }
            .foregroundStyle(.white)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { NetworkStatusPill() }
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.body.weight(.bold))
                    }
                    .foregroundStyle(BasirPalette.cyan)
                    .accessibilityLabel(l10n.t("إغلاق الإعدادات", "Close settings"))
                }
            }
            .onDisappear { settings.save() }
        }
    }

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionTitle(title: l10n.t("لغة التطبيق", "App language"), systemImage: "globe")
            AccessibleSelectionRow(
                title: "العربية",
                selected: l10n.language == .arabic,
                selectedValue: l10n.t("محددة", "Selected")
            ) { l10n.language = .arabic }
            AccessibleSelectionRow(
                title: "English",
                selected: l10n.language == .english,
                selectedValue: l10n.t("محددة", "Selected")
            ) { l10n.language = .english }
        }
        .glassSurface()
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionTitle(title: l10n.t("نموذج الذكاء الاصطناعي", "AI model"), systemImage: "brain.head.profile")
            Picker(l10n.t("النموذج", "Model"), selection: $settings.preferredModel) {
                ForEach(AIModelChoice.allCases) { model in
                    Text(model.title(l10n)).tag(model)
                }
            }
            .pickerStyle(.menu)
            .tint(BasirPalette.cyan)
            Text(settings.preferredModel.detail(l10n))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
        }
        .glassSurface(accent: BasirPalette.cyan)
        .onChange(of: settings.preferredModel) { _ in
            settings.save()
            OperationFeedback.selectionChanged()
        }
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassSectionTitle(title: l10n.t("مخرجات المستند", "Document output"), systemImage: "doc.richtext.fill")
            Picker(l10n.t("محتوى ملف Word", "Word file content"), selection: $settings.outputMode) {
                ForEach(OutputMode.allCases) { mode in
                    Text(mode.title(l10n)).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .tint(BasirPalette.cyan)
            Text(settings.outputMode.detail(l10n))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
            Toggle(isOn: $settings.embedVisuals) {
                    HStack(spacing: 10) {
                        Image(systemName: settings.embedVisuals ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .accessibilityHidden(true)
                        Text(l10n.t("إدراج الصور والشعارات", "Include images and logos"))
                    }
                }
            Toggle(isOn: $settings.includeMath) {
                    HStack(spacing: 10) {
                        Image(systemName: settings.includeMath ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .accessibilityHidden(true)
                        Text(l10n.t("شرح المعادلات الرياضية", "Explain mathematical equations"))
                    }
                }
            Toggle(isOn: $settings.preserveLinks) {
                    HStack(spacing: 10) {
                        Image(systemName: settings.preserveLinks ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .accessibilityHidden(true)
                        Text(l10n.t("الحفاظ على الروابط", "Preserve links"))
                    }
                }
        }
        .tint(BasirPalette.cyan)
        .glassSurface()
        .onChange(of: settings.outputMode) { _ in settings.save(); OperationFeedback.selectionChanged() }
        .onChange(of: settings.embedVisuals) { _ in settings.save(); OperationFeedback.selectionChanged() }
        .onChange(of: settings.includeMath) { _ in settings.save(); OperationFeedback.selectionChanged() }
        .onChange(of: settings.preserveLinks) { _ in settings.save(); OperationFeedback.selectionChanged() }
    }

    private var documentAdvancedCard: some View {
        DisclosureGroup(isExpanded: $showDocumentAdvanced) {
            VStack(alignment: .leading, spacing: 14) {
                Picker(l10n.t("دقة صفحات PDF", "PDF page quality"), selection: $settings.pdfQuality) {
                    Text(l10n.t("سريعة", "Fast")).tag(PDFQuality.fast)
                    Text(l10n.t("متوازنة", "Balanced")).tag(PDFQuality.balanced)
                    Text(l10n.t("عالية", "High")).tag(PDFQuality.accurate)
                }
                .pickerStyle(.menu)
                Toggle(isOn: $settings.skipBlankPages) {
                    HStack(spacing: 10) {
                        Image(systemName: settings.skipBlankPages ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .accessibilityHidden(true)
                        Text(l10n.t("تخطي الصفحات الفارغة", "Skip blank pages"))
                    }
                }
                Toggle(isOn: $settings.preferPDFText) {
                    HStack(spacing: 10) {
                        Image(systemName: settings.preferPDFText ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .accessibilityHidden(true)
                        Text(l10n.t("استخدام نص PDF الأصلي عند موثوقيته", "Use embedded PDF text when reliable"))
                    }
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(l10n.t("صفحات PDF المطلوبة", "PDF pages"))
                        .font(.subheadline.weight(.semibold))
                    TextField(l10n.t("الكل، أو مثال: 1-20، 25", "All, or example: 1-20, 25"), text: $settings.pageSelection)
                        .keyboardType(.numbersAndPunctuation)
                        .padding(12)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    Text(l10n.t("اتركه فارغًا لمعالجة كل الصفحات.", "Leave blank to process every page."))
                        .font(.footnote)
                        .foregroundStyle(BasirPalette.secondaryText)
                }
                Toggle(isOn: $settings.includeSpeakerNotes) {
                    HStack(spacing: 10) {
                        Image(systemName: settings.includeSpeakerNotes ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .accessibilityHidden(true)
                        Text(l10n.t("إدراج ملاحظات الشرائح", "Include slide notes"))
                    }
                }
                Toggle(isOn: $settings.includeHiddenSlides) {
                    HStack(spacing: 10) {
                        Image(systemName: settings.includeHiddenSlides ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .accessibilityHidden(true)
                        Text(l10n.t("إدراج الشرائح المخفية", "Include hidden slides"))
                    }
                }
                Picker(l10n.t("تصحيح دوران PDF", "PDF rotation correction"), selection: $settings.rotationCorrection) {
                    Text(l10n.t("تلقائي", "Automatic")).tag(0)
                    Text("90°").tag(90)
                    Text("180°").tag(180)
                    Text("270°").tag(270)
                }
                .pickerStyle(.menu)
            }
            .padding(.top, 10)
        } label: {
            Label(l10n.t("خيارات PDF والعروض", "PDF and presentation options"), systemImage: "slider.horizontal.3")
                .font(.headline)
                .frame(minHeight: 44)
        }
        .tint(BasirPalette.cyan)
        .glassSurface()
        .onChange(of: settings.pdfQuality) { _ in settings.save(); OperationFeedback.selectionChanged() }
        .onChange(of: settings.skipBlankPages) { _ in settings.save(); OperationFeedback.selectionChanged() }
        .onChange(of: settings.preferPDFText) { _ in settings.save(); OperationFeedback.selectionChanged() }
        .onChange(of: settings.pageSelection) { _ in settings.save() }
        .onChange(of: settings.includeSpeakerNotes) { _ in settings.save(); OperationFeedback.selectionChanged() }
        .onChange(of: settings.includeHiddenSlides) { _ in settings.save(); OperationFeedback.selectionChanged() }
        .onChange(of: settings.rotationCorrection) { _ in settings.save(); OperationFeedback.selectionChanged() }
    }

    private var networkCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassSectionTitle(title: l10n.t("الشبكة والاستئناف", "Network and resume"), systemImage: "wifi")
            Toggle(isOn: $settings.wifiOnly) {
                    HStack(spacing: 10) {
                        Image(systemName: settings.wifiOnly ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .accessibilityHidden(true)
                        Text(l10n.t("رفع الملفات عبر Wi‑Fi فقط", "Upload only on Wi-Fi"))
                    }
                }
            Toggle(isOn: $settings.allowLowData) {
                    HStack(spacing: 10) {
                        Image(systemName: settings.allowLowData ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .accessibilityHidden(true)
                        Text(l10n.t("السماح أثناء وضع البيانات المنخفضة", "Allow Low Data Mode"))
                    }
                }
            Toggle(isOn: $settings.automaticResume) {
                    HStack(spacing: 10) {
                        Image(systemName: settings.automaticResume ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .accessibilityHidden(true)
                        Text(l10n.t("استئناف المهمة تلقائيًا", "Resume tasks automatically"))
                    }
                }
            Text(l10n.t(
                "إذا أوقف iOS المتابعة في الخلفية، يحتفظ بصير بمعرّف المهمة نفسه ويعود إلى مهمة الخدمة بدل إنشاء تحويل جديد.",
                "If iOS suspends background monitoring, Basir keeps the same task identifier and reconnects to the existing service job instead of creating a new conversion."
            ))
            .font(.footnote)
            .foregroundStyle(BasirPalette.secondaryText)
            Text(networkDescription)
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
        }
        .tint(BasirPalette.cyan)
        .glassSurface()
        .onChange(of: settings.wifiOnly) { _ in settings.save(); OperationFeedback.selectionChanged() }
        .onChange(of: settings.allowLowData) { _ in settings.save(); OperationFeedback.selectionChanged() }
        .onChange(of: settings.automaticResume) { _ in settings.save(); OperationFeedback.selectionChanged() }
    }




    private var legalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionTitle(title: l10n.t("القانونية والسياسات", "Legal and policies"), systemImage: "doc.text.fill")
            NavigationLink {
                ServerPublicDocumentView(slug: "terms", isArabic: l10n.isArabic)
            } label: {
                Label(l10n.t("الشروط والأحكام", "Terms and Conditions"), systemImage: "doc.text")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
            }
            NavigationLink {
                ServerPublicDocumentView(slug: "privacy", isArabic: l10n.isArabic)
            } label: {
                Label(l10n.t("سياسة الخصوصية", "Privacy Policy"), systemImage: "hand.raised.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
            }
        }
        .glassSurface()
    }

    private var publicInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionTitle(title: l10n.t("المساعدة والمعلومات", "Help and information"), systemImage: "questionmark.circle.fill")
            NavigationLink {
                ServerPublicDocumentView(slug: "faq", isArabic: l10n.isArabic)
            } label: {
                Label(l10n.t("الأسئلة المتكررة", "Frequently Asked Questions"), systemImage: "questionmark.bubble")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
            }
            NavigationLink {
                ServerPublicDocumentView(slug: "contact", isArabic: l10n.isArabic)
            } label: {
                Label(l10n.t("التواصل", "Contact"), systemImage: "envelope.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
            }
            NavigationLink {
                ServerPublicDocumentView(slug: "about", isArabic: l10n.isArabic)
            } label: {
                Label(l10n.t("عن بصير", "About Basir"), systemImage: "info.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
            }
        }
        .glassSurface()
    }

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassSectionTitle(title: l10n.t("الأصوات والإشعارات", "Sounds and notifications"), systemImage: "speaker.wave.2.fill")
            Picker(l10n.t("صوت المهمة", "Task sound"), selection: $settings.soundTheme) {
                Text(l10n.t("متوقف", "Off")).tag(SoundTheme.off)
                Text(l10n.t("هادئ", "Gentle")).tag(SoundTheme.gentle)
                Text(l10n.t("واضح", "Clear")).tag(SoundTheme.clear)
                Text(l10n.t("اهتزاز فقط", "Haptics only")).tag(SoundTheme.tactile)
            }
            .pickerStyle(.menu)
            .tint(BasirPalette.cyan)
            Toggle(isOn: $settings.notificationsEnabled) {
                    HStack(spacing: 10) {
                        Image(systemName: settings.notificationsEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .accessibilityHidden(true)
                        Text(l10n.t("إشعار عند اكتمال المهمة", "Notify when a task completes"))
                    }
                }
                .onChange(of: settings.notificationsEnabled) { enabled in
                    settings.save()
                    if enabled { Task { _ = await OperationFeedback.requestNotificationPermission() } }
                }
        }
        .tint(BasirPalette.cyan)
        .glassSurface()
        .onChange(of: settings.soundTheme) { _ in settings.save() }
    }



    private var networkDescription: String {
        guard network.snapshot.isConnected else {
            return l10n.t("لا يوجد اتصال بالإنترنت الآن.", "The device is currently offline.")
        }
        var parts = [network.snapshot.usesWiFi ? l10n.t("متصل عبر Wi‑Fi", "Connected by Wi-Fi")
                                                   : l10n.t("متصل عبر بيانات الهاتف", "Connected by cellular data")]
        if network.snapshot.isConstrained {
            parts.append(l10n.t("وضع البيانات المنخفضة مفعّل", "Low Data Mode is active"))
        }
        return parts.joined(separator: " • ")
    }
}


// R21_LEGACY_CI_MARKERS_BEGIN
// basirPublicURL("/legal/terms")
// basirPublicURL("/legal/privacy")
// basirPublicURL("/help/faq")
// basirPublicURL("/contact")
// basirPublicURL("/about")
// R21_LEGACY_CI_MARKERS_END

