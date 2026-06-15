import SwiftUI

struct AdvancedSkillsHubView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        List {
            Section {
                NavigationLink { ReadingComprehensionLabView() } label: {
                    skillRow("مختبر القراءة", "نصوص متدرجة مع أسئلة الفكرة والتفاصيل والسياق.", "book.fill", AdvancedSkillsLibrary.readingPassages.count)
                }
                NavigationLink { ListeningComprehensionLabView() } label: {
                    skillRow("فهم الاستماع", "مقاطع محلية تُنطق بصوت iOS وتُحل دون إظهار النص أولًا.", "headphones", AdvancedSkillsLibrary.listeningPassages.count)
                }
                NavigationLink { WritingStudioView() } label: {
                    skillRow("استوديو الكتابة", "رسائل وفقرات وتقارير مع تقييم محلي متعدد المعايير.", "pencil.line", AdvancedSkillsLibrary.writingPrompts.count)
                }
            } header: {
                Text("المهارات المتقدمة")
            } footer: {
                Text("تعمل المكتبات والتقييمات الأساسية محليًا. يمكن تطويرها لاحقًا بتغذية راجعة من الخادم دون تعطيل الوضع غير المتصل.")
            }

            Section("المسار والتحليل") {
                NavigationLink { LearningPathwaysView() } label: {
                    Label("مساري: \(settings.selectedLearningPathway.titleAr)", systemImage: settings.selectedLearningPathway.systemImage)
                }
                NavigationLink { WeeklyProgressReportView() } label: {
                    Label("تقرير الأسبوع القابل للمشاركة", systemImage: "doc.text.image.fill")
                }
            }

