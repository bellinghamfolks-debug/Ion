import Combine
import SwiftUI

struct DictationChallengeView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @State private var index = 0
    @State private var answer = ""
    @State private var checked = false
    @State private var score = 0

    private var prompts: [DictationPrompt] {
        let exact = ConversationLibrary.dictationPrompts.filter { $0.level == session.selectedLevel }
        return exact.isEmpty ? ConversationLibrary.dictationPrompts : exact
    }

    private var prompt: DictationPrompt { prompts[index % prompts.count] }

    var body: some View {
        Form {
            Section("الإملاء \(index + 1)") {
                Button { container.textToSpeech.speak(prompt.sentence) } label: {
                    Label("تشغيل الجملة", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(.borderedProminent)
                Text(prompt.translationAr).foregroundStyle(.secondary)
                TextField("اكتب ما سمعت", text: $answer, axis: .vertical)
                    .environment(\.layoutDirection, .leftToRight)
                    .disabled(checked)
            }

            if checked {
                let similarity = StringSimilarity.score(prompt.sentence, answer)
                Section("النتيجة") {
                    AccessibleProgressView(title: "الدقة \(Int(similarity * 100))٪", value: similarity)
                    Text("النص الصحيح: \(prompt.sentence)").environment(\.layoutDirection, .leftToRight)
                }
            }

            Button(checked ? "جملة أخرى" : "تحقق") {
                if checked {
                    index = (index + 1) % prompts.count
                    answer = ""
                    checked = false
                } else {
                    checked = true
                    let correct = StringSimilarity.score(prompt.sentence, answer) >= 0.86
                    if correct { score += 1 }
                    Task { await container.progressRepository.recordSkill(.listening, correct: correct, at: .now) }
                }
            }
            .disabled(answer.isEmpty)
        }
        .navigationTitle("تحدي الإملاء")
    }
}

struct FiveMinuteChallengeView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @State private var questions: [PlacementQuestion] = []
    @State private var index = 0
    @State private var selected = ""
    @State private var correct = 0
    @State private var remainingSeconds = 300
    @State private var isRunning = false
    @State private var isFinished = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 18) {
            if !isRunning && !isFinished {
                Image(systemName: "timer").font(.system(size: 64)).foregroundStyle(.tint).accessibilityHidden(true)
                Text("خمس دقائق").font(.largeTitle.bold())
                Text("عشرة أسئلة سريعة من مستوى قريب من مستواك. ينتهي التحدي عند انتهاء الوقت أو الأسئلة.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                PrimaryButton(title: "ابدأ التحدي", systemImage: "play.fill") { start() }
            } else if isFinished {
                Image(systemName: "flag.checkered").font(.system(size: 64)).foregroundStyle(.tint).accessibilityHidden(true)
                Text("النتيجة \(correct) من \(questions.count)").font(.largeTitle.bold())
                Text("الوقت المتبقي: \(formattedTime)")
                PrimaryButton(title: "إعادة التحدي", systemImage: "arrow.clockwise") { start() }
            } else if questions.indices.contains(index) {
                Text(formattedTime).font(.title.monospacedDigit().bold()).accessibilityLabel("الوقت المتبقي \(formattedTime)")
                AccessibleProgressView(title: "السؤال \(index + 1) من \(questions.count)", value: Double(index) / Double(questions.count))
                Text(questions[index].prompt).font(.title2.bold()).environment(\.layoutDirection, .leftToRight)
                ForEach(questions[index].choices, id: \.self) { choice in
                    Button {
                        selected = choice
                    } label: {
                        HStack {
                            Text(choice).environment(\.layoutDirection, .leftToRight)
                            Spacer()
                            Image(systemName: selected == choice ? "checkmark.circle.fill" : "circle")
                        }
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.bordered)
                }
                PrimaryButton(title: "إجابة", systemImage: "arrow.forward", isDisabled: selected.isEmpty) { submit() }
            }
        }
        .padding(AppTheme.screenPadding)
        .screenBackground()
        .navigationTitle("تحدي خمس دقائق")
        .onReceive(timer) { _ in
            guard isRunning else { return }
            if remainingSeconds > 0 { remainingSeconds -= 1 }
            else { finish() }
        }
    }

    private var formattedTime: String {
        String(format: "%d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    private func start() {
        let levelIndex = CEFRLevel.allCases.firstIndex(of: session.selectedLevel) ?? 0
        let allowed = PlacementQuestionBank.all.filter {
            abs((CEFRLevel.allCases.firstIndex(of: $0.level) ?? 0) - levelIndex) <= 1
        }
        questions = Array(allowed.shuffled().prefix(10))
        index = 0
        selected = ""
        correct = 0
        remainingSeconds = 300
        isFinished = false
        isRunning = true
    }

    private func submit() {
        guard questions.indices.contains(index) else { return }
        let question = questions[index]
        let wasCorrect = selected == question.answer
        if wasCorrect { correct += 1 }
        Task { await container.progressRepository.recordSkill(question.skill, correct: wasCorrect, at: .now) }
        if index + 1 >= questions.count { finish() }
        else {
            index += 1
            selected = ""
        }
    }

    private func finish() {
        isRunning = false
        isFinished = true
    }
}

