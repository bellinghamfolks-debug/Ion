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
                                         detail: l10n.t("النموذج، محتوى Word، خيارات PDF والعروض",
                                                        "Model, Word content, PDF and presentation options"),
                                         systemImage: "slider.horizontal.3") { AdvancedSettingsView() }
                            Divider().padding(.leading, 44)
                            settingsLink(l10n.t("تواصل معنا", "Contact us"),
                                         detail: l10n.t("أرسل سؤالًا أو مشكلة أو اقتراحًا إلى فريق بصير",
                                                        "Send a question, problem, or idea to the Basir team"),
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

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            GlassSectionTitle(title: l10n.t("الخصوصية", "Privacy"), systemImage: "lock.shield.fill")
            Toggle(l10n.t("قفل بصير ببصمة الوجه أو الرمز", "Lock Basir with Face ID or passcode"), isOn: $settings.appLock)
            Toggle(l10n.t("حذف نسخة الخادم فور التنزيل", "Delete the server copy after download"), isOn: $settings.deleteServerCopy)
            Text(l10n.t("مع القفل يطلب بصير بصمة الوجه أو رمز الجهاز كلما عدت إليه. ومع الحذف تُمسح نسخة الملف ونتيجته من الخادم بمجرد وصول ملف Word إلى هاتفك؛ النتائج الجزئية تبقى حتى تعيد محاولة صفحاتها. ولإخفاء أرقام الهوية والحسابات أثناء القراءة استخدم قائمة «بصير» في القارئ.",
                        "With the lock, Basir asks for Face ID or your passcode whenever you return. With deletion, the file and its result are removed from the server as soon as the Word file reaches your phone; partial results stay until you retry their pages. To hide ID and account numbers while reading, use the Basir menu in the reader."))
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
                            "يتصل التطبيق بخادم بصير المشفّر فقط. لا توجد إعلانات أو أدوات تتبع. لا يُستخدم ملفك لتدريب نموذج خاص ببصير. احتفظ دائمًا بنسختك الأصلية؛ بصير ليس أرشيفًا.",
                            "The app connects only to the encrypted Basir server. It has no ads or tracking. Your file is not used to train a Basir-specific model. Always keep your original; Basir is not an archive."
                        ),
                        systemImage: "hand.raised.fill"
                    )
                    legalCard
                    helpCard
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

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            GlassSectionTitle(title: l10n.t("ما هو بصير؟", "What is Basir?"), systemImage: "eye")
            Text(l10n.t(
                "بصير يحوّل المستندات التي يصعب قراءتها إلى ملفات Word مرتبة يسهل التنقل فيها بقارئ الشاشة: عناوين حقيقية، وجداول قابلة للتنقل، وصور موصوفة بالنص. صُمم أولًا للمكفوفين وضعاف البصر، ويفيد كل من يحتاج نصًا واضحًا من ملف مصوّر.",
                "Basir turns hard-to-read documents into well-structured Word files that are easy to navigate with a screen reader: real headings, navigable tables, and images described in text. It is designed first for blind and low-vision readers, and helps anyone who needs clear text from a scanned file."
            ))
            .font(.body)
            .foregroundStyle(BasirPalette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .glassSurface()
    }

    private var featuresCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            GlassSectionTitle(title: l10n.t("ماذا يستطيع؟", "What can it do?"), systemImage: "checklist")
            feature("doc.richtext", l10n.t("تحويل PDF والصور والعروض إلى Word.", "Convert PDFs, images, and presentations to Word."))
            feature("waveform", l10n.t("تفريغ التسجيلات الصوتية، بما فيها الطويلة، إلى نص مكتوب.", "Transcribe audio recordings, including long ones, into written text."))
            feature("character.book.closed", l10n.t("ترجمة المستندات إلى 15 لغة.", "Translate documents into 15 languages."))
            feature("text.below.photo", l10n.t("وصف الصور والشعارات والرسوم داخل الملف.", "Describe images, logos, and charts inside the file."))
            feature("checkmark.shield", l10n.t("التحقق من كل نتيجة قبل حفظها، مع تقرير بلغة بسيطة.", "Verify every result before saving it, with a plain-language report."))
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
            GlassSectionTitle(title: l10n.t("القانونية والسياسات", "Legal and policies"), systemImage: "doc.text.fill")
            externalLink(l10n.t("الشروط والأحكام", "Terms and Conditions"), icon: "doc.text", path: "/legal/terms")
            externalLink(l10n.t("سياسة الخصوصية", "Privacy Policy"), icon: "hand.raised", path: "/legal/privacy")
        }
        .glassSurface()
    }

    /// Help pages stay inside the app.
    private var helpCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            GlassSectionTitle(title: l10n.t("المساعدة والتواصل", "Help and contact"), systemImage: "questionmark.circle.fill")
            internalLink(l10n.t("الأسئلة المتكررة", "Frequently Asked Questions"), icon: "questionmark.bubble", slug: "faq")
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
