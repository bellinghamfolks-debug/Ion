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
                        privacyCard
                        SectionHeading(title: l10n.t("المزيد", "More"))
                        VStack(spacing: 0) {
                            settingsLink(l10n.t("خيارات متقدمة", "Advanced options"),
                                         detail: l10n.t("محتوى الملفات وجودة التحويل ونموذج المعالجة",
                                                        "File content, conversion quality, and AI model"),
                                         systemImage: "slider.horizontal.3") { AdvancedSettingsView() }
                            Divider().padding(.leading, 44)
                            settingsLink(l10n.t("تواصل معنا", "Contact us"),
                                         detail: l10n.t("للاستفسارات والملاحظات والاقتراحات",
                                                        "Questions, feedback, and suggestions"),
                                         systemImage: "envelope") { ContactFormView() }
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
                        Text(l10n.t("تمييز أوضح بين النص والخلفية، وحدود أكثر وضوحًا.", "Clearer contrast between text and backgrounds, with more visible borders."))
                            .font(.footnote)
                            .foregroundStyle(BasirPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(BasirPalette.accent)
            } else {
                Text(l10n.t("لتوضيح النص والحدود، فعّل «زيادة التباين» من إعدادات تسهيلات الاستخدام في iPhone.",
                            "For clearer text and borders, turn on Increase Contrast in your iPhone’s Accessibility settings."))
                    .font(.footnote)
                    .foregroundStyle(BasirPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .glassSurface()
    }

    private var networkCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            GlassSectionTitle(title: l10n.t("الاتصال واستئناف المهام", "Connection and task resumption"), systemImage: "wifi")
            Toggle(l10n.t("رفع الملفات عبر Wi‑Fi فقط", "Upload only on Wi-Fi"), isOn: $settings.wifiOnly)
            Toggle(l10n.t("السماح بالمعالجة في وضع البيانات المنخفضة", "Allow processing in Low Data Mode"), isOn: $settings.allowLowData)
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

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            GlassSectionTitle(title: l10n.t("الخصوصية", "Privacy"), systemImage: "lock.shield.fill")
            Toggle(l10n.t("قفل بصير ببصمة الوجه أو رمز الدخول", "Lock Basir with Face ID or passcode"), isOn: $settings.appLock)
            Toggle(l10n.t("حذف الملفات من الخادم بعد التنزيل", "Delete files from the server after download"), isOn: $settings.deleteServerCopy)
            Text(l10n.t("عند تفعيل القفل، يلزم التحقق من هويتك كلما عدت إلى بصير.\n\nعند تفعيل الحذف، تُحذف نسخة الملف ونتيجته من الخادم بعد تنزيل النتيجة المكتملة. تبقى النتائج الجزئية لإتاحة إعادة محاولة الصفحات.\n\nلإخفاء أرقام الهوية والحسابات أثناء القراءة، افتح قائمة «خيارات القراءة» في القارئ.",
                        "With app lock on, you’ll need to verify your identity each time you return to Basir.\n\nWith deletion on, the source file and result are removed from the server after the completed result downloads. Partial results are kept so you can retry pages.\n\nTo hide ID and account numbers while reading, open Reading options in the reader."))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(BasirPalette.accent)
        .glassSurface()
        .onChange(of: settings.appLock) { enabled in
            OperationFeedback.selectionChanged()
            if enabled { AppLock.confirmCanLock(settings: settings, l10n: l10n) }
        }
        .onChange(of: settings.deleteServerCopy) { _ in OperationFeedback.selectionChanged() }
    }

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            GlassSectionTitle(title: l10n.t("الأصوات والإشعارات", "Sounds and notifications"), systemImage: "speaker.wave.2.fill")
            Picker(l10n.t("تنبيهات المهام", "Task feedback"), selection: $settings.soundTheme) {
                Text(l10n.t("بلا صوت أو اهتزاز", "No sound or haptics")).tag(SoundTheme.off)
                Text(l10n.t("هادئ", "Gentle")).tag(SoundTheme.gentle)
                Text(l10n.t("واضح", "Clear")).tag(SoundTheme.clear)
                Text(l10n.t("اهتزاز فقط", "Haptics only")).tag(SoundTheme.tactile)
            }
            .pickerStyle(.menu)
            .tint(BasirPalette.accent)
            Toggle(l10n.t("إشعار عند اكتمال المهمة", "Notify when a task completes"), isOn: $settings.notificationsEnabled)
                .onChange(of: settings.notificationsEnabled) { enabled in
                    settings.save()
                    if enabled {
                        Task {
                            if await OperationFeedback.requestNotificationPermission() {
                                PushRegistrar.shared.registerForRemoteNotifications()
                            }
                        }
                    }
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
            Toggle(l10n.t("الاحتفاظ بالرموز ومعانيها", "Keep symbols and their meanings"), isOn: $settings.preserveSymbols)
            Toggle(l10n.t("الاحتفاظ بالروابط", "Keep links"), isOn: $settings.preserveLinks)
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
            Picker(l10n.t("جودة معالجة PDF", "PDF processing quality"), selection: $settings.pdfQuality) {
                Text(l10n.t("سريعة", "Fast")).tag(PDFQuality.fast)
                Text(l10n.t("متوازنة", "Balanced")).tag(PDFQuality.balanced)
                Text(l10n.t("عالية", "High")).tag(PDFQuality.accurate)
            }
            .pickerStyle(.menu)
            Toggle(l10n.t("تخطي الصفحات الفارغة", "Skip blank pages"), isOn: $settings.skipBlankPages)
            Toggle(l10n.t("استخدام النص الأصلي في PDF متى كان موثوقًا", "Use the PDF’s original text when reliable"), isOn: $settings.preferPDFText)
            VStack(alignment: .leading, spacing: 7) {
                Text(l10n.t("صفحات PDF المطلوبة", "PDF pages"))
                    .font(.subheadline.weight(.semibold))
                TextField(l10n.t("مثل: 1-20، 25", "For example: 1-20, 25"), text: $settings.pageSelection)
                    .keyboardType(.numbersAndPunctuation)
                    .padding(BasirSpacing.m)
                    .background(BasirPalette.subtleFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(l10n.t("اتركه فارغًا لمعالجة كل الصفحات.", "Leave blank to process every page."))
                    .font(.footnote)
                    .foregroundStyle(BasirPalette.secondaryText)
            }
            Toggle(l10n.t("إدراج ملاحظات الشرائح", "Include slide notes"), isOn: $settings.includeSpeakerNotes)
            Toggle(l10n.t("إدراج الشرائح المخفية", "Include hidden slides"), isOn: $settings.includeHiddenSlides)
            Picker(l10n.t("تدوير صفحات PDF", "PDF page rotation"), selection: $settings.rotationCorrection) {
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

/// Public website addresses. Terms and the privacy policy are legal
/// documents, so they open on the website (always the current version);
/// help pages stay inside the app.
enum BasirPublicLinks {
    static func url(_ path: String, isArabic: Bool) -> URL? {
        guard let base = BundledServerConfiguration.current().secureBaseURL,
              var components = URLComponents(url: base.appendingPathComponent(path),
                                             resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "lang", value: isArabic ? "ar" : "en")]
        return components.url
    }
    static func endpoint(_ path: String) -> URL? {
        BundledServerConfiguration.current().secureBaseURL?.appendingPathComponent(path)
    }
}

/// Native About screen: what Basir does, version, links, and the tour.
struct AboutBasirView: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.openURL) private var openURL
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
                    aboutCard
                    featuresCard
                    InfoCard(
                        title: l10n.t("الخصوصية", "Privacy"),
                        text: l10n.t(
                            "يستخدم بصير اتصالًا مشفّرًا بخادمه، ولا يتضمن إعلانات أو أدوات تتبع. لا تُستخدم ملفاتك لتدريب نموذج خاص ببصير. احتفظ بنسخك الأصلية في مكان آمن.",
                            "Basir uses an encrypted connection to its server, with no ads or tracking. Your files are not used to train a Basir-specific model. Keep your original files in a safe place."
                        ),
                        systemImage: "hand.raised.fill"
                    )
                    legalCard
                    helpCard
                    SecondaryActionButton(title: l10n.t("إعادة عرض جولة الترحيب", "Show welcome tour"),
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

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            GlassSectionTitle(title: l10n.t("ما هو بصير؟", "What is Basir?"), systemImage: "eye")
            Text(l10n.t(
                "بصير يساعدك على قراءة المستندات المصوّرة وتحويلها إلى ملفات Word منظمة، بعناوين وجداول يسهل التنقل بينها، وأوصاف نصية للصور. صُمم مع الاهتمام باحتياجات المكفوفين وضعاف البصر واستخدام قارئات الشاشة.",
                "Basir helps you read scanned documents by turning them into structured Word files, with headings, navigable tables, and text descriptions of images. It is designed with blind and low-vision readers and screen reader use in mind."
            ))
            .font(.body)
            .foregroundStyle(BasirPalette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .glassSurface()
    }

    private var featuresCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            GlassSectionTitle(title: l10n.t("مزايا بصير", "What you can do with Basir"), systemImage: "checklist")
            feature("doc.richtext", l10n.t("تحويل PDF والصور والعروض إلى Word.", "Convert PDFs, images, and presentations to Word."))
            feature("waveform", l10n.t("تحويل التسجيلات الصوتية إلى نص مكتوب.", "Transcribe audio recordings into text."))
            feature("character.book.closed", l10n.t("ترجمة المستندات إلى 15 لغة.", "Translate documents into 15 languages."))
            feature("text.below.photo", l10n.t("وصف الصور والشعارات والرسوم داخل الملف.", "Describe images, logos, and charts inside the file."))
            feature("checkmark.shield", l10n.t("فحص النتائج قبل حفظها، مع تقرير يوضح ما يحتاج إلى مراجعة.", "Check results before saving, with a report showing any points to review."))
        }
        .glassSurface()
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: BasirSpacing.m) {
            Image(systemName: icon)
                .foregroundStyle(BasirPalette.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// Terms and privacy open on the website in Safari.
    private var legalCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            GlassSectionTitle(title: l10n.t("الشروط والخصوصية", "Terms and privacy"), systemImage: "doc.text.fill")
            externalLink(l10n.t("الشروط والأحكام", "Terms and Conditions"), icon: "doc.text", path: "/legal/terms")
            externalLink(l10n.t("سياسة الخصوصية", "Privacy Policy"), icon: "hand.raised", path: "/legal/privacy")
        }
        .glassSurface()
    }

    /// Help pages stay inside the app.
    private var helpCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            GlassSectionTitle(title: l10n.t("المساعدة والتواصل", "Help and contact"), systemImage: "questionmark.circle.fill")
            internalLink(l10n.t("الأسئلة الشائعة", "Frequently Asked Questions"), icon: "questionmark.bubble", slug: "faq")
            NavigationLink {
                ContactFormView()
            } label: {
                Label(l10n.t("تواصل معنا", "Contact us"), systemImage: "envelope")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
            }
            .tint(BasirPalette.accent)
        }
        .glassSurface()
    }

    private func externalLink(_ title: String, icon: String, path: String) -> some View {
        Button {
            if let url = BasirPublicLinks.url(path, isArabic: l10n.isArabic) { openURL(url) }
        } label: {
            HStack(spacing: BasirSpacing.m) {
                Label(title, systemImage: icon)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward.square")
                    .foregroundStyle(BasirPalette.tertiaryText)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .tint(BasirPalette.accent)
        .accessibilityHint(l10n.t("يفتح في Safari", "Opens in Safari"))
    }

    private func internalLink(_ title: String, icon: String, slug: String) -> some View {
        NavigationLink {
            ServerPublicDocumentView(slug: slug, isArabic: l10n.isArabic)
        } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
        }
        .tint(BasirPalette.accent)
    }
}


// R21_LEGACY_CI_MARKERS_BEGIN
// basirPublicURL("/legal/terms")
// basirPublicURL("/legal/privacy")
// basirPublicURL("/help/faq")
// basirPublicURL("/contact")
// basirPublicURL("/about")
// R21_LEGACY_CI_MARKERS_END