// MARK: - Batch 3 advanced preparation

struct AdvancedPreparationHubView: View {
    var body: some View {
        List {
            Section {
                Text("وحدات متخصصة لاختبارات اللغة والمقابلات. تحفظ النتائج والأخطاء محليًا حتى تتغير الخطة بناءً على أدائك الفعلي.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("الاختبارات") {
                NavigationLink { IELTSSpeakingSimulatorView() } label: {
                    Label("محاكي IELTS Speaking", systemImage: "person.wave.2.fill")
                }
                NavigationLink { STEPPracticeView() } label: {
                    Label("تدريب STEP", systemImage: "doc.text.magnifyingglass")
                }
            }
            Section("العمل") {
                NavigationLink { InterviewCoachView() } label: {
                    Label("مدرب مقابلات العمل", systemImage: "briefcase.fill")
                }
            }
            Section("الذاكرة التعليمية") {
                NavigationLink { MistakeNotebookView() } label: {
                    Label("دفتر الأخطاء", systemImage: "exclamationmark.bubble.fill")
                }
            }
        }
        .navigationTitle("الاستعداد المتقدم")
    }
}

struct IELTSSpeakingSimulatorView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var session: UserSession
    @State private var index = 0
    @State private var answer = ""
    @State private var evaluation: InterviewEvaluation?
    @State private var completedScores: [Double] = []
    @State private var isFinished = false

    private var questions: [ExamQuestion] {
        let levelIndex = CEFRLevel.allCases.firstIndex(of: session.selectedLevel) ?? 0
        let filtered = AdvancedPracticeLibrary.ieltsSpeakingQuestions.filter {
            abs((CEFRLevel.allCases.firstIndex(of: $0.level) ?? 0) - levelIndex) <= 1
        }
        return filtered.isEmpty ? AdvancedPracticeLibrary.ieltsSpeakingQuestions : filtered
    }

