import SwiftUI

struct PracticeHubView: View {
    var body: some View {
        List {
            Section(L("تدريب مباشر")) {
                NavigationLink { TutorView() } label: {
                    Label(L("المدرّب النصي"), systemImage: "bubble.left.and.bubble.right.fill")
                }
                NavigationLink { VoiceCoachView() } label: {
                    Label(L("تدريب المحادثة بالصوت"), systemImage: "waveform.badge.mic")
                }
                NavigationLink { MistakeNotebookView() } label: {
                    Label(L("راجع أخطاءك"), systemImage: "exclamationmark.bubble.fill")
                }
            }

            Section(L("تدريب مخصص")) {
                NavigationLink { ExplainView() } label: {
                    Label(L("شرح كلمة أو قاعدة"), systemImage: "sparkles")
                }
                NavigationLink { WritingCoachView() } label: {
                    Label(L("تدريب الكتابة"), systemImage: "pencil.and.scribble")
                }
                NavigationLink { AIExerciseView() } label: {
                    Label(L("تمارين مخصصة"), systemImage: "wand.and.stars")
                }
            }

            Section(L("المهارات")) {
                NavigationLink { PronunciationLabView() } label: {
                    Label(L("تدريب النطق"), systemImage: "waveform.and.mic")
                }
                NavigationLink { ListeningLabView() } label: {
                    Label(L("تدريب الاستماع"), systemImage: "headphones")
                }
                NavigationLink { AdvancedSkillsHubView() } label: {
                    Label(L("القراءة والكتابة والاستماع"), systemImage: "books.vertical.fill")
                }
                NavigationLink { SentenceBuilderView() } label: {
                    Label(L("بناء الجمل"), systemImage: "text.word.spacing")
                }
            }

            Section(L("اختبارات وأهداف")) {
                NavigationLink { AdvancedPreparationHubView() } label: {
                    Label(L("IELTS وSTEP والمقابلات"), systemImage: "doc.text.magnifyingglass")
                }
                NavigationLink { PlacementTestView() } label: {
                    Label(L("اختبار تحديد المستوى"), systemImage: "scope")
                }
                NavigationLink { LearningPathwaysView() } label: {
                    Label(L("مسارات التعلّم"), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
            }

            Section(L("تدريب قصير")) {
                NavigationLink { DictationChallengeView() } label: {
                    Label(L("إملاء"), systemImage: "pencil.and.outline")
                }
                NavigationLink { FiveMinuteChallengeView() } label: {
                    Label(L("خمس دقائق"), systemImage: "timer")
                }
                NavigationLink { ConversationStudioView() } label: {
                    Label(L("مواقف محادثة"), systemImage: "person.2.wave.2.fill")
                }
            }

            Section(L("مراجع وتقارير")) {
                NavigationLink { GrammarLibraryView() } label: {
                    Label(L("مرجع القواعد"), systemImage: "function")
                }
                NavigationLink { StoryLibraryView() } label: {
                    Label(L("قصص متدرجة"), systemImage: "book.pages.fill")
                }
                NavigationLink { WordbookView() } label: {
                    Label(L("دفتر المفردات"), systemImage: "character.book.closed.fill")
                }
                NavigationLink { DailyPlanView() } label: {
                    Label(L("خطة اليوم"), systemImage: "checklist")
                }
                NavigationLink { WeeklyProgressReportView() } label: {
                    Label(L("التقرير الأسبوعي"), systemImage: "doc.text.image.fill")
                }
                NavigationLink { LearningInsightsView() } label: {
                    Label(L("تحليل التقدّم"), systemImage: "chart.xyaxis.line")
                }
                NavigationLink { AchievementsView() } label: {
                    Label(L("الإنجازات"), systemImage: "trophy.fill")
                }
                NavigationLink { LeaderboardView() } label: {
                    Label(L("الترتيب"), systemImage: "list.number")
                }
            }
        }
        .navigationTitle(L("التدريب"))
    }
}

struct PronunciationLabView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var textToSpeech: TextToSpeechService
    @State private var target = "I would like a cup of coffee, please."
    @State private var report: PronunciationReport?
    @State private var didRecord = false

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
