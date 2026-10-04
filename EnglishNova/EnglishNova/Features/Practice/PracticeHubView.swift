import SwiftUI

struct PracticeHubView: View {
    @EnvironmentObject private var account: AccountService
    @State private var searchText = ""
    @State private var quota: AIQuota?

    private struct Entry: Identifiable {
        let id: String
        let title: String
        let detail: String
        let systemImage: String
        let tint: Color
        let destination: () -> AnyView
    }

    private struct PracticeGroup: Identifiable {
        let id: String
        let title: String
        let entries: [Entry]
    }

    private var groups: [PracticeGroup] {
        [
            PracticeGroup(id: "mistakes", title: LE("ابدأ من نقاط ضعفك", "Start with your weak spots"), entries: [
                Entry(id: "remedial", title: LE("تدرّب على أخطائك", "Practise your mistakes"),
                      detail: LE("أسئلة أخطأت فيها تعود إليك حتى تتقنها", "Items you missed come back until you master them"),
                      systemImage: "arrow.uturn.backward.circle.fill", tint: AppTheme.streak) { AnyView(RemedialPracticeView()) },
                Entry(id: "custom", title: L("تمارين مخصصة"),
                      detail: LE("تمارين جديدة بحسب مستواك وأخطائك", "Fresh exercises for your level and mistakes"),
                      systemImage: "wand.and.stars", tint: AppTheme.brandSecondary) { AnyView(AIExerciseView()) }
            ]),
            PracticeGroup(id: "speak", title: LE("تحدّث واستمع", "Speak and listen"), entries: [
                Entry(id: "voice", title: L("تدريب المحادثة بالصوت"),
                      detail: LE("محادثة صوتية مع المدرّب", "A spoken conversation with the tutor"),
                      systemImage: "waveform.badge.mic", tint: AppTheme.brand) { AnyView(VoiceCoachView()) },
                Entry(id: "tutor", title: L("المدرّب النصي"),
                      detail: LE("اكتب واسأل واحصل على تصحيح فوري", "Write, ask and get instant corrections"),
                      systemImage: "bubble.left.and.bubble.right.fill", tint: AppTheme.brand) { AnyView(TutorView()) },
                Entry(id: "shadowing", title: LE("مدرّب النطق", "Pronunciation coach"),
                      detail: LE("استمع وقلّد جملًا من دروسك واعرف الكلمات التي تحتاج تدريبًا", "Shadow sentences from your lessons and find words to work on"),
                      systemImage: "person.wave.2.fill", tint: AppTheme.accentTeal) { AnyView(ShadowingCoachView()) },
                Entry(id: "pronunciation", title: L("تدريب النطق"),
                      detail: LE("قل جملة واعرف الكلمات التي تحتاج تدريبًا", "Say a sentence and see which words need work"),
                      systemImage: "waveform.and.mic", tint: AppTheme.accentTeal) { AnyView(PronunciationLabView()) },
                Entry(id: "listening", title: L("تدريب الاستماع"),
                      detail: LE("استمع واكتب ما سمعت", "Listen and type what you hear"),
                      systemImage: "headphones", tint: AppTheme.accentTeal) { AnyView(ListeningLabView()) },
                Entry(id: "scenarios", title: L("مواقف محادثة"),
                      detail: LE("مطعم، مطار، عمل، وغيرها", "Restaurant, airport, work and more"),
                      systemImage: "person.2.wave.2.fill", tint: AppTheme.brandSecondary) { AnyView(ConversationStudioView()) }
            ]),
            PracticeGroup(id: "write", title: LE("اكتب واقرأ", "Write and read"), entries: [
                Entry(id: "writing", title: L("تدريب الكتابة"),
                      detail: LE("اكتب فقرة واحصل على تقييم وتصحيح", "Write a paragraph and get feedback"),
                      systemImage: "pencil.and.scribble", tint: AppTheme.brand) { AnyView(WritingCoachView()) },
                Entry(id: "skills", title: L("القراءة والكتابة والاستماع"),
                      detail: LE("أنشطة مهارات متدرجة لكل مستوى", "Graded skill activities for every level"),
                      systemImage: "books.vertical.fill", tint: AppTheme.accentTeal) { AnyView(AdvancedSkillsHubView()) },
                Entry(id: "stories", title: L("قصص متدرجة"),
                      detail: LE("قصص تفاعلية تختار فيها النهاية", "Interactive stories where you choose the ending"),
                      systemImage: "book.pages.fill", tint: AppTheme.brandSecondary) { AnyView(StoryLibraryView()) },
                Entry(id: "sentences", title: L("بناء الجمل"),
                      detail: LE("ركّب جملة من أجزائها", "Build a sentence from its parts"),
                      systemImage: "text.word.spacing", tint: AppTheme.warning) { AnyView(SentenceBuilderView()) },
                Entry(id: "explain-text", title: LE("اشرح أي نص", "Explain any text"),
                      detail: LE("صوّر لافتة أو صفحة أو الصق نصًا واحصل على ترجمة وشرح", "Photograph a sign or page, or paste text, for a translation and explanation"),
                      systemImage: "text.viewfinder", tint: AppTheme.brand) { AnyView(ExplainTextView()) },
                Entry(id: "explain", title: L("شرح كلمة أو قاعدة"),
                      detail: LE("اسأل عن أي كلمة أو قاعدة", "Ask about any word or rule"),
                      systemImage: "sparkles", tint: AppTheme.warning) { AnyView(ExplainView()) }
            ]),
            PracticeGroup(id: "quick", title: LE("تحديات قصيرة", "Quick challenges"), entries: [
                Entry(id: "five", title: L("خمس دقائق"),
                      detail: LE("جولة سريعة من أسئلة متنوعة", "A quick round of mixed questions"),
                      systemImage: "timer", tint: AppTheme.streak) { AnyView(FiveMinuteChallengeView()) },
                Entry(id: "dictation", title: L("إملاء"),
                      detail: LE("استمع إلى جمل واكتبها", "Listen to sentences and write them"),
                      systemImage: "pencil.and.outline", tint: AppTheme.streak) { AnyView(DictationChallengeView()) }
            ]),
            PracticeGroup(id: "exams", title: L("اختبارات وأهداف"), entries: [
                Entry(id: "mock", title: LE("اختبار تجريبي كامل", "Full mock test"),
                      detail: LE("Listening أو Reading بتوقيت حقيقي وBand تقريبي", "Timed Listening or Reading with an approximate band"),
                      systemImage: "stopwatch.fill", tint: AppTheme.streak) { AnyView(MockExamHubView()) },
                Entry(id: "ielts6", title: L("منهج IELTS 6.0 المكثف"),
                      detail: LE("خطة مكثفة للوصول إلى 6.0", "An intensive plan to reach band 6.0"),
                      systemImage: "scope", tint: AppTheme.brand) { AnyView(IELTSBandSixView()) },
                Entry(id: "prep", title: L("IELTS وSTEP والمقابلات"),
                      detail: LE("أسئلة تدريبية واختبارات ومقابلات", "Practice questions, tests and interviews"),
                      systemImage: "doc.text.magnifyingglass", tint: AppTheme.brand) { AnyView(AdvancedPreparationHubView()) },
                Entry(id: "placement", title: L("اختبار تحديد المستوى"),
                      detail: LE("اعرف مستواك الحالي", "Find your current level"),
                      systemImage: "chart.bar.doc.horizontal", tint: AppTheme.accentTeal) { AnyView(PlacementTestView()) },
                Entry(id: "pathways", title: L("مسارات التعلّم"),
                      detail: LE("سفر، عمل، دراسة، وغيرها", "Travel, work, study and more"),
                      systemImage: "point.topleft.down.to.point.bottomright.curvepath", tint: AppTheme.accentTeal) { AnyView(LearningPathwaysView()) }
            ]),
            PracticeGroup(id: "reference", title: LE("مراجع", "Reference"), entries: [
                Entry(id: "grammar", title: L("مرجع القواعد"),
                      detail: LE("قواعد مشروحة بأمثلة", "Grammar explained with examples"),
                      systemImage: "function", tint: AppTheme.brandSecondary) { AnyView(GrammarLibraryView()) }
            ])
        ]
    }