    private var question: ExamQuestion { questions[index % questions.count] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if isFinished {
                    completion
                } else {
                    AccessibleProgressView(title: "السؤال \(index + 1) من 3", value: Double(index) / 3)
                    InfoCard(title: "السؤال", systemImage: "quote.bubble.fill") {
                        Text(question.prompt).font(.title2.bold()).environment(\.layoutDirection, .leftToRight)
                        Text(L(question.promptAr)).foregroundStyle(.secondary)
                        Button("استمع للسؤال") {
                            container.textToSpeech.speak(question.prompt, accent: settings.accentVariant, rate: Float(settings.speechRate))
                        }
                    }

                    TextField("أجب بالإنجليزية", text: $answer, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(5...12)
                        .environment(\.layoutDirection, .leftToRight)
                        .disabled(evaluation != nil)

                    Button {
                        Task {
                            if speechService.state == .listening {
                                speechService.stop()
                                answer = speechService.transcript
                            } else {
                                speechService.resetTranscript()
                                await speechService.start(localeIdentifier: settings.accentVariant.localeIdentifier)
                            }
                        }
                    } label: {
                        Label(speechService.state == .listening ? "إيقاف الإجابة" : "الإجابة بالصوت", systemImage: "mic.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(evaluation != nil)

                    if let evaluation {
                        InfoCard(title: "تقييم تدريبي", systemImage: "chart.bar.fill") {
                            AccessibleProgressView(title: "النتيجة \(Int(evaluation.overall * 100))٪", value: evaluation.overall)
                            LabeledContent("الإجابة عن السؤال", value: "\(Int(evaluation.relevance * 100))٪")
                            LabeledContent("الترابط والبناء", value: "\(Int(evaluation.structure * 100))٪")
                            LabeledContent("تنوع اللغة", value: "\(Int(evaluation.language * 100))٪")
                            ForEach(evaluation.feedbackAr, id: \.self) { Text($0) }
                            Text("هذا مؤشر تدريبي محلي، وليس تقدير Band رسميًا من IELTS.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    PrimaryButton(
                        title: evaluation == nil ? "قيّم الإجابة" : "السؤال التالي",
                        systemImage: evaluation == nil ? "checkmark.circle" : "arrow.forward.circle",
                        isDisabled: answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        if evaluation == nil { evaluate() } else { advance() }
                    }
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle("IELTS Speaking")
        .onChange(of: speechService.transcript) { _, value in
            if speechService.state == .listening { answer = value }
        }
        .onDisappear { speechService.stop() }
    }

    private var completion: some View {
        let average = completedScores.isEmpty ? 0 : completedScores.reduce(0, +) / Double(completedScores.count)
        return InfoCard(title: "اكتملت المحاكاة", systemImage: "flag.checkered") {
            AccessibleProgressView(title: "متوسط الجلسة \(Int(average * 100))٪", value: average)
            Text("راجع الملاحظات المسجلة في دفتر الأخطاء، ثم أعد سؤالًا واحدًا بصياغة أفضل بدل تكرار الجلسة كاملة فورًا.")
            Button("جلسة جديدة") {
                index = 0
                answer = ""
                evaluation = nil
                completedScores = []
                isFinished = false
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func evaluate() {
        let result = SpeakingResponseAnalyzer.evaluate(answer: answer, question: question)
        evaluation = result
        completedScores.append(result.overall)
        Task {
            await container.progressRepository.recordSkill(.practicalCommunication, correct: result.overall >= 0.68, at: .now)
            if result.overall < 0.7 {
                await container.learningMemoryRepository.recordMistake(.init(
                    id: UUID().uuidString,
                    category: "IELTS Speaking",
                    source: question.id,
                    prompt: question.prompt,
                    learnerAnswer: answer,
                    correction: "Answer directly, give a reason, and add one example.",
                    explanationAr: result.feedbackAr.joined(separator: " "),
                    createdAt: .now,
                    reviewCount: 0,
                    resolved: false
                ))
            }
        }
    }

    private func advance() {
        if index >= 2 {
            isFinished = true
            let average = completedScores.isEmpty ? 0 : completedScores.reduce(0, +) / Double(completedScores.count)
            Task {
                await container.learningMemoryRepository.recordExamAttempt(.init(
                    id: UUID().uuidString,
                    track: .ieltsSpeaking,
                    score: average,
                    answered: completedScores.count,
                    correct: completedScores.filter { $0 >= 0.68 }.count,
                    createdAt: .now,
                    notesAr: ["مؤشر محلي للطلاقة والترابط وليس درجة IELTS رسمية."]
                ))
            }
        } else {
            index += 1
            answer = ""
            evaluation = nil
            speechService.resetTranscript()
        }
    }
}

struct STEPPracticeView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @State private var questions: [ExamQuestion] = []
    @State private var index = 0
    @State private var selected = ""
    @State private var checked = false
    @State private var correct = 0
    @State private var isFinished = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if questions.isEmpty {
                Text("جلسة STEP قصيرة من عشرة أسئلة، مع شرح الإجابة وتسجيل الأخطاء للمراجعة.")
                    .foregroundStyle(.secondary)
                PrimaryButton(title: "ابدأ الجلسة", systemImage: "play.fill") { start() }
            } else if isFinished {
                InfoCard(title: "نتيجة STEP التدريبية", systemImage: "checkmark.seal.fill") {
                    AccessibleProgressView(title: "\(correct) من \(questions.count)", value: Double(correct) / Double(max(1, questions.count)))
                    Text("هذه نتيجة جلسة تدريبية قصيرة وليست تحويلًا رسميًا إلى درجة STEP.")
                    Button("جلسة جديدة") { start() }.buttonStyle(.borderedProminent)
                }
            } else if questions.indices.contains(index) {
                let question = questions[index]
                AccessibleProgressView(title: "السؤال \(index + 1) من \(questions.count)", value: Double(index) / Double(questions.count))
                Text(question.prompt).font(.title2.bold()).environment(\.layoutDirection, .leftToRight)
                Text(L(question.promptAr)).foregroundStyle(.secondary)
                ForEach(question.choices, id: \.self) { choice in
                    Button {
                        if !checked { selected = choice }
                    } label: {
                        HStack {
                            Text(choice).environment(\.layoutDirection, .leftToRight)
                            Spacer()
                            Image(systemName: selected == choice ? "checkmark.circle.fill" : "circle")
                        }
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.bordered)
                    .disabled(checked)
                }
                if checked {
                    InfoCard(title: selected == question.answer ? "إجابة صحيحة" : "الإجابة تحتاج مراجعة", systemImage: selected == question.answer ? "checkmark.circle.fill" : "xmark.circle.fill") {
                        Text("الإجابة الصحيحة: \(question.answer ?? "")")
                            .environment(\.layoutDirection, .leftToRight)
                        Text(question.explanationAr)
                    }
                }
                PrimaryButton(
                    title: checked ? "التالي" : "تحقق",
                    systemImage: checked ? "arrow.forward" : "checkmark",
                    isDisabled: selected.isEmpty
                ) {
                    if checked { next() } else { check(question) }
                }
            }
        }
        .padding(AppTheme.screenPadding)
        .screenBackground()
        .navigationTitle("تدريب STEP")
    }

    private func start() {
        let levelIndex = CEFRLevel.allCases.firstIndex(of: session.selectedLevel) ?? 0
        let nearby = AdvancedPracticeLibrary.stepQuestions.filter {
            abs((CEFRLevel.allCases.firstIndex(of: $0.level) ?? 0) - levelIndex) <= 1
        }
        let pool = nearby.count >= 10 ? nearby : AdvancedPracticeLibrary.stepQuestions
        questions = Array(pool.shuffled().prefix(10))
        index = 0
        selected = ""
        checked = false
        correct = 0
        isFinished = false
    }

    private func check(_ question: ExamQuestion) {
        checked = true
        let wasCorrect = selected == question.answer
        if wasCorrect { correct += 1 }
        Task {
            await container.progressRepository.recordSkill(.grammar, correct: wasCorrect, at: .now)
            if !wasCorrect {
                await container.learningMemoryRepository.recordMistake(.init(
                    id: UUID().uuidString,
                    category: "STEP",
                    source: question.id,
                    prompt: question.prompt,
                    learnerAnswer: selected,
                    correction: question.answer ?? "",
                    explanationAr: question.explanationAr,
                    createdAt: .now,
                    reviewCount: 0,
                    resolved: false
                ))
            }
        }
    }

    private func next() {
        if index + 1 >= questions.count {
            isFinished = true
            Task {
                await container.learningMemoryRepository.recordExamAttempt(.init(
                    id: UUID().uuidString,
                    track: .step,
                    score: Double(correct) / Double(max(1, questions.count)),
                    answered: questions.count,
                    correct: correct,
                    createdAt: .now,
                    notesAr: ["جلسة تدريبية قصيرة من بنك محلي."]
                ))
            }
        } else {
            index += 1
            selected = ""
            checked = false
        }
    }
}

struct InterviewCoachView: View {
    var body: some View {
        List {
            Section {
                Text("اختر سؤالًا، أجب كتابة أو صوتًا، ثم راجع مدى صلة الإجابة وبنيتها ولغتها. الأسئلة تشمل القانون والحوكمة والمواقف السلوكية.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(InterviewCategory.allCases) { category in
                Section(category.titleAr) {
                    ForEach(AdvancedPracticeLibrary.interviewQuestions.filter { $0.category == category }) { question in
                        NavigationLink {
                            InterviewQuestionView(question: question)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(question.question).environment(\.layoutDirection, .leftToRight)
                                Text(question.questionAr).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("مدرب المقابلات")
    }
}

private struct InterviewQuestionView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var speechService: SpeechService
    let question: InterviewQuestion
    @State private var answer = ""
    @State private var evaluation: InterviewEvaluation?

    var body: some View {
        Form {
            Section("السؤال") {
                Text(question.question).font(.title2.bold()).environment(\.layoutDirection, .leftToRight)
                Text(question.questionAr).foregroundStyle(.secondary)
                Button("استمع للسؤال") {
                    container.textToSpeech.speak(question.question, accent: settings.accentVariant, rate: Float(settings.speechRate))
                }
            }

            Section("إجابتك") {
                TextField("أجب بالإنجليزية", text: $answer, axis: .vertical)
                    .lineLimit(5...12)
                    .environment(\.layoutDirection, .leftToRight)
                    .disabled(evaluation != nil)
                Button {
                    Task {
                        if speechService.state == .listening {
                            speechService.stop()
                            answer = speechService.transcript
                        } else {
                            speechService.resetTranscript()
                            await speechService.start(localeIdentifier: settings.accentVariant.localeIdentifier)
                        }
                    }
                } label: {
                    Label(speechService.state == .listening ? "إيقاف" : "إجابة صوتية", systemImage: "mic.fill")
                }
                .disabled(evaluation != nil)
            }

            if let evaluation {
                Section("التقييم") {
                    AccessibleProgressView(title: "النتيجة \(Int(evaluation.overall * 100))٪", value: evaluation.overall)
                    LabeledContent("صلة الإجابة", value: "\(Int(evaluation.relevance * 100))٪")
                    LabeledContent("البناء", value: "\(Int(evaluation.structure * 100))٪")
                    LabeledContent("اللغة", value: "\(Int(evaluation.language * 100))٪")
                    ForEach(evaluation.feedbackAr, id: \.self) { Text($0) }
                }
                Section("نموذج وليس نصًا للحفظ") {
                    Text(question.sampleAnswer).environment(\.layoutDirection, .leftToRight)
                    Button("استمع للنموذج") {
                        container.textToSpeech.speak(question.sampleAnswer, accent: settings.accentVariant, rate: Float(settings.speechRate))
                    }
                    ForEach(question.coachingPointsAr, id: \.self) { Label($0, systemImage: "lightbulb.fill") }
                }
            }

            Button(evaluation == nil ? "قيّم الإجابة" : "محاولة جديدة") {
                if evaluation == nil { evaluate() }
                else {
                    answer = ""
                    evaluation = nil
                    speechService.resetTranscript()
                }
            }
            .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && evaluation == nil)
        }
        .navigationTitle(L(question.category.titleAr))
        .onChange(of: speechService.transcript) { _, value in
            if speechService.state == .listening { answer = value }
        }
        .onDisappear { speechService.stop() }
    }

    private func evaluate() {
        let result = SpeakingResponseAnalyzer.evaluateInterview(answer: answer, question: question)
        evaluation = result
        Task {
            await container.learningMemoryRepository.recordInterviewAttempt(.init(
                id: UUID().uuidString,
                track: .workplace,
                score: result.overall,
                answered: 1,
                correct: result.overall >= 0.68 ? 1 : 0,
                createdAt: .now,
                notesAr: result.feedbackAr
            ))
            if result.overall < 0.72 {
                await container.learningMemoryRepository.recordMistake(.init(
                    id: UUID().uuidString,
                    category: "مقابلات العمل",
                    source: question.category.titleAr,
                    prompt: question.question,
                    learnerAnswer: answer,
                    correction: question.sampleAnswer,
                    explanationAr: result.feedbackAr.joined(separator: " "),
                    createdAt: .now,
                    reviewCount: 0,
                    resolved: false
                ))
            }
        }
    }
}

struct MistakeNotebookView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var memory = LearnerMemorySnapshot()
    @State private var showResolved = false
    @State private var searchText = ""

    private var filtered: [LearningMistake] {
        memory.mistakes.filter { mistake in
            (showResolved || !mistake.resolved) &&
            (searchText.isEmpty || [mistake.category, mistake.source, mistake.prompt, mistake.correction]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        List {
            Section {
                Toggle("إظهار الأخطاء المحسومة", isOn: $showResolved)
                LabeledContent("غير محسومة", value: "\(memory.mistakes.filter { !$0.resolved }.count)")
                LabeledContent("تقارير النطق", value: "\(memory.pronunciationReports.count)")
            }

            if filtered.isEmpty {
                ContentUnavailableView(
                    "لا توجد ملاحظات مطابقة",
                    systemImage: "checkmark.circle",
                    description: Text("تظهر هنا أخطاء المحادثة والنطق والاختبارات التي تحتاج مراجعة.")
                )
            } else {
                ForEach(filtered) { mistake in
                    Section(mistake.category) {
                        Text(mistake.prompt).font(.headline).environment(\.layoutDirection, .leftToRight)
                        if !mistake.learnerAnswer.isEmpty {
                            LabeledContent("إجابتك") {
                                Text(mistake.learnerAnswer).environment(\.layoutDirection, .leftToRight)
                            }
                        }
                        LabeledContent("التصحيح") {
                            Text(mistake.correction).environment(\.layoutDirection, .leftToRight)
                        }
                        Text(mistake.explanationAr).foregroundStyle(.secondary)
                        LabeledContent("مرات الظهور أو المراجعة", value: "\(mistake.reviewCount + 1)")
                        Button(mistake.resolved ? "إعادته للمراجعة" : "تعليمه كمحسوم") {
                            Task {
                                await container.learningMemoryRepository.markMistakeResolved(id: mistake.id, resolved: !mistake.resolved)
                                await load()
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "ابحث في الأخطاء")
        .navigationTitle("دفتر الأخطاء")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        memory = await container.learningMemoryRepository.snapshot()
    }
}
