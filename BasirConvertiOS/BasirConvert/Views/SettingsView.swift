import SwiftUI
import Foundation

/// Settings, split in 3.1: everyday options here, document and model options
/// under "Advanced", and policies and help under "About Basir".
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var network: NetworkMonitor

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: BasirSpacing.l) {
                        Text(l10n.t("الإعدادات", "Settings"))
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                        languageCard
                        appearanceCard
                        feedbackCard
                        networkCard
                        SectionHeading(title: l10n.t("المزيد", "More"))
                        VStack(spacing: 0) {
                            settingsLink(l10n.t("خيارات متقدمة", "Advanced options"),
                                         detail: l10n.t("النموذج، محتوى Word، خيارات PDF والعروض",
                                                        "Model, Word content, PDF and presentation options"),
                                         systemImage: "slider.horizontal.3") { AdvancedSettingsView() }
                            Divider().padding(.leading, 44)
                            settingsLink(l10n.t("عن بصير", "About Basir"),
                                         detail: l10n.t("الشروط والخصوصية والمساعدة", "Terms, privacy, and help"),
                                         systemImage: "info.circle") { AboutBasirView() }
                        }
                        .glassSurface(padding: BasirSpacing.s)
                    }
                    .appScreenContent(bottomPadding: 24)
                }
            }
            .foregroundStyle(BasirPalette.primaryText)
            .navigationTitle(l10n.t("الإعدادات", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(l10n.t("تم", "Done")) {
                        settings.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(BasirPalette.accent)
                }
            }
            .onDisappear { settings.save() }
        }
        .escapeToDismiss {
            settings.save()
            dismiss()
        }
    }

    private func settingsLink<Destination: View>(
        _ title: String,
        detail: String,
        systemImage: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: BasirSpacing.m) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(BasirPalette.accent)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(BasirPalette.primaryText)
                    Text(detail).font(.footnote).foregroundStyle(BasirPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BasirPalette.tertiaryText)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 56)
            .padding(.horizontal, BasirSpacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
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

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            GlassSectionTitle(title: l10n.t("المظهر", "Appearance"), systemImage: "circle.lefthalf.filled")
            ForEach(AppAppearance.allCases) { option in
                AccessibleSelectionRow(
                    title: option.title(l10n),
                    selected: settings.appearance == option,
                    selectedValue: l10n.t("محدد", "Selected")
                ) {
                    settings.appearance = option
                    OperationFeedback.selectionChanged()
                }
            }
            if BasirTheme.supportsInAppHighContrast {
                Toggle(isOn: $settings.highContrast) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(l10n.t("تباين عالٍ", "High contrast"))
                            .font(.body.weight(.semibold))
                        Text(l10n.t("ألوان أقوى وحدود أوضح ونص أغمق.", "Stronger colors, clearer borders, and darker text."))
                            .font(.footnote)
                            .foregroundStyle(BasirPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(BasirPalette.accent)
            } else {
                Text(l10n.t("للتباين العالي فعّل «زيادة التباين» من إعدادات تسهيلات الاستخدام في iPhone.",
                            "For high contrast, turn on Increase Contrast in the iPhone Accessibility settings."))
                    .font(.footnote)
                    .foregroundStyle(BasirPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .glassSurface()
    }

    private var networkCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            GlassSectionTitle(title: l10n.t("الشبكة والاستئناف", "Network and resume"), systemImage: "wifi")
            Toggle(l10n.t("رفع الملفات عبر Wi‑Fi فقط", "Upload only on Wi-Fi"), isOn: $settings.wifiOnly)
            Toggle(l10n.t("السماح أثناء وضع البيانات المنخفضة", "Allow Low Data Mode"), isOn: $settings.allowLowData)
            Toggle(l10n.t("استئناف المهام تلقائيًا", "Resume tasks automatically"), isOn: $settings.automaticResume)
            Text(networkDescription)
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
        }
        .tint(BasirPalette.accent)
        .glassSurface()
        .onChange(of: settings.wifiOnly) { _ in settings.save(); OperationFeedback.selectionChanged() }
        .onChange(of: settings.allowLowData) { _ in settings.save(); OperationFeedback.selectionChanged() }
        .onChange(of: settings.automaticResume) { _ in settings.save(); OperationFeedback.selectionChanged() }
    }

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            GlassSectionTitle(title: l10n.t("الأصوات والإشعارات", "Sounds and notifications"), systemImage: "speaker.wave.2.fill")
            Picker(l10n.t("صوت المهمة", "Task sound"), selection: $settings.soundTheme) {
                Text(l10n.t("متوقف", "Off")).tag(SoundTheme.off)
                Text(l10n.t("هادئ", "Gentle")).tag(SoundTheme.gentle)
                Text(l10n.t("واضح", "Clear")).tag(SoundTheme.clear)
                Text(l10n.t("اهتزاز فقط", "Haptics only")).tag(SoundTheme.tactile)
            }
            .pickerStyle(.menu)
            .tint(BasirPalette.accent)
            Toggle(l10n.t("إشعار عند اكتمال المهمة", "Notify when a task completes"), isOn: $settings.notificationsEnabled)
                .onChange(of: settings.notificationsEnabled) { enabled in
                    settings.save()
                    if enabled { Task { _ = await OperationFeedback.requestNotificationPermission() } }
                }
        }
        .tint(BasirPalette.accent)
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