    private var filteredGroups: [PracticeGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return groups }
        return groups.compactMap { group in
            let entries = group.entries.filter {
                $0.title.localizedCaseInsensitiveContains(query) || $0.detail.localizedCaseInsensitiveContains(query)
            }
            return entries.isEmpty ? nil : PracticeGroup(id: group.id, title: group.title, entries: entries)
        }
    }

    var body: some View {
        List {
            if let quota, searchText.isEmpty {
                Section {
                    AccessibleProgressView(
                        title: LfE("رصيد المساعد الذكي اليوم: %@ من %@", "Today's AI allowance: %@ of %@ left",
                                   "\(quota.remainingUnits)", "\(quota.dailyUnits)"),
                        value: Double(quota.remainingUnits) / Double(max(quota.dailyUnits, 1))
                    )
                } footer: {
                    Text(LE("يتجدد عند منتصف الليل بتوقيت الرياض. الدروس والمراجعة والتدريب المحلي لا تستهلك الرصيد.",
                            "Renews at midnight Riyadh time. Lessons, review and offline practice don't use it."))
                }
            }
            if filteredGroups.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
            ForEach(filteredGroups) { group in
                Section(group.title) {
                    ForEach(group.entries) { entry in
                        NavigationLink { entry.destination() } label: { row(entry) }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: LE("ابحث عن تدريب", "Search practice"))
        .navigationTitle(L("التدريب"))
        .task(id: account.isAuthenticated) {
            quota = account.isAuthenticated ? try? await AIStudioService().quota() : nil
        }
    }

    private func row(_ entry: Entry) -> some View {
        HStack(spacing: 14) {
            Image(systemName: entry.systemImage)
                .font(.headline)
                .foregroundStyle(entry.tint)
                .frame(width: 38, height: 38)
                .background(entry.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.body.weight(.semibold))
                Text(entry.detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct PronunciationLabView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var textToSpeech: TextToSpeechService
    @State private var target: String
    @State private var report: PronunciationReport?
    @State private var didRecord = false
    private let onComplete: (() -> Void)?

    init(initialTarget: String = "I would like a cup of coffee, please.", onComplete: (() -> Void)? = nil) {
        _target = State(initialValue: initialTarget)
        self.onComplete = onComplete
    }

    var body: some View {
        Form {
            Section(L("النص الذي ستقوله")) {
                TextField(L("الجملة"), text: $target, axis: .vertical)
                    .environment(\.layoutDirection, .leftToRight)
                Picker(L("اللكنة"), selection: $settings.accentVariant) {
                    ForEach(AccentVariant.allCases) { accent in
                        Text(accent.titleAr).tag(accent)
                    }
                }
                Button(L("سماع النموذج")) {
                    textToSpeech.speak(
                        target,
                        accent: settings.accentVariant,
                        rate: Float(settings.speechRate)
                    )
                }
            }

            Section(L("تسجيلك")) {
                Button(speechService.state == .listening ? L("إيقاف التسجيل") : L("ابدأ التسجيل")) {
                    Task {
                        if speechService.state == .listening {
                            speechService.stop()
                        } else {
                            report = nil
                            didRecord = false
                            speechService.resetTranscript()
                            await speechService.start(localeIdentifier: settings.accentVariant.localeIdentifier)
                        }
                    }
                }

                Text(speechService.transcript.isEmpty ? L("لم يلتقط التطبيق كلامًا بعد.") : speechService.transcript)
                    .environment(\.layoutDirection, .leftToRight)

                if !speechService.transcript.isEmpty && speechService.state != .listening {
                    Button(L("عرض التقييم")) { analyze() }
                        .buttonStyle(.borderedProminent)
                }
            }

            if let report {
                Section(L("النتيجة")) {
                    AccessibleProgressView(title: L("النتيجة العامة"), value: report.overall)
                    LabeledContent(L("دقة الكلمات"), value: "\(Int(report.accuracy * 100))٪")
                    LabeledContent(L("اكتمال الجملة"), value: "\(Int(report.completeness * 100))٪")
                    LabeledContent(L("الطلاقة"), value: "\(Int(report.fluency * 100))٪")
                    LabeledContent(L("السرعة"), value: Lf("%@ كلمة في الدقيقة", "\(Int(report.wordsPerMinute))"))
                    Text(L("هذه نتيجة تدريبية تقريبية تعتمد على النص الذي تعرّف إليه النظام والتوقيت. لا تقيس مخارج الحروف قياسًا مخبريًا."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !report.needsPractice.isEmpty {
                    Section(L("كلمات تستحق إعادة المحاولة")) {
                        ForEach(report.needsPractice) { word in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(word.expected.isEmpty ? word.recognized ?? "" : word.expected)
                                    .font(.headline)
                                    .environment(\.layoutDirection, .leftToRight)
                                Text(word.issue.titleAr).font(.caption.bold())
                                if let tip = word.tipAr {
                                    Text(tip).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                if !report.tipsAr.isEmpty {
                    Section(L("ملاحظات")) {
                        ForEach(report.tipsAr, id: \.self) { tip in
                            Label(tip, systemImage: "lightbulb.fill")
                        }
                    }
                }
            }
        }
        .navigationTitle(L("تدريب النطق"))
        .onDisappear { speechService.stop() }
    }

    private func analyze() {
        let value = PronunciationAnalyzer.analyze(
            target: target,
            recognized: speechService.transcript,
            accent: settings.accentVariant,
            duration: speechService.elapsedTime,
            segments: speechService.segments
        )
        report = value
        guard !didRecord else { return }
        didRecord = true
        onComplete?()

        Task {
            await container.learningMemoryRepository.recordPronunciation(value)
            await container.progressRepository.recordSkill(
                .practicalCommunication,
                correct: value.overall >= 0.72,
                at: .now
            )
            for word in value.needsPractice.prefix(3) where !word.expected.isEmpty {
                await container.learningMemoryRepository.recordMistake(.init(
                    id: UUID().uuidString,
                    category: L("النطق"),
                    source: L("تدريب النطق"),
                    prompt: word.expected,
                    learnerAnswer: word.recognized ?? L("لم تُلتقط"),
                    correction: word.expected,
                    explanationAr: word.tipAr ?? L("قل الكلمة وحدها أولًا، ثم ضعها داخل الجملة."),
                    createdAt: .now,
                    reviewCount: 0,
                    resolved: false
                ))
            }
        }
    }
}

struct ListeningLabView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var textToSpeech: TextToSpeechService
    @State private var sentence = "The meeting starts at nine in the morning."
    @State private var answer = ""
    @State private var didRecord = false

    var body: some View {
        Form {
            Section {
                Text(L("استمع إلى الجملة، ثم اكتب ما سمعته بالإنجليزية."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(L("تشغيل الجملة")) {
                    textToSpeech.speak(
                        sentence,
                        accent: settings.accentVariant,
                        rate: Float(settings.speechRate)
                    )
                }
                TextField(L("اكتب ما سمعت"), text: $answer, axis: .vertical)
                    .environment(\.layoutDirection, .leftToRight)
            }

            if !answer.isEmpty {
                Section(L("النتيجة")) {
                    let score = StringSimilarity.score(sentence, answer)
                    AccessibleProgressView(title: L("التطابق"), value: score)
                    Button(L("حفظ النتيجة")) {
                        guard !didRecord else { return }
                        didRecord = true
                        Task {
                            await container.progressRepository.recordSkill(
                                .listening,
                                correct: score >= 0.82,
                                at: .now
                            )
                        }
                    }
                    .disabled(didRecord)
                }
            }
        }
        .navigationTitle(L("تدريب الاستماع"))
    }
}

struct SentenceBuilderView: View {
    @State private var subject = "I"
    @State private var verb = "study"
    @State private var complement = "English every day"

    var body: some View {
        Form {
            Section(L("اكتب أجزاء الجملة")) {
                TextField(L("الفاعل"), text: $subject)
                TextField(L("الفعل"), text: $verb)
                TextField(L("بقية الجملة"), text: $complement)
            }
            Section(L("الجملة")) {
                Text("\(subject) \(verb) \(complement).")
                    .font(.title2.bold())
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
        .navigationTitle(L("بناء الجمل"))
    }
}
