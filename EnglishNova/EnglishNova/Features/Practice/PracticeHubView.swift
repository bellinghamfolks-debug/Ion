import SwiftUI

struct PracticeHubView: View {
    var body: some View {
        List {
            Section("المدرب الذكي") {
                NavigationLink { TutorView() } label: { Label("المدرّس النصي", systemImage: "bubble.left.and.bubble.right.fill") }
                NavigationLink { VoiceCoachView() } label: { Label("محادثة صوتية ذكية", systemImage: "waveform.badge.mic") }
                NavigationLink { AdvancedPreparationHubView() } label: { Label("IELTS وSTEP والمقابلات", systemImage: "doc.text.magnifyingglass") }
                NavigationLink { MistakeNotebookView() } label: { Label("دفتر الأخطاء", systemImage: "exclamationmark.bubble.fill") }
            }
            Section("مختبرات المستوى المتقدم") {
                NavigationLink { AdvancedSkillsHubView() } label: { Label("القراءة والاستماع والكتابة", systemImage: "books.vertical.fill") }
                NavigationLink { LearningPathwaysView() } label: { Label("مسارات الهدف", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                NavigationLink { WeeklyProgressReportView() } label: { Label("التقرير الأسبوعي", systemImage: "doc.text.image.fill") }
            }
            Section("تدريب تفاعلي") {
                NavigationLink { ConversationStudioView() } label: { Label("استوديو المحادثة", systemImage: "person.2.wave.2.fill") }
                NavigationLink { DictationChallengeView() } label: { Label("تحدي الإملاء", systemImage: "pencil.and.outline") }
                NavigationLink { FiveMinuteChallengeView() } label: { Label("تحدي خمس دقائق", systemImage: "timer") }
            }
            Section("مهارات اللغة") {
                NavigationLink { PronunciationLabView() } label: { Label("مختبر النطق", systemImage: "waveform.and.mic") }
                NavigationLink { ListeningLabView() } label: { Label("مختبر الاستماع", systemImage: "headphones") }
                NavigationLink { SentenceBuilderView() } label: { Label("مصنع الجمل", systemImage: "text.word.spacing") }
            }
            Section("مكتبة التعلّم") {
                NavigationLink { PlacementTestView() } label: { Label("اختبار تحديد المستوى التكيفي", systemImage: "scope") }
                NavigationLink { GrammarLibraryView() } label: { Label("مكتبة القواعد", systemImage: "function") }
                NavigationLink { StoryLibraryView() } label: { Label("القصص المتدرجة والتفاعلية", systemImage: "book.pages.fill") }
                NavigationLink { WordbookView() } label: { Label("قاموسي الشخصي", systemImage: "character.book.closed.fill") }
                NavigationLink { DailyPlanView() } label: { Label("خطتي الذكية", systemImage: "wand.and.stars") }
                NavigationLink { LearningInsightsView() } label: { Label("تحليلات التقدم", systemImage: "chart.xyaxis.line") }
                NavigationLink { AchievementsView() } label: { Label("الإنجازات", systemImage: "trophy.fill") }
            }
        }
        .navigationTitle("مركز التدريب")
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
            Section("الجملة المستهدفة") {
                TextField("الجملة", text: $target, axis: .vertical).environment(\.layoutDirection, .leftToRight)
                Picker("اللكنة", selection: $settings.accentVariant) {
                    ForEach(AccentVariant.allCases) { accent in
                        Text(accent.titleAr).tag(accent)
                    }
                }
                Button("استمع للنموذج") {
                    textToSpeech.speak(target, accent: settings.accentVariant, rate: Float(settings.speechRate))
                }
            }
            Section("تسجيلك") {
                Button(speechService.state == .listening ? "إيقاف" : "ابدأ النطق") {
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
                Text(speechService.transcript.isEmpty ? "لا يوجد تفريغ بعد" : speechService.transcript)
                    .environment(\.layoutDirection, .leftToRight)
                if !speechService.transcript.isEmpty && speechService.state != .listening {
                    Button("تحليل النطق") { analyze() }
                        .buttonStyle(.borderedProminent)
                }
            }

            if let report {
                Section("التقرير") {
                    AccessibleProgressView(title: "النتيجة الكلية", value: report.overall)
                    LabeledContent("دقة الكلمات", value: "\(Int(report.accuracy * 100))٪")
                    LabeledContent("اكتمال الجملة", value: "\(Int(report.completeness * 100))٪")
                    LabeledContent("الطلاقة", value: "\(Int(report.fluency * 100))٪")
                    LabeledContent("السرعة", value: "\(Int(report.wordsPerMinute)) كلمة في الدقيقة")
                    Text("هذا التحليل يعتمد على تفريغ الكلام والتوقيت وثقة نظام التعرف، وليس قياسًا صوتيًا مخبريًا لمخارج الحروف.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !report.needsPractice.isEmpty {
                    Section("كلمات تحتاج تدريبًا") {
                        ForEach(report.needsPractice) { word in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(word.expected.isEmpty ? word.recognized ?? "" : word.expected)
                                    .font(.headline)
                                    .environment(\.layoutDirection, .leftToRight)
                                Text(word.issue.titleAr).font(.caption.bold())
                                if let tip = word.tipAr { Text(tip).font(.caption).foregroundStyle(.secondary) }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                Section("نصائح") {
                    ForEach(report.tipsAr, id: \.self) { tip in
                        Label(tip, systemImage: "lightbulb.fill")
                    }
                }
            }
        }
        .navigationTitle("مختبر النطق")
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
                    category: "النطق",
                    source: "مختبر النطق",
                    prompt: word.expected,
                    learnerAnswer: word.recognized ?? "لم تُلتقط",
                    correction: word.expected,
                    explanationAr: word.tipAr ?? "أعد الكلمة منفردة ثم داخل الجملة.",
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
            Button("تشغيل المقطع") {
                textToSpeech.speak(sentence, accent: settings.accentVariant, rate: Float(settings.speechRate))
            }
            TextField("اكتب ما سمعت", text: $answer, axis: .vertical).environment(\.layoutDirection, .leftToRight)
            if !answer.isEmpty {
                let score = StringSimilarity.score(sentence, answer)
                AccessibleProgressView(title: "الدقة", value: score)
                Button("تسجيل النتيجة") {
                    guard !didRecord else { return }
                    didRecord = true
                    Task { await container.progressRepository.recordSkill(.listening, correct: score >= 0.82, at: .now) }
                }
                .disabled(didRecord)
            }
        }
        .navigationTitle("مختبر الاستماع")
    }
}

struct SentenceBuilderView: View {
    @State private var subject = "I"
    @State private var verb = "study"
    @State private var complement = "English every day"

    var body: some View {
        Form {
            Section("ابنِ الجملة") {
                TextField("الفاعل", text: $subject)
                TextField("الفعل", text: $verb)
                TextField("التكملة", text: $complement)
            }
            Section("النتيجة") {
                Text("\(subject) \(verb) \(complement).")
                    .font(.title2.bold()).environment(\.layoutDirection, .leftToRight)
            }
        }
        .navigationTitle("مصنع الجمل")
    }
}