/// Model, Word content, and PDF / presentation options.
struct AdvancedSettingsView: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: BasirSpacing.l) {
                    Text(l10n.t("خيارات متقدمة", "Advanced options"))
                        .font(.title.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    modelCard
                    outputCard
                    documentCard
                }
                .appScreenContent(bottomPadding: 24)
            }
        }
        .foregroundStyle(BasirPalette.primaryText)
        .navigationTitle(l10n.t("خيارات متقدمة", "Advanced options"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            GlassSectionTitle(title: l10n.t("نموذج الذكاء الاصطناعي", "AI model"), systemImage: "brain.head.profile")
            Picker(l10n.t("النموذج", "Model"), selection: $settings.preferredModel) {
                ForEach(AIModelChoice.allCases) { model in
                    Text(model.title(l10n)).tag(model)
                }
            }
            .pickerStyle(.menu)
            .tint(BasirPalette.accent)
            Text(settings.preferredModel.detail(l10n))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassSurface()
        .onChange(of: settings.preferredModel) { _ in
            settings.save()
            OperationFeedback.selectionChanged()
        }
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            GlassSectionTitle(title: l10n.t("محتوى ملف Word", "Word file content"), systemImage: "doc.richtext.fill")
            ForEach(OutputMode.allCases) { mode in
                AccessibleSelectionRow(
                    title: mode.title(l10n),
                    detail: mode.detail(l10n),
                    selected: settings.outputMode == mode,
                    selectedValue: l10n.t("محدد", "Selected")
                ) { settings.outputMode = mode }
            }
            Toggle(l10n.t("إدراج الصور والشعارات", "Include images and logos"), isOn: $settings.embedVisuals)
            Toggle(l10n.t("شرح المعادلات الرياضية", "Explain mathematical equations"), isOn: $settings.includeMath)
            Toggle(l10n.t("الحفاظ على الرموز ومعانيها", "Preserve symbols and their meaning"), isOn: $settings.preserveSymbols)
            Toggle(l10n.t("الحفاظ على الروابط", "Preserve links"), isOn: $settings.preserveLinks)
        }
        .tint(BasirPalette.accent)
        .glassSurface()
        .onChange(of: settings.outputMode) { _ in settings.save(); OperationFeedback.selectionChanged() }
        .onChange(of: settings.embedVisuals) { _ in settings.save(); OperationFeedback.selectionChanged() }
        .onChange(of: settings.includeMath) { _ in settings.save(); OperationFeedback.selectionChanged() }
        .onChange(of: settings.preserveSymbols) { _ in settings.save(); OperationFeedback.selectionChanged() }
        .onChange(of: settings.preserveLinks) { _ in settings.save(); OperationFeedback.selectionChanged() }
    }

    private var documentCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            GlassSectionTitle(title: l10n.t("خيارات PDF والعروض", "PDF and presentation options"), systemImage: "doc.on.doc")
            Picker(l10n.t("دقة صفحات PDF", "PDF page quality"), selection: $settings.pdfQuality) {
                Text(l10n.t("سريعة", "Fast")).tag(PDFQuality.fast)
                Text(l10n.t("متوازنة", "Balanced")).tag(PDFQuality.balanced)
                Text(l10n.t("عالية", "High")).tag(PDFQuality.accurate)
            }
            .pickerStyle(.menu)
            Toggle(l10n.t("تخطي الصفحات الفارغة", "Skip blank pages"), isOn: $settings.skipBlankPages)
            Toggle(l10n.t("استخدام نص PDF الأصلي عند موثوقيته", "Use embedded PDF text when reliable"), isOn: $settings.preferPDFText)
            VStack(alignment: .leading, spacing: 7) {
                Text(l10n.t("صفحات PDF المطلوبة", "PDF pages"))
                    .font(.subheadline.weight(.semibold))
                TextField(l10n.t("الكل، أو مثال: 1-20، 25", "All, or example: 1-20, 25"), text: $settings.pageSelection)
                    .keyboardType(.numbersAndPunctuation)
                    .padding(BasirSpacing.m)
                    .background(BasirPalette.subtleFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(l10n.t("اتركه فارغًا لمعالجة كل الصفحات.", "Leave blank to process every page."))
                    .font(.footnote)
                    .foregroundStyle(BasirPalette.secondaryText)
            }
            Toggle(l10n.t("إدراج ملاحظات الشرائح", "Include slide notes"), isOn: $settings.includeSpeakerNotes)
            Toggle(l10n.t("إدراج الشرائح المخفية", "Include hidden slides"), isOn: $settings.includeHiddenSlides)
            Picker(l10n.t("تصحيح دوران PDF", "PDF rotation correction"), selection: $settings.rotationCorrection) {
                Text(l10n.t("تلقائي", "Automatic")).tag(0)
                Text("90°").tag(90)
                Text("180°").tag(180)
                Text("270°").tag(270)
            }
            .pickerStyle(.menu)
        }
        .tint(BasirPalette.accent)
        .glassSurface()
        .onChange(of: settings.pdfQuality) { _ in settings.save(); OperationFeedback.selectionChanged() }
        .onChange(of: settings.skipBlankPages) { _ in settings.save(); OperationFeedback.selectionChanged() }
        .onChange(of: settings.preferPDFText) { _ in settings.save(); OperationFeedback.selectionChanged() }
        .onChange(of: settings.pageSelection) { _ in settings.save() }
        .onChange(of: settings.includeSpeakerNotes) { _ in settings.save(); OperationFeedback.selectionChanged() }
        .onChange(of: settings.includeHiddenSlides) { _ in settings.save(); OperationFeedback.selectionChanged() }
        .onChange(of: settings.rotationCorrection) { _ in settings.save(); OperationFeedback.selectionChanged() }
    }
}