            Section("كيف يعمل التقييم؟") {
                Label("القراءة والاستماع: صحة الإجابات مع تسجيل الإتقان المتناقص بمرور الوقت.", systemImage: "checkmark.circle")
                Label("الكتابة: إنجاز المهمة، والتنظيم، والتنوع، والأساسيات الكتابية.", systemImage: "text.badge.checkmark")
                Label("لا يزعم التقييم المحلي أنه درجة IELTS رسمية أو تدقيق لغوي بشري.", systemImage: "info.circle")
            }
        }
        .navigationTitle("مختبرات اللغة")
    }

    private func skillRow(_ title: String, _ detail: String, _ icon: String, _ count: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                Text("\(count) نشاطًا محليًا").font(.caption.bold())
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ReadingComprehensionLabView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @EnvironmentObject private var textToSpeech: TextToSpeechService
    @State private var passageIndex = 0
    @State private var answers: [String: String] = [:]
    @State private var submitted = false
    @State private var recordedPassageID: String?

    private var passages: [ReadingPassage] { AdvancedSkillsLibrary.readings(for: session.selectedLevel) }
    private var passage: ReadingPassage { passages[passageIndex % max(1, passages.count)] }
    private var score: Double {
        guard !passage.questions.isEmpty else { return 0 }
        return Double(passage.questions.filter { answers[$0.id] == $0.answer }.count) / Double(passage.questions.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(passage.titleAr).font(.largeTitle.bold())
                HStack {
                    Label(passage.level.rawValue, systemImage: "gauge.with.dots.needle.33percent")
                    Label(passage.topicAr, systemImage: "tag.fill")
                    Label("\(passage.estimatedMinutes) د", systemImage: "clock")
                }
                .font(.subheadline)

                InfoCard(title: passage.title, systemImage: "book.pages.fill") {
                    Text(passage.text)
                        .font(.title3)
                        .lineSpacing(7)
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityLabel("النص الإنجليزي. \(passage.text)")
                    Button {
                        textToSpeech.speak(passage.text)
                    } label: {
                        Label("استمع إلى النص", systemImage: "speaker.wave.2.fill")
                    }
                }

                ForEach(Array(passage.questions.enumerated()), id: \.element.id) { number, question in
                    questionCard(question, number: number + 1)
                }

                if submitted {
                    InfoCard(title: "النتيجة", systemImage: score >= 0.70 ? "checkmark.seal.fill" : "arrow.clockwise.circle.fill") {
                        AccessibleProgressView(title: "\(Int(score * 100))٪", value: score)
                        Text(score >= 0.70 ? "فهم جيد. راجع الشرح ثم انتقل إلى نص جديد." : "أعد قراءة النص وابحث عن الكلمات التي تحمل الإجابة مباشرة.")
                        PrimaryButton(title: "النص التالي", systemImage: "arrow.forward.circle.fill") { nextPassage() }
                    }
                } else {
                    PrimaryButton(title: "تصحيح الإجابات", systemImage: "checkmark.circle.fill") { submit() }
                        .disabled(answers.count < passage.questions.count)
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle("مختبر القراءة")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func questionCard(_ question: ComprehensionQuestion, number: Int) -> some View {
        InfoCard(title: "السؤال \(number)", systemImage: "questionmark.circle.fill") {
            Text(question.prompt).font(.headline).environment(\.layoutDirection, .leftToRight)
            Text(question.promptAr).font(.caption).foregroundStyle(.secondary)
            ForEach(question.choices, id: \.self) { choice in
                Button {
                    guard !submitted else { return }
                    answers[question.id] = choice
                } label: {
                    HStack {
                        Image(systemName: choiceIcon(choice, question: question))
                            .accessibilityHidden(true)
                        Text(choice).environment(\.layoutDirection, .leftToRight)
                        Spacer()
                    }
                }
                .buttonStyle(.bordered)
                .tint(choiceTint(choice, question: question))
                .accessibilityLabel(accessibilityChoiceLabel(choice, question: question))
            }
            if submitted {
                Text(question.explanationAr).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func choiceIcon(_ choice: String, question: ComprehensionQuestion) -> String {
        if submitted && choice == question.answer { return "checkmark.circle.fill" }
        if submitted && answers[question.id] == choice { return "xmark.circle.fill" }
        return answers[question.id] == choice ? "largecircle.fill.circle" : "circle"
    }

    private func choiceTint(_ choice: String, question: ComprehensionQuestion) -> Color? {
        if submitted && choice == question.answer { return .green }
        if submitted && answers[question.id] == choice { return .red }
        return nil
    }

    private func accessibilityChoiceLabel(_ choice: String, question: ComprehensionQuestion) -> String {
        if submitted && choice == question.answer { return "\(choice)، الإجابة الصحيحة" }
        if submitted && answers[question.id] == choice { return "\(choice)، إجابتك غير صحيحة" }
        if answers[question.id] == choice { return "\(choice)، محدد" }
        return choice
    }

    private func submit() {
        submitted = true
        guard recordedPassageID != passage.id else { return }
        recordedPassageID = passage.id
        let sessionRecord = PracticeSessionRecord(
            id: UUID().uuidString,
            domain: .reading,
            sourceID: passage.id,
            titleAr: passage.titleAr,
            level: passage.level,
            score: score,
            minutes: passage.estimatedMinutes,
            createdAt: .now,
            details: passage.questions.compactMap { question in
                answers[question.id] == question.answer ? nil : "\(question.prompt): \(question.answer)"
            }
        )
        Task {
            await container.progressRepository.recordPracticeSession(sessionRecord)
            for question in passage.questions where answers[question.id] != question.answer {
                await container.learningMemoryRepository.recordMistake(.init(
                    id: UUID().uuidString,
                    category: "القراءة",
                    source: passage.titleAr,
                    prompt: question.prompt,
                    learnerAnswer: answers[question.id] ?? "دون إجابة",
                    correction: question.answer,
                    explanationAr: question.explanationAr,
                    createdAt: .now,
                    reviewCount: 0,
                    resolved: false
                ))
            }
        }
    }

    private func nextPassage() {
        passageIndex = (passageIndex + 1) % max(1, passages.count)
        answers = [:]
        submitted = false
    }
}

struct ListeningComprehensionLabView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var textToSpeech: TextToSpeechService
    @State private var itemIndex = 0
    @State private var answers: [String: String] = [:]
    @State private var submitted = false
    @State private var replayCount = 0
    @State private var recordedID: String?

    private var items: [ListeningPassage] { AdvancedSkillsLibrary.listenings(for: session.selectedLevel) }
    private var item: ListeningPassage { items[itemIndex % max(1, items.count)] }
    private var score: Double {
        guard !item.questions.isEmpty else { return 0 }
        return Double(item.questions.filter { answers[$0.id] == $0.answer }.count) / Double(item.questions.count)
    }

    var body: some View {
        Form {
            Section("الموقف") {
                Text(item.titleAr).font(.title2.bold())
                Text(item.contextAr).foregroundStyle(.secondary)
                Label("المستوى \(item.level.rawValue)", systemImage: "gauge.with.dots.needle.33percent")
                Button {
                    replayCount += 1
                    textToSpeech.speak(item.transcript, accent: settings.accentVariant, rate: Float(settings.speechRate))
                } label: {
                    Label(replayCount == 0 ? "تشغيل المقطع" : "إعادة المقطع، شُغّل \(replayCount) مرة", systemImage: "play.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                Text("المقترح: \(item.recommendedReplays) تشغيلات أو أقل.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            ForEach(Array(item.questions.enumerated()), id: \.element.id) { number, question in
                Section("السؤال \(number + 1)") {
                    Text(question.prompt).font(.headline).environment(\.layoutDirection, .leftToRight)
                    ForEach(question.choices, id: \.self) { choice in
                        Button {
                            guard !submitted else { return }
                            answers[question.id] = choice
                        } label: {
                            Label(choice, systemImage: answers[question.id] == choice ? "largecircle.fill.circle" : "circle")
                                .environment(\.layoutDirection, .leftToRight)
                        }
                        .accessibilityLabel(answers[question.id] == choice ? "\(choice)، محدد" : choice)
                    }
                    if submitted {
                        Text(answers[question.id] == question.answer ? "إجابة صحيحة" : "الصحيح: \(question.answer)")
                            .font(.caption.bold())
                        Text(question.explanationAr).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if submitted {
                Section("النتيجة") {
                    AccessibleProgressView(title: "\(Int(score * 100))٪", value: score)
                    if settings.revealListeningTranscriptAfterAnswer {
                        DisclosureGroup("إظهار النص بعد الإجابة") {
                            Text(item.transcript).environment(\.layoutDirection, .leftToRight)
                        }
                    }
                    Button("المقطع التالي") { nextItem() }
                }
            } else {
                Button("تصحيح الإجابات") { submit() }
                    .disabled(answers.count < item.questions.count)
            }
        }
        .navigationTitle("فهم الاستماع")
        .onDisappear { textToSpeech.stop() }
    }

    private func submit() {
        submitted = true
        guard recordedID != item.id else { return }
        recordedID = item.id
        Task {
            await container.progressRepository.recordPracticeSession(.init(
                id: UUID().uuidString,
                domain: .listening,
                sourceID: item.id,
                titleAr: item.titleAr,
                level: item.level,
                score: score,
                minutes: max(2, replayCount + 2),
                createdAt: .now,
                details: ["عدد مرات التشغيل: \(replayCount)"]
            ))
            for question in item.questions where answers[question.id] != question.answer {
                await container.learningMemoryRepository.recordMistake(.init(
                    id: UUID().uuidString,
                    category: "الاستماع",
                    source: item.titleAr,
                    prompt: question.prompt,
                    learnerAnswer: answers[question.id] ?? "دون إجابة",
                    correction: question.answer,
                    explanationAr: question.explanationAr,
                    createdAt: .now,
                    reviewCount: 0,
                    resolved: false
                ))
            }
        }
    }

    private func nextItem() {
        textToSpeech.stop()
        itemIndex = (itemIndex + 1) % max(1, items.count)
        answers = [:]
        submitted = false
        replayCount = 0
    }
}

struct WritingStudioView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @State private var promptIndex = 0
    @State private var draft = ""
    @State private var evaluation: WritingEvaluation?
    @State private var recordedPromptID: String?

    private var prompts: [WritingPrompt] { AdvancedSkillsLibrary.writings(for: session.selectedLevel) }
    private var prompt: WritingPrompt { prompts[promptIndex % max(1, prompts.count)] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(prompt.titleAr).font(.largeTitle.bold())
                Text(prompt.kind.titleAr).font(.headline).foregroundStyle(.secondary)

                InfoCard(title: "المهمة", systemImage: "doc.text.fill") {
                    Text(prompt.prompt).font(.title3).environment(\.layoutDirection, .leftToRight)
                    Text(prompt.promptAr).foregroundStyle(.secondary)
                    Label("الحد الأدنى \(prompt.minimumWords) كلمة", systemImage: "number")
                    Text("مفردات مقترحة: \(prompt.suggestedWords.joined(separator: "، "))")
                        .font(.caption)
                        .environment(\.layoutDirection, .leftToRight)
                }

                InfoCard(title: "قائمة الفحص", systemImage: "checklist") {
                    ForEach(prompt.checklistAr, id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("مسودتك").font(.title2.bold())
                    TextEditor(text: $draft)
                        .frame(minHeight: 240)
                        .padding(8)
                        .background(.background, in: RoundedRectangle(cornerRadius: 14))
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityLabel("حقل كتابة المسودة باللغة الإنجليزية")
                    Text("\(wordCount) كلمة")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(wordCount >= prompt.minimumWords ? Color.secondary : Color.orange)
                }

                PrimaryButton(title: "تحليل المسودة محليًا", systemImage: "text.magnifyingglass") { analyze() }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let evaluation {
                    evaluationView(evaluation)
                    DisclosureGroup("نموذج إجابة للمقارنة بعد المحاولة") {
                        Text(prompt.sampleAnswer)
                            .environment(\.layoutDirection, .leftToRight)
                            .textSelection(.enabled)
                    }
                    Button("مهمة جديدة") { nextPrompt() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle("استوديو الكتابة")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var wordCount: Int {
        draft.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.count
    }

    private func evaluationView(_ value: WritingEvaluation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            InfoCard(title: "تقرير الكتابة", systemImage: "chart.bar.doc.horizontal.fill") {
                AccessibleProgressView(title: "النتيجة الكلية \(Int(value.overall * 100))٪", value: value.overall)
                scoreRow("إنجاز المهمة", value.taskAchievement)
                scoreRow("التنظيم والترابط", value.organization)
                scoreRow("تنوع اللغة", value.languageRange)
                scoreRow("الأساسيات الكتابية", value.mechanics)
                Text("هذا تحليل محلي إرشادي يعتمد على بنية النص ومؤشراته، وليس تصحيحًا بشريًا أو درجة اختبار رسمية.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            InfoCard(title: "نقاط قوة", systemImage: "hand.thumbsup.fill") {
                ForEach(value.strengthsAr, id: \.self) { Label($0, systemImage: "checkmark.circle.fill") }
            }
            InfoCard(title: "الخطوة التالية", systemImage: "arrow.up.right.circle.fill") {
                ForEach(value.improvementsAr, id: \.self) { Label($0, systemImage: "lightbulb.fill") }
            }
        }
    }

    private func scoreRow(_ title: String, _ value: Double) -> some View {
        AccessibleProgressView(title: "\(title) \(Int(value * 100))٪", value: value)
    }

    private func analyze() {
        let value = WritingEvaluator.evaluate(text: draft, prompt: prompt)
        evaluation = value
        guard recordedPromptID != prompt.id else { return }
        recordedPromptID = prompt.id
        Task {
            await container.progressRepository.recordPracticeSession(.init(
                id: UUID().uuidString,
                domain: .writing,
                sourceID: prompt.id,
                titleAr: prompt.titleAr,
                level: prompt.level,
                score: value.overall,
                minutes: max(3, wordCount / 12),
                createdAt: .now,
                details: value.improvementsAr
            ))
            if value.overall < 0.72 {
                await container.learningMemoryRepository.recordMistake(.init(
                    id: UUID().uuidString,
                    category: "الكتابة",
                    source: prompt.titleAr,
                    prompt: prompt.prompt,
                    learnerAnswer: String(draft.prefix(500)),
                    correction: prompt.sampleAnswer,
                    explanationAr: value.improvementsAr.joined(separator: " "),
                    createdAt: .now,
                    reviewCount: 0,
                    resolved: false
                ))
            }
        }
    }

    private func nextPrompt() {
        promptIndex = (promptIndex + 1) % max(1, prompts.count)
        draft = ""
        evaluation = nil
    }
}
