import SwiftUI

struct PracticeHubView: View {
    var body: some View {
        List {
            Section(L("المدرب الذكي")) {
                NavigationLink { TutorView() } label: { Label(L("المدرّس النصي"), systemImage: "bubble.left.and.bubble.right.fill") }
                NavigationLink { VoiceCoachView() } label: { Label(L("محادثة صوتية ذكية"), systemImage: "waveform.badge.mic") }
                NavigationLink { AdvancedPreparationHubView() } label: { Label(L("IELTS وSTEP والمقابلات"), systemImage: "doc.text.magnifyingglass") }
                NavigationLink { MistakeNotebookView() } label: { Label(L("دفتر الأخطاء"), systemImage: "exclamationmark.bubble.fill") }
            }
            Section(L("ذكاء الخادم")) {
                NavigationLink { ExplainView() } label: { Label(L("اشرح لي"), systemImage: "sparkles") }
                NavigationLink { WritingCoachView() } label: { Label(L("مصحّح الكتابة"), systemImage: "pencil.and.scribble") }
                NavigationLink { AIExerciseView() } label: { Label(L("مولّد التمارين"), systemImage: "wand.and.stars") }
                NavigationLink { LeaderboardView() } label: { Label(L("لوحة الصدارة"), systemImage: "trophy.fill") }
            }
            Section(L("مختبرات المستوى المتقدم")) {
                NavigationLink { AdvancedSkillsHubView() } label: { Label(L("القراءة والاستماع والكتابة"), systemImage: "books.vertical.fill") }
                NavigationLink { LearningPathwaysView() } label: { Label(L("مسارات الهدف"), systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                NavigationLink { WeeklyProgressReportView() } label: { Label(L("التقرير الأسبوعي"), systemImage: "doc.text.image.fill") }
            }
            Section(L("تدريب تفاعلي")) {
                NavigationLink { ConversationStudioView() } label: { Label(L("استوديو المحادثة"), systemImage: "person.2.wave.2.fill") }
                NavigationLink { DictationChallengeView() } label: { Label(L("تحدي الإملاء"), systemImage: "pencil.and.outline") }
                NavigationLink { FiveMinuteChallengeView() } label: { Label(L("تحدي خمس دقائق"), systemImage: "timer") }
            }
            Section(L("مهارات اللغة")) {
                NavigationLink { PronunciationLabView() } label: { Label(L("مختبر النطق"), systemImage: "waveform.and.mic") }
                NavigationLink { ListeningLabView() } label: { Label(L("مختبر الاستماع"), systemImage: "headphones") }
                NavigationLink { SentenceBuilderView() } label: { Label(L("مصنع الجمل"), systemImage: "text.word.spacing") }
            }
            Section(L("مكتبة التعلّم")) {
                NavigationLink { PlacementTestView() } label: { Label(L("اختبار تحديد المستوى التكيفي"), systemImage: "scope") }
                NavigationLink { GrammarLibraryView() } label: { Label(L("مكتبة القواعد"), systemImage: "function") }
                NavigationLink { StoryLibraryView() } label: { Label(L("القصص المتدرجة والتفاعلية"), systemImage: "book.pages.fill") }
                NavigationLink { WordbookView() } label: { Label(L("قاموسي الشخصي"), systemImage: "character.book.closed.fill") }
                NavigationLink { DailyPlanView() } label: { Label(L("خطتي الذكية"), systemImage: "wand.and.stars") }
                NavigationLink { LearningInsightsView() } label: { Label(L("تحليلات التقدم"), systemImage: "chart.xyaxis.line") }
                NavigationLink { AchievementsView() } label: { Label(L("الإنجازات"), systemImage: "trophy.fill") }
            }
        }
        .navigationTitle(L("مركز التدريب"))
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
            Section(L("الجملة المستهدفة")) {
                TextField(L("الجملة"), text: $target, axis: .vertical).environment(\.layoutDirection, .leftToRight)
                Picker(L("اللكنة"), selection: $settings.accentVariant) {
                    ForEach(AccentVariant.allCases) { accent in
                        Text(L(accent.titleAr)).tag(accent)
                    }
                }
                Button(L("استمع للنموذج")) {
                    textToSpeech.speak(target, accent: settings.accentVariant, rate: Float(settings.speechRate))
                }
            }
            Section(L("تسجيلك")) {
                Button(speechService.state == .listening ? L("إيقاف") : L("ابدأ النطق")) {
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
                Text(speechService.transcript.isEmpty ? L("لا يوجد تفريغ بعد") : speechService.transcript)
                    .environment(\.layoutDirection, .leftToRight)
                if !speechService.transcript.isEmpty && speechService.state != .listening {
                    Button(L("تحليل النطق")) { analyze() }
                        .buttonStyle(.borderedProminent)
                }
            }

            if let report {
                Section(L("التقرير")) {
                    AccessibleProgressView(title: L("النتيجة الكلية"), value: report.overall)
                    LabeledContent(L("دقة الكلمات"), value: "\(Int(report.accuracy * 100))٪")
                    LabeledContent(L("اكتمال الجملة"), value: "\(Int(report.completeness * 100))٪")
                    LabeledContent(L("الطلاقة"), value: "\(Int(report.fluency * 100))٪")
                    LabeledContent(L("السرعة"), value: Lf("%@ كلمة في الدقيقة", "\(Int(report.wordsPerMinute))"))
                    Text(L("هذا التحليل يعتمد على تفريغ الكلام والتوقيت وثقة نظام التعرف، وليس قياسًا صوتيًا مخبريًا لمخارج الحروف."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !report.needsPractice.isEmpty {
                    Section(L("كلمات تحتاج تدريبًا")) {
                        ForEach(report.needsPractice) { word in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(word.expected.isEmpty ? word.recognized ?? "" : word.expected)
                                    .font(.headline)
                                    .environment(\.layoutDirection, .leftToRight)
                                Text(L(word.issue.titleAr)).font(.caption.bold())
                                if let tip = word.tipAr { Text(tip).font(.caption).foregroundStyle(.secondary) }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                Section(L("نصائح")) {
                    ForEach(report.tipsAr, id: \.self) { tip in
                        Label(tip, systemImage: "lightbulb.fill")
                    }
                }
            }
        }
        .navigationTitle(L("مختبر النطق"))
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
            await container.progressRepository.recordSkill(.practicalCommunication, correct: value.overall >= 0.72, at: .now)
            for word in value.needsPractice.prefix(3) where !word.expected.isEmpty {
                await container.learningMemoryRepository.recordMistake(.init(
                    id: UUID().uuidString,
                    category: L("النطق"),
                    source: L("مختبر النطق"),
                    prompt: word.expected,
                    learnerAnswer: word.recognized ?? L("لم تُلتقط"),
                    correction: word.expected,
                    explanationAr: word.tipAr ?? L("أعد الكلمة منفردة ثم داخل الجملة."),
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
            Button(L("تشغيل المقطع")) {
                textToSpeech.speak(sentence, accent: settings.accentVariant, rate: Float(settings.speechRate))
            }
            TextField(L("اكتب ما سمعت"), text: $answer, axis: .vertical).environment(\.layoutDirection, .leftToRight)
            if !answer.isEmpty {
                let score = StringSimilarity.score(sentence, answer)
                AccessibleProgressView(title: L("الدقة"), value: score)
                Button(L("تسجيل النتيجة")) {
                    guard !didRecord else { return }
                    didRecord = true
                    Task { await container.progressRepository.recordSkill(.listening, correct: score >= 0.82, at: .now) }
                }
                .disabled(didRecord)
            }
        }
        .navigationTitle(L("مختبر الاستماع"))
    }
}

struct SentenceBuilderView: View {
    @State private var subject = "I"
    @State private var verb = "study"
    @State private var complement = "English every day"

    var body: some View {
        Form {
            Section(L("ابنِ الجملة")) {
                TextField(L("الفاعل"), text: $subject)
                TextField(L("الفعل"), text: $verb)
                TextField(L("التكملة"), text: $complement)
            }
            Section(L("النتيجة")) {
                Text("\(subject) \(verb) \(complement).")
                    .font(.title2.bold()).environment(\.layoutDirection, .leftToRight)
            }
        }
        .navigationTitle(L("مصنع الجمل"))
    }
}