/// Version, policies, help, and the welcome tour.
struct AboutBasirView: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var viewModel: AppViewModel
    @AppStorage("onboarding_completed_v3_1") private var onboardingCompleted = true

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: BasirSpacing.l) {
                    BasirHeroCard(title: l10n.t("بصير", "Basir"),
                                  subtitle: l10n.t("الإصدار \(version)", "Version \(version)"),
                                  systemImage: "eye.fill")
                    linksCard(title: l10n.t("القانونية والسياسات", "Legal and policies"), systemImage: "doc.text.fill", links: [
                        DocumentLink(slug: "terms", title: l10n.t("الشروط والأحكام", "Terms and Conditions"), icon: "doc.text"),
                        DocumentLink(slug: "privacy", title: l10n.t("سياسة الخصوصية", "Privacy Policy"), icon: "hand.raised.fill")
                    ])
                    linksCard(title: l10n.t("المساعدة والمعلومات", "Help and information"), systemImage: "questionmark.circle.fill", links: [
                        DocumentLink(slug: "faq", title: l10n.t("الأسئلة المتكررة", "Frequently Asked Questions"), icon: "questionmark.bubble"),
                        DocumentLink(slug: "contact", title: l10n.t("التواصل", "Contact"), icon: "envelope.fill"),
                        DocumentLink(slug: "about", title: l10n.t("عن بصير", "About Basir"), icon: "info.circle.fill")
                    ])
                    InfoCard(
                        title: l10n.t("الخصوصية", "Privacy"),
                        text: l10n.t(
                            "يتصل التطبيق بخادم بصير المشفّر فقط. لا توجد إعلانات أو أدوات تتبع. اختيار النموذج يُرسل كمعرّف نموذج فقط ولا يضيف أي بيانات شخصية.",
                            "The app connects only to the encrypted Basir server. It has no ads or tracking. Model selection sends only a model identifier and adds no personal data."
                        ),
                        systemImage: "hand.raised.fill"
                    )
                    SecondaryActionButton(title: l10n.t("عرض جولة الترحيب مجددًا", "Show the welcome tour again"),
                                          systemImage: "sparkles") {
                        // Close Settings first so the tour can be presented over the app.
                        viewModel.isSettingsPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onboardingCompleted = false }
                    }
                }
                .appScreenContent(bottomPadding: 24)
            }
        }
        .foregroundStyle(BasirPalette.primaryText)
        .navigationTitle(l10n.t("عن بصير", "About Basir"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private struct DocumentLink: Identifiable {
        let slug: String
        let title: String
        let icon: String
        var id: String { slug }
    }

    private func linksCard(title: String, systemImage: String, links: [DocumentLink]) -> some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            GlassSectionTitle(title: title, systemImage: systemImage)
            ForEach(links) { link in
                NavigationLink {
                    ServerPublicDocumentView(slug: link.slug, isArabic: l10n.isArabic)
                } label: {
                    Label(link.title, systemImage: link.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                }
                .tint(BasirPalette.accent)
            }
        }
        .glassSurface()
    }
}


// R21_LEGACY_CI_MARKERS_BEGIN
// basirPublicURL("/legal/terms")
// basirPublicURL("/legal/privacy")
// basirPublicURL("/help/faq")
// basirPublicURL("/contact")
// basirPublicURL("/about")
// R21_LEGACY_CI_MARKERS_END
