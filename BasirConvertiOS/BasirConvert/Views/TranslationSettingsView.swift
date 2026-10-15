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
                    Text(l10n.t("كل خيار هنا يُرسل مع كل مهمة ترجمة ويغيّر الملف المترجم فعلًا. القيم الافتراضية تُبقي الترجمة كما كانت.",
                                "Every choice here is sent with each translation task and really changes the translated file. The defaults keep translation as it was."))
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
                        Label(l10n.t("إعادة إعدادات الترجمة الافتراضية", "Reset translation settings"),
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
        .confirmationDialog(l10n.t("إعادة كل خيارات الترجمة وحذف القاموس؟", "Reset every translation option and clear the glossary?"),
                            isPresented: $confirmingReset, titleVisibility: .visible) {
            Button(l10n.t("إعادة الضبط", "Reset"), role: .destructive) {
                prefs.wrappedValue = .standard
                UIAccessibility.post(notification: .announcement,
                                     argument: l10n.t("أُعيدت إعدادات الترجمة الافتراضية.", "Translation settings reset."))
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
            picker(l10n.t("لغة المستند الأصلية", "Language of the original"), selection: prefs.sourceLanguage) {
                Text(l10n.t("اكتشاف تلقائي", "Detect automatically")).tag("")
                ForEach(SupportedLanguage.all) { Text($0.name(interface: l10n.language)).tag($0.code) }
            }
            note(prefs.wrappedValue.sourceLanguage.isEmpty
                 ? l10n.t("يتعرّف بصير على لغة المستند وحده. حدّدها إذا كان المستند يخلط لغتين وتريد ترجمة إحداهما فقط؛ النص المكتوب أصلًا بلغة الترجمة يبقى كما هو.",
                          "Basir detects the document's language. Set it when the document mixes two languages and you want only one translated; text already in the target language stays as it is.")
                 : l10n.t("يُترجم النص المكتوب بهذه اللغة، ويبقى ما هو مكتوب أصلًا بلغة الترجمة كما هو.",
                          "Text in this language is translated; text already in the target language stays as it is."))
        }
        .glassSurface()
    }

    // MARK: Style

    private var styleCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            GlassSectionTitle(title: l10n.t("أسلوب الترجمة", "Translation style"), systemImage: "text.quote")
            picker(l10n.t("الأسلوب", "Style"), selection: prefs.style) {
                Text(l10n.t("أمين (قريب من الأصل)", "Faithful (close to the original)")).tag(TranslationPreferences.Style.faithful)
                Text(l10n.t("طبيعي (بلغة سلسة)", "Natural (fluent)")).tag(TranslationPreferences.Style.natural)
                Text(l10n.t("مبسّط (لغة سهلة)", "Plain language")).tag(TranslationPreferences.Style.plain)
            }
            note(styleNote)
            picker(l10n.t("مستوى اللغة", "Register"), selection: prefs.formality) {
                Text(l10n.t("رسمي", "Formal")).tag(TranslationPreferences.Formality.formal)
                Text(l10n.t("محايد يومي", "Neutral, everyday")).tag(TranslationPreferences.Formality.neutral)
            }
            note(prefs.wrappedValue.formality == .formal
                 ? l10n.t("فصحى رسمية، وصيغ المخاطبة الرسمية في اللغات التي تفرّق بينها (مثل vous وSie).",
                          "Formal register, and formal address where the language distinguishes it (vous, Sie).")
                 : l10n.t("فصحى معاصرة واضحة بلا عبارات متكلّفة، وصيغ المخاطبة غير الرسمية حيث تفرّق اللغة.",
                          "Clear contemporary wording without ornate phrasing, and informal address where the language distinguishes it."))
            Toggle(l10n.t("ملاحظات المترجم", "Translator's notes"), isOn: prefs.notes)
            note(prefs.wrappedValue.notes
                 ? l10n.t("يضيف شرحًا قصيرًا بين معقوفين بعد كل مصطلح ثقافي أو تاريخي أو ديني قد يغمض على القارئ، يبدأ بـ«ملاحظة المترجم».",
                          "Adds a short explanation in square brackets after a cultural, historical or religious term that might be unclear, starting with “Translator's note”.")
                 : l10n.t("لا يضيف أي شرح ليس في الأصل.", "Adds no explanation that is not in the original."))
        }
        .glassSurface()
    }

    private var styleNote: String {
        switch prefs.wrappedValue.style {
        case .faithful:
            return l10n.t("يلتزم بألفاظ الأصل وترتيب جمله قدر ما تسمح به اللغة. مناسب للعقود والوثائق الرسمية والنصوص الدقيقة.",
                          "Stays close to the original wording and sentence order. Suits contracts, official documents and precise texts.")
        case .natural:
            return l10n.t("يكتب بلغة سلسة كأنها كُتبت أصلًا بلغة الترجمة، ويعيد بناء الجمل عند الحاجة دون أن يُسقط معلومة.",
                          "Reads as if written in the target language, restructuring sentences where needed without dropping any fact.")
        case .plain:
            return l10n.t("جمل قصيرة وكلمات شائعة وشرح مختصر للمصطلحات، مع الحفاظ على كل معلومة واسم ورقم وخطوة.",
                          "Short sentences, common words and brief explanations of jargon, keeping every fact, name, number and step.")
        }
    }

    // MARK: What stays as it is

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            GlassSectionTitle(title: l10n.t("الأسماء والمصطلحات والأرقام", "Names, terms and numbers"), systemImage: "textformat.abc")
            picker(l10n.t("أسماء الأعلام والجهات", "Names of people and organisations"), selection: prefs.names) {
                Text(l10n.t("تبقى بحروفها الأصلية", "Keep in the original script")).tag(TranslationPreferences.Names.keep)
                Text(l10n.t("تُكتب بحروف لغة الترجمة", "Write in the target script")).tag(TranslationPreferences.Names.targetScript)
            }
            picker(l10n.t("المصطلحات التقنية", "Technical terms"), selection: prefs.terms) {
                Text(l10n.t("تُترجم", "Translate")).tag(TranslationPreferences.Terms.translate)
                Text(l10n.t("تُترجم مع الأصل بين قوسين", "Translate, original in parentheses")).tag(TranslationPreferences.Terms.translateWithOriginal)
                Text(l10n.t("تبقى بلغتها الأصلية", "Keep in the original language")).tag(TranslationPreferences.Terms.keep)
            }
            picker(l10n.t("الاقتباسات والشعر والنصوص الدينية", "Quotations, poetry and religious texts"), selection: prefs.quotations) {
                Text(l10n.t("تبقى بنصها الأصلي", "Keep the original text")).tag(TranslationPreferences.Quotations.keep)
                Text(l10n.t("النص الأصلي ثم ترجمة معناه", "Original, then its translated meaning")).tag(TranslationPreferences.Quotations.keepWithMeaning)
                Text(l10n.t("تُترجم مع باقي النص", "Translate with the rest")).tag(TranslationPreferences.Quotations.translate)
            }
            picker(l10n.t("الأرقام", "Digits"), selection: prefs.numerals) {
                Text(l10n.t("كما في الأصل", "As in the original")).tag(TranslationPreferences.Numerals.source)
                Text(l10n.t("أرقام 0123", "Digits 0123")).tag(TranslationPreferences.Numerals.western)
                Text(l10n.t("أرقام ٠١٢٣", "Digits ٠١٢٣")).tag(TranslationPreferences.Numerals.eastern)
            }
            note(l10n.t("يُطبَّق اختيار الأرقام على الملف بعد الترجمة أيضًا، ما عدا الروابط والرموز المختلطة بحروف لاتينية مثل A320.",
                        "The digit choice is also applied to the file after translation, except in links and codes mixed with Latin letters such as A320."))
            picker(l10n.t("النص داخل الصور", "Text inside pictures"), selection: prefs.imageText) {
                Text(l10n.t("يُترجم في وصف الصورة", "Translate in the description")).tag(TranslationPreferences.ImageText.translate)
                Text(l10n.t("يُنقل بلغته الأصلية", "Quote in its original language")).tag(TranslationPreferences.ImageText.keep)
            }
        }
        .glassSurface()
    }

    // MARK: Glossary

    private var glossaryCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            GlassSectionTitle(title: l10n.t("قاموسك الخاص", "Your glossary"), systemImage: "book.closed")
            note(l10n.t("مصطلحات تريد ترجمتها دائمًا بطريقتك. يلتزم بها بصير في الترجمة، ويستبدل أي مصطلح منها بقي دون ترجمة في الملف. حتى \(TranslationPreferences.maximumGlossary) مصطلحًا.",
                        "Terms you always want translated your way. Basir follows them when translating, and replaces any that stayed untranslated in the file. Up to \(TranslationPreferences.maximumGlossary) terms."))
            ForEach(Array(prefs.wrappedValue.glossary.enumerated()), id: \.element.id) { index, entry in
                VStack(alignment: .leading, spacing: BasirSpacing.s) {
                    TextField(l10n.t("المصطلح في الأصل", "Term in the original"), text: glossaryBinding(entry.id, \.source))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(BasirSpacing.s)
                        .background(BasirPalette.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel(l10n.t("المصطلح \(index + 1) في الأصل", "Term \(index + 1) in the original"))
                    TextField(l10n.t("ترجمته التي تريدها", "Your translation"), text: glossaryBinding(entry.id, \.target))
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
                                     argument: l10n.t("أُضيف مصطلح جديد في آخر القائمة.", "A new term was added at the end of the list."))
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
        case .natural: parts.append(l10n.t("أسلوب طبيعي", "natural style"))
        case .plain: parts.append(l10n.t("لغة مبسّطة", "plain language"))
        }
        if formality == .neutral { parts.append(l10n.t("لغة يومية", "everyday register")) }
        if names == .targetScript { parts.append(l10n.t("الأسماء بحروف الترجمة", "names in target script")) }
        if terms == .translateWithOriginal { parts.append(l10n.t("المصطلحات مع أصلها", "terms with originals")) }
        if terms == .keep { parts.append(l10n.t("المصطلحات بلغتها", "terms kept")) }
        if quotations == .keepWithMeaning { parts.append(l10n.t("الاقتباسات مع معناها", "quotations with meaning")) }
        if quotations == .translate { parts.append(l10n.t("الاقتباسات مترجمة", "quotations translated")) }
        if numerals == .western { parts.append(l10n.t("أرقام 0123", "digits 0123")) }
        if numerals == .eastern { parts.append(l10n.t("أرقام ٠١٢٣", "digits ٠١٢٣")) }
        if notes { parts.append(l10n.t("ملاحظات المترجم", "translator's notes")) }
        if imageText == .keep { parts.append(l10n.t("نص الصور بلغته", "picture text kept")) }
        let terms = usableGlossary.count
        if terms > 0 { parts.append(l10n.t("قاموس: \(terms)", "glossary: \(terms)")) }
        return parts.isEmpty
            ? l10n.t("الإعدادات الافتراضية: ترجمة أمينة رسمية.", "Default settings: faithful, formal translation.")
            : parts.joined(separator: l10n.isArabic ? "، " : ", ")
    }
}
