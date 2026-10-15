import SwiftUI

/// Settings › Translation. Every choice here is sent with each translation
/// task and changes the translated file (see TranslationPreferences).
struct TranslationSettingsView: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @State private var confirmingReset = false

    private var prefs: Binding<TranslationPreferences> {
        Binding(get: { settings.translation }, set: { settings.translation = $0; settings.save() })
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: BasirSpacing.l) {
                    Text(l10n.t("اختر لغة الترجمة وأسلوبها، وحدّد طريقة كتابة الأسماء والمصطلحات. تُحفظ اختياراتك للترجمات القادمة.",
                                "Choose the translation language, writing style, and how names and terms should appear. Your choices are saved for future translations."))
                        .font(.footnote)
                        .foregroundStyle(BasirPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    languagesCard
                    styleCard
                    contentCard
                    glossaryCard
                    Button(role: .destructive) {
                        confirmingReset = true
                    } label: {
                        Label(l10n.t("استعادة الإعدادات الافتراضية", "Reset translation settings"),
                              systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(settings.translation == .standard)
                }
                .appScreenContent(bottomPadding: 24)
            }
        }
        .foregroundStyle(BasirPalette.primaryText)
        .navigationTitle(l10n.t("الترجمة", "Translation"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(l10n.t("استعادة إعدادات الترجمة الافتراضية وحذف جميع مصطلحات قاموسك؟", "Reset every translation option and clear the glossary?"),
                            isPresented: $confirmingReset, titleVisibility: .visible) {
            Button(l10n.t("إعادة الضبط", "Reset"), role: .destructive) {
                prefs.wrappedValue = .standard
                UIAccessibility.post(notification: .announcement,
                                     argument: l10n.t("تمت استعادة إعدادات الترجمة الافتراضية.", "Translation settings reset."))
            }
        }
    }

    // MARK: Languages

    private var languagesCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            GlassSectionTitle(title: l10n.t("اللغات", "Languages"), systemImage: "character.bubble")
            picker(l10n.t("الترجمة إلى", "Translate into"),
                   selection: Binding(get: { settings.targetLanguageCode },
                                      set: { settings.targetLanguageCode = $0; settings.save() })) {
                ForEach(SupportedLanguage.all) { Text($0.name(interface: l10n.language)).tag($0.code) }
            }
            picker(l10n.t("لغة المستند", "Document language"), selection: prefs.sourceLanguage) {
                Text(l10n.t("اكتشاف تلقائي", "Detect automatically")).tag("")
                ForEach(SupportedLanguage.all) { Text($0.name(interface: l10n.language)).tag($0.code) }
            }
            note(prefs.wrappedValue.sourceLanguage.isEmpty
                 ? l10n.t("يكتشف بصير لغة المستند تلقائيًا. إذا احتوى على أكثر من لغة، يمكنك تحديد اللغة التي تريد ترجمتها. يبقى النص المكتوب بلغة الترجمة كما هو.",
                          "Basir detects the document's language. Set it when the document mixes two languages and you want only one translated; text already in the target language stays as it is.")
                 : l10n.t("يترجم بصير النص المكتوب باللغة المحددة. يبقى النص المكتوب بلغة الترجمة كما هو.",
                          "Text in this language is translated; text already in the target language stays as it is."))
        }
        .glassSurface()
    }

    // MARK: Style

    private var styleCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            GlassSectionTitle(title: l10n.t("أسلوب الترجمة", "Translation style"), systemImage: "text.quote")
            picker(l10n.t("الأسلوب", "Style"), selection: prefs.style) {
                Text(l10n.t("قريب من الأصل", "Close to the original")).tag(TranslationPreferences.Style.faithful)
                Text(l10n.t("سلس", "Natural")).tag(TranslationPreferences.Style.natural)
                Text(l10n.t("مبسّط", "Plain language")).tag(TranslationPreferences.Style.plain)
            }
            note(styleNote)
            picker(l10n.t("درجة الرسمية", "Formality"), selection: prefs.formality) {
                Text(l10n.t("رسمي", "Formal")).tag(TranslationPreferences.Formality.formal)
                Text(l10n.t("غير متكلّف", "Everyday")).tag(TranslationPreferences.Formality.neutral)
            }
            note(prefs.wrappedValue.formality == .formal
                 ? l10n.t("لغة رسمية تناسب الخطابات والوثائق، مع استخدام صيغ المخاطبة الرسمية عند توفرها في لغة الترجمة.",
                          "Formal wording for letters and documents, using formal forms of address where available.")
                 : l10n.t("لغة واضحة تناسب الاستخدام اليومي، مع صيغ مخاطبة غير رسمية. تبقى الترجمة العربية بالفصحى.",
                          "Clear, everyday wording with informal forms of address. Arabic translations still use Modern Standard Arabic."))
            Toggle(l10n.t("ملاحظات المترجم", "Translator's notes"), isOn: prefs.notes)
            note(prefs.wrappedValue.notes
                 ? l10n.t("يطلب من المترجم توضيح المصطلحات الثقافية والتاريخية والدينية التي قد تحتاج إلى شرح. تظهر التوضيحات بين معقوفين بعنوان «ملاحظة المترجم».",
                          "Adds a short explanation in square brackets after a cultural, historical or religious term that might be unclear, starting with “Translator's note”.")
                 : l10n.t("ترجمة دون ملاحظات توضيحية إضافية.", "Adds no explanation that is not in the original."))
        }
        .glassSurface()
    }

    private var styleNote: String {
        switch prefs.wrappedValue.style {
        case .faithful:
            return l10n.t("يحافظ قدر الإمكان على ألفاظ النص وترتيب جمله. يناسب الوثائق الرسمية والنصوص التي تهم فيها دقة الصياغة.",
                          "Keeps the original wording and sentence order where possible. Suits official documents and texts where precise wording matters.")
        case .natural:
            return l10n.t("يعيد صياغة الجمل لتبدو طبيعية في لغة الترجمة، مع الحفاظ على المعنى والتفاصيل.",
                          "Restructures sentences to sound natural in the target language while preserving the meaning and details.")
        case .plain:
            return l10n.t("يستخدم جملًا قصيرة وكلمات مألوفة، ويوضح المصطلحات الصعبة مع الحفاظ على تفاصيل النص.",
                          "Uses short sentences and familiar words, explaining difficult terms while preserving the details.")
        }
    }

    // MARK: What stays as it is

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            GlassSectionTitle(title: l10n.t("الأسماء والمصطلحات والأرقام", "Names, terms and numbers"), systemImage: "textformat.abc")
            picker(l10n.t("أسماء الأشخاص والجهات", "Names of people and organisations"), selection: prefs.names) {
                Text(l10n.t("الاحتفاظ بالحروف الأصلية", "Keep in the original script")).tag(TranslationPreferences.Names.keep)
                Text(l10n.t("كتابتها بحروف لغة الترجمة", "Write in the target script")).tag(TranslationPreferences.Names.targetScript)
            }
            picker(l10n.t("المصطلحات التقنية", "Technical terms"), selection: prefs.terms) {
                Text(l10n.t("ترجمتها", "Translate")).tag(TranslationPreferences.Terms.translate)
                Text(l10n.t("الترجمة مع المصطلح الأصلي بين قوسين", "Translate, original in parentheses")).tag(TranslationPreferences.Terms.translateWithOriginal)
                Text(l10n.t("الاحتفاظ باللغة الأصلية", "Keep in the original language")).tag(TranslationPreferences.Terms.keep)
            }
            picker(l10n.t("الاقتباسات والشعر والنصوص الدينية", "Quotations, poetry and religious texts"), selection: prefs.quotations) {
                Text(l10n.t("الاحتفاظ بالنص الأصلي", "Keep the original text")).tag(TranslationPreferences.Quotations.keep)
                Text(l10n.t("النص الأصلي ثم ترجمة معناه", "Original, then its translated meaning")).tag(TranslationPreferences.Quotations.keepWithMeaning)
                Text(l10n.t("ترجمتها ضمن النص", "Translate with the rest")).tag(TranslationPreferences.Quotations.translate)
            }
            picker(l10n.t("الأرقام", "Digits"), selection: prefs.numerals) {
                Text(l10n.t("كما في الأصل", "As in the original")).tag(TranslationPreferences.Numerals.source)
                Text(l10n.t("أرقام 0123", "Digits 0123")).tag(TranslationPreferences.Numerals.western)
                Text(l10n.t("أرقام ٠١٢٣", "Digits ٠١٢٣")).tag(TranslationPreferences.Numerals.eastern)
            }
            note(l10n.t("يحدد هذا الخيار شكل الأرقام في الملف المترجم. لا تتغير الأرقام داخل الروابط أو الرموز التي تحتوي على حروف لاتينية، مثل A320.",
                        "Choose how numbers appear in the translated file. Numbers in links or codes containing Latin letters, such as A320, stay unchanged."))
            picker(l10n.t("النص داخل الصور", "Text inside pictures"), selection: prefs.imageText) {
                Text(l10n.t("ترجمته ضمن وصف الصورة", "Translate in the description")).tag(TranslationPreferences.ImageText.translate)
                Text(l10n.t("نقله بلغته الأصلية", "Quote in its original language")).tag(TranslationPreferences.ImageText.keep)
            }
        }
        .glassSurface()
    }

    // MARK: Glossary

    private var glossaryCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            GlassSectionTitle(title: l10n.t("قاموسك الخاص", "Your glossary"), systemImage: "book.closed")
            note(l10n.t("أضف المصطلحات والترجمة التي تفضّلها لكل منها ليستخدمها بصير في مستنداتك. يمكنك إضافة حتى \(TranslationPreferences.maximumGlossary) مصطلحًا.",
                        "Add terms and your preferred translation for each one. Basir uses these in your documents. You can add up to \(TranslationPreferences.maximumGlossary) terms."))
            ForEach(Array(prefs.wrappedValue.glossary.enumerated()), id: \.element.id) { index, entry in
                VStack(alignment: .leading, spacing: BasirSpacing.s) {
                    TextField(l10n.t("المصطلح الأصلي", "Original term"), text: glossaryBinding(entry.id, \.source))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(BasirSpacing.s)
                        .background(BasirPalette.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel(l10n.t("المصطلح \(index + 1) في الأصل", "Term \(index + 1) in the original"))
                    TextField(l10n.t("الترجمة المفضّلة", "Preferred translation"), text: glossaryBinding(entry.id, \.target))
                        .autocorrectionDisabled()
                        .padding(BasirSpacing.s)
                        .background(BasirPalette.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel(l10n.t("ترجمة المصطلح \(index + 1)", "Translation of term \(index + 1)"))
                    Button(role: .destructive) {
                        prefs.wrappedValue.glossary.removeAll { $0.id == entry.id }
                    } label: {
                        Label(l10n.t("حذف المصطلح \(index + 1)", "Delete term \(index + 1)"), systemImage: "trash")
                            .font(.footnote)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, BasirSpacing.xs)
                Divider()
            }
            Button {
                prefs.wrappedValue.glossary.append(.init(source: "", target: ""))
                UIAccessibility.post(notification: .announcement,
                                     argument: l10n.t("تمت إضافة خانة لمصطلح جديد في نهاية القائمة.", "A new term was added at the end of the list."))
            } label: {
                Label(l10n.t("إضافة مصطلح", "Add a term"), systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)
            .disabled(prefs.wrappedValue.glossary.count >= TranslationPreferences.maximumGlossary)
        }
        .glassSurface()
    }

    private func glossaryBinding(_ id: UUID, _ path: WritableKeyPath<TranslationPreferences.GlossaryEntry, String>) -> Binding<String> {
        Binding(
            get: { prefs.wrappedValue.glossary.first(where: { $0.id == id })?[keyPath: path] ?? "" },
            set: { value in
                guard let index = prefs.wrappedValue.glossary.firstIndex(where: { $0.id == id }) else { return }
                prefs.wrappedValue.glossary[index][keyPath: path] = String(value.prefix(TranslationPreferences.maximumTermLength))
            }
        )
    }

    // MARK: Pieces

    private func picker<Value: Hashable, Content: View>(_ title: String, selection: Binding<Value>,
                                                         @ViewBuilder content: () -> Content) -> some View {
        Picker(title, selection: selection, content: content)
            .pickerStyle(.menu)
            .tint(BasirPalette.accent)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(BasirPalette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension TranslationPreferences {
    /// One line for the translate screen: what differs from the defaults.
    @MainActor
    func summary(_ l10n: L10n) -> String {
        var parts: [String] = []
        switch style {
        case .faithful: break
        case .natural: parts.append(l10n.t("أسلوب سلس", "natural style"))
        case .plain: parts.append(l10n.t("لغة مبسّطة", "plain language"))
        }
        if formality == .neutral { parts.append(l10n.t("أسلوب غير متكلّف", "everyday register")) }
        if names == .targetScript { parts.append(l10n.t("الأسماء بحروف لغة الترجمة", "names in target script")) }
        if terms == .translateWithOriginal { parts.append(l10n.t("المصطلحات مع نصها الأصلي", "terms with originals")) }
        if terms == .keep { parts.append(l10n.t("المصطلحات بلغتها الأصلية", "terms kept")) }
        if quotations == .keepWithMeaning { parts.append(l10n.t("الاقتباسات مع معناها", "quotations with meaning")) }
        if quotations == .translate { parts.append(l10n.t("الاقتباسات مترجمة", "quotations translated")) }
        if numerals == .western { parts.append(l10n.t("أرقام 0123", "digits 0123")) }
        if numerals == .eastern { parts.append(l10n.t("أرقام ٠١٢٣", "digits ٠١٢٣")) }
        if notes { parts.append(l10n.t("ملاحظات المترجم", "translator's notes")) }
        if imageText == .keep { parts.append(l10n.t("نص الصور بلغته الأصلية", "picture text kept")) }
        let terms = usableGlossary.count
        if terms > 0 { parts.append(l10n.t("قاموس: \(terms)", "glossary: \(terms)")) }
        return parts.isEmpty
            ? l10n.t("الإعدادات الافتراضية: أسلوب رسمي قريب من الأصل.", "Default settings: faithful, formal translation.")
            : parts.joined(separator: l10n.isArabic ? "، " : ", ")
    }
}
