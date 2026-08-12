import SwiftUI

struct ConversationStudioView: View {
    @EnvironmentObject private var session: UserSession

    var body: some View {
        List {
            Section(L("المحادثة بالصوت")) {
                NavigationLink {
                    VoiceCoachView()
                } label: {
                    Label(L("تدريب المحادثة بالصوت"), systemImage: "waveform.badge.mic")
                }
                Text(L("استمع إلى الطرف الآخر، أجب بصوتك، ثم راجع ملاحظات النطق ومحتوى الإجابة قبل متابعة الحوار."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text(L("يمكنك أيضًا التدرب على مواقف كاملة بالكتابة أو الصوت. لا يلزم أن تطابق نموذج الإجابة حرفيًا؛ المهم أن توصل الفكرة المطلوبة بوضوح."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(CEFRLevel.allCases) { level in
                let scenarios = ConversationLibrary.scenarios.filter { $0.level == level }
                if !scenarios.isEmpty {
                    Section("\(level.rawValue) • \(level.titleAr)") {
                        ForEach(scenarios) { scenario in
                            NavigationLink {
                                ConversationSessionView(scenario: scenario)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(L(scenario.titleAr)).font(.headline)
                                    Text(scenario.titleEn)
                                        .environment(\.layoutDirection, .leftToRight)
                                    Text(scenario.roleAr)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L("تدريب المحادثة"))
    }
}

private struct ConversationSessionView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var settings: AppSettings
    let scenario: ConversationScenario

    @State private var turnIndex = 0
    @State private var response = ""
    @State private var evaluation: ConversationEvaluation?
    @State private var completedScores: [Double] = []
    @State private var isFinished = false

    private var currentTurn: ConversationTurn? {
        guard scenario.turns.indices.contains(turnIndex) else { return nil }
        return scenario.turns[turnIndex]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L(scenario.titleAr)).font(.largeTitle.bold())
                Text(scenario.roleAr).foregroundStyle(.secondary)
                AccessibleProgressView(
                    title: Lf("الدور %@ من %@", "\(min(turnIndex + 1, scenario.turns.count))", "\(scenario.turns.count)"),
                    value: scenario.turns.isEmpty ? 0 : Double(turnIndex) / Double(scenario.turns.count)
                )

                InfoCard(title: L("الطرف الآخر"), systemImage: "person.crop.circle.fill") {
                    let line = turnIndex == 0 ? scenario.openingLine : responseLine
                    HStack(alignment: .top) {
                        Text(line)
                            .font(.title3)
                            .environment(\.layoutDirection, .leftToRight)
                        Spacer()
                        Button {
                            container.textToSpeech.speak(
                                line,
                                accent: settings.accentVariant,
                                rate: Float(settings.speechRate)
                            )
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        .accessibilityLabel(L("سماع كلام الطرف الآخر"))
                    }
                    if turnIndex == 0 {
                        Text(scenario.openingLineAr).foregroundStyle(.secondary)
                    }
                }

                if isFinished {
                    resultCard
                } else if let turn = currentTurn {
                    InfoCard(title: L("مهمتك"), systemImage: "target") {
                        Text(L(turn.promptAr)).font(.headline)
                        Text(L("عبّر بطريقتك. ليس مطلوبًا أن تطابق النموذج كلمةً بكلمة."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TextField(L("اكتب ردك بالإنجليزية"), text: $response, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...7)
                        .environment(\.layoutDirection, .leftToRight)
                        .disabled(evaluation != nil)

                    HStack {
                        Button {
                            Task {
                                if speechService.state == .listening {
                                    speechService.stop()
                                    response = speechService.transcript
                                } else {
                                    await speechService.start(
                                        localeIdentifier: settings.accentVariant.localeIdentifier
                                    )
                                }
                            }
                        } label: {
                            Label(
                                speechService.state == .listening ? L("إيقاف التسجيل") : L("الإجابة بالصوت"),
                                systemImage: "mic.fill"
                            )
                        }
                        .buttonStyle(.bordered)

                        Button {
                            container.textToSpeech.speak(
                                turn.sampleAnswer,
                                accent: settings.accentVariant,
                                rate: Float(settings.speechRate)
                            )
                        } label: {
                            Label(L("سماع مثال"), systemImage: "ear.fill")
                        }
                        .buttonStyle(.bordered)
                    }

                    if let evaluation {
                        InfoCard(
                            title: L("مراجعة الإجابة"),
                            systemImage: evaluation.score >= 0.8 ? "checkmark.seal.fill" : "lightbulb.fill"
                        ) {
                            AccessibleProgressView(
                                title: Lf("تغطية الأفكار %@٪", "\(Int(evaluation.score * 100))"),
                                value: evaluation.score
                            )
                            Text(evaluation.feedbackAr)
                            if !evaluation.matchedIdeas.isEmpty {
                                Text(Lf("أفكار ظهرت في إجابتك: %@", "\(evaluation.matchedIdeas.joined(separator: "، "))"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Divider()
                            Text(L("مثال لإجابة ممكنة"))
                                .font(.caption.bold())
                            Text(turn.sampleAnswer)
                                .environment(\.layoutDirection, .leftToRight)
                        }
                    }

                    PrimaryButton(
                        title: evaluation == nil ? L("مراجعة الرد") : L("متابعة الحوار"),
                        systemImage: evaluation == nil ? "checkmark.circle.fill" : "arrow.forward.circle.fill",
                        isDisabled: response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        if evaluation == nil { evaluate(turn) } else { advance() }
                    }
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle(scenario.level.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: speechService.transcript) { _, newValue in
            if speechService.state == .listening { response = newValue }
        }
    }

    private var responseLine: String {
        guard turnIndex > 0 else { return scenario.openingLine }
        let prior = scenario.turns[min(turnIndex - 1, scenario.turns.count - 1)]
        let score = completedScores.last ?? 0
        return score >= 0.45 ? prior.responseOnSuccess : prior.responseOnRetry
    }

    private var resultCard: some View {
        let average = completedScores.isEmpty ? 0 : completedScores.reduce(0, +) / Double(completedScores.count)
        return InfoCard(title: L("اكتملت المحادثة"), systemImage: "flag.checkered") {
            AccessibleProgressView(
                title: Lf("النتيجة العامة %@٪", "\(Int(average * 100))"),
                value: average
            )
            Text(
                average >= 0.8
                    ? L("وصلت أفكارك بوضوح في معظم الموقف.")
                    : L("أكملت الموقف. راجع الملاحظات ثم أعده وحاول تغطية الأفكار التي فاتتك.")
            )
            Button(L("إعادة المحادثة")) {
                turnIndex = 0
                response = ""
                evaluation = nil
                completedScores = []
                isFinished = false
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func evaluate(_ turn: ConversationTurn) {
        let result = ConversationLibrary.evaluate(response, for: turn)
        evaluation = result
        Task {
            await container.progressRepository.recordSkill(
                .practicalCommunication,
                correct: result.score >= 0.6,
                at: .now
            )
            let entry = ConversationMemoryEntry(
                id: UUID().uuidString,
                scenarioID: scenario.id,
                scenarioTitle: scenario.titleAr,
                transcript: response,
                reply: result.feedbackAr,
                score: result.score,
                createdAt: .now
            )
            await container.learningMemoryRepository.recordConversation(entry)
            if result.score < 0.55 {
                let mistake = LearningMistake(
                    id: UUID().uuidString,
                    category: L("المحادثة"),
                    source: scenario.titleAr,
                    prompt: turn.promptAr,
                    learnerAnswer: response,
                    correction: turn.sampleAnswer,
                    explanationAr: result.feedbackAr,
                    createdAt: .now,
                    reviewCount: 0,
                    resolved: false
                )
                await container.learningMemoryRepository.recordMistake(mistake)
            }
        }
    }

    private func advance() {
        guard let evaluation else { return }
        completedScores.append(evaluation.score)
        if turnIndex + 1 >= scenario.turns.count {
            isFinished = true
        } else {
            turnIndex += 1
            response = ""
            self.evaluation = nil
        }
    }
}

// MARK: - Voice conversation

struct VoiceCoachView: View {
    @EnvironmentObject private var session: UserSession
    @EnvironmentObject private var settings: AppSettings

    private var recommended: [ConversationScenario] {
        let exact = ConversationLibrary.scenarios.filter { $0.level == session.selectedLevel }
        return exact.isEmpty ? ConversationLibrary.scenarios : exact
    }

    var body: some View {
        List {
            Section {
                Text(L("في كل جولة تسمع سؤالًا، تجيب بصوتك، ثم ترى تقييمًا تقريبيًا للكلام وملاحظات على محتوى الإجابة. وإذا كان المدرّب عبر الإنترنت متاحًا، يمكنه متابعة الحوار برد جديد."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section(L("إعداد الجلسة")) {
                Picker(L("اللكنة"), selection: $settings.accentVariant) {
                    ForEach(AccentVariant.allCases) { accent in
                        Text(L(accent.titleAr)).tag(accent)
                    }
                }
                Toggle(L("اقرأ سؤال المحادثة تلقائيًا"), isOn: $settings.autoSpeakCoachPrompts)
            }

            Section(Lf("مناسب لمستواك %@", "\(session.selectedLevel.rawValue)")) {
                ForEach(recommended) { scenario in
                    NavigationLink {
                        VoiceCoachSessionView(scenario: scenario)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(L(scenario.titleAr)).font(.headline)
                            Text(scenario.titleEn)
                                .environment(\.layoutDirection, .leftToRight)
                            Text(Lf("%@ جولات • %@", "\(scenario.turns.count)", "\(scenario.roleAr)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(L("جميع المستويات")) {
                ForEach(ConversationLibrary.scenarios.filter { !recommended.contains($0) }) { scenario in
                    NavigationLink("\(scenario.level.rawValue) • \(scenario.titleAr)") {
                        VoiceCoachSessionView(scenario: scenario)
                    }
                }
            }
        }
        .navigationTitle(L("المحادثة بالصوت"))
    }
}

private struct VoiceCoachSessionView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var speechService: SpeechService
    let scenario: ConversationScenario

    @State private var turnIndex = 0
    @State private var partnerLine = ""
    @State private var transcript = ""
    @State private var report: PronunciationReport?
    @State private var ideaEvaluation: ConversationEvaluation?
    @State private var coachReply: VoiceCoachReply?
    @State private var scores: [Double] = []
    @State private var isEvaluating = false
    @State private var isFinished = false
    @State private var statusMessage: String?

    private var turn: ConversationTurn? {
        scenario.turns.indices.contains(turnIndex) ? scenario.turns[turnIndex] : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L(scenario.titleAr)).font(.largeTitle.bold())
                Text(scenario.roleAr).foregroundStyle(.secondary)
                AccessibleProgressView(
                    title: Lf("الجولة %@ من %@", "\(min(turnIndex + 1, scenario.turns.count))", "\(scenario.turns.count)"),
                    value: scenario.turns.isEmpty ? 0 : Double(turnIndex) / Double(scenario.turns.count)
                )

                coachCard

                if isFinished {
                    completionCard
                } else if let turn {
                    activeTurnView(turn)
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle(L(settings.accentVariant.titleAr))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            partnerLine = scenario.openingLine
            if settings.autoSpeakCoachPrompts { speakPartnerLine() }
        }
        .onChange(of: speechService.transcript) { _, newValue in
            if speechService.state == .listening { transcript = newValue }
        }
        .onDisappear {
            speechService.stop()
            container.textToSpeech.stop()
        }
    }

    @ViewBuilder
    private var coachCard: some View {
        InfoCard(title: L("الطرف الآخر"), systemImage: "waveform.circle.fill") {
            Text(partnerLine.isEmpty ? scenario.openingLine : partnerLine)
                .font(.title3)
                .environment(\.layoutDirection, .leftToRight)
            HStack {
                Button(L("استمع")) { speakPartnerLine() }
                    .buttonStyle(.bordered)
                if let source = coachReply?.source {
                    Text(source == "remote" || source == "server" ? L("رد من المدرّب عبر الإنترنت") : L("رد محلي"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if settings.showArabicCoachHints, let translation = coachReply?.translationAr {
                Text(translation).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func activeTurnView(_ turn: ConversationTurn) -> some View {
        InfoCard(title: L("مهمتك"), systemImage: "target") {
            Text(L(turn.promptAr)).font(.headline)
            Text(L("مثال تستخدمه المقارنة الصوتية"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(turn.sampleAnswer)
                .environment(\.layoutDirection, .leftToRight)
            Button(L("سماع المثال")) {
                container.textToSpeech.speak(
                    turn.sampleAnswer,
                    accent: settings.accentVariant,
                    rate: Float(settings.speechRate)
                )
            }
        }

        TextField(L("سيظهر كلامك هنا، ويمكنك تعديله قبل التقييم"), text: $transcript, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(3...8)
            .environment(\.layoutDirection, .leftToRight)
            .disabled(isEvaluating || report != nil)

        HStack {
            Button {
                Task { await toggleRecording() }
            } label: {
                Label(
                    speechService.state == .listening ? L("إيقاف التسجيل") : L("ابدأ الإجابة"),
                    systemImage: speechService.state == .listening ? "stop.circle.fill" : "mic.circle.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(isEvaluating || report != nil)

            if speechService.state == .listening {
                Text(L("يستمع الآن"))
                    .font(.caption.bold())
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }

        if isEvaluating {
            ProgressView(L("جارٍ تحليل الرد"))
        }
        if let statusMessage {
            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if let report, let ideaEvaluation {
            pronunciationReportCard(report, ideaEvaluation: ideaEvaluation)
        }

        if let coachReply {
            InfoCard(title: L("ملاحظة المدرّب"), systemImage: "brain.head.profile") {
                Text(coachReply.feedbackAr)
                if let suggestion = coachReply.suggestedAnswer {
                    Text(L("صياغة مقترحة"))
                        .font(.caption.bold())
                    Text(suggestion)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
        }

        PrimaryButton(
            title: report == nil ? L("تحليل الرد") : L("الجولة التالية"),
            systemImage: report == nil ? "waveform.path.ecg" : "arrow.forward.circle.fill",
            isDisabled: transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isEvaluating
        ) {
            if report == nil {
                Task { await evaluateCurrentTurn(turn) }
            } else {
                advance()
            }
        }
    }

    private var completionCard: some View {
        let average = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
        return InfoCard(title: L("اكتملت جلسة المحادثة"), systemImage: "checkmark.seal.fill") {
            AccessibleProgressView(
                title: Lf("متوسط الجلسة %@٪", "\(Int(average * 100))"),
                value: average
            )
            Text(
                average >= 0.82
                    ? L("كان كلامك واضحًا وغطيت معظم المطلوب.")
                    : L("راجع الكلمات والملاحظات المسجلة ثم أعد الموقف عندما تكون جاهزًا.")
            )
            Button(L("إعادة الجلسة")) { resetSession() }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func pronunciationReportCard(
        _ report: PronunciationReport,
        ideaEvaluation: ConversationEvaluation
    ) -> some View {
        InfoCard(title: L("مراجعة الكلام"), systemImage: "chart.bar.doc.horizontal.fill") {
            AccessibleProgressView(
                title: Lf("النتيجة الكلية %@٪", "\(Int(report.overall * 100))"),
                value: report.overall
            )
            LabeledContent(L("دقة الكلمات"), value: "\(Int(report.accuracy * 100))٪")
            LabeledContent(L("اكتمال الجملة"), value: "\(Int(report.completeness * 100))٪")
            LabeledContent(L("الطلاقة"), value: "\(Int(report.fluency * 100))٪")
            LabeledContent(L("السرعة"), value: Lf("%@ كلمة في الدقيقة", "\(Int(report.wordsPerMinute))"))
            LabeledContent(L("تغطية أفكار الموقف"), value: "\(Int(ideaEvaluation.score * 100))٪")
            Text(L("هذه نتيجة تدريبية تقريبية تعتمد على النص الذي تعرّف إليه النظام والتوقيت والثقة، ولا تقيس مخارج الحروف قياسًا مخبريًا."))
                .font(.caption)
                .foregroundStyle(.secondary)

            if !report.needsPractice.isEmpty {
                Divider()
                Text(L("كلمات تستحق إعادة المحاولة")).font(.headline)
                ForEach(report.needsPractice.prefix(8)) { word in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Image(systemName: word.issue.systemImage).accessibilityHidden(true)
                            Text(word.expected.isEmpty ? word.recognized ?? "" : word.expected)
                                .font(.headline)
                                .environment(\.layoutDirection, .leftToRight)
                            Spacer()
                            Text(L(word.issue.titleAr)).font(.caption.bold())
                        }
                        if let recognized = word.recognized, recognized != word.expected {
                            Text(Lf("تعرّف إليه النظام على أنه: %@", "\(recognized)"))
                                .font(.caption)
                                .environment(\.layoutDirection, .leftToRight)
                        }
                        if let tip = word.tipAr {
                            Text(tip).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            ForEach(report.tipsAr, id: \.self) { tip in
                Label(tip, systemImage: "lightbulb.fill")
                    .font(.subheadline)
            }
        }
    }

    private func speakPartnerLine() {
        let line = partnerLine.isEmpty ? scenario.openingLine : partnerLine
        container.textToSpeech.speak(
            line,
            accent: settings.accentVariant,
            rate: Float(settings.speechRate)
        )
    }

    private func toggleRecording() async {
        if speechService.state == .listening {
            speechService.stop()
            transcript = speechService.transcript
        } else {
            container.textToSpeech.stop()
            speechService.resetTranscript()
            await speechService.start(localeIdentifier: settings.accentVariant.localeIdentifier)
        }
    }

    private func evaluateCurrentTurn(_ turn: ConversationTurn) async {
        speechService.stop()
        isEvaluating = true
        statusMessage = nil
        defer { isEvaluating = false }

        let localReport = PronunciationAnalyzer.analyze(
            target: turn.sampleAnswer,
            recognized: transcript,
            accent: settings.accentVariant,
            duration: speechService.elapsedTime,
            segments: speechService.segments
        )
        let localIdeas = ConversationLibrary.evaluate(transcript, for: turn)
        report = localReport
        ideaEvaluation = localIdeas
        let combinedScore = localReport.overall * 0.65 + localIdeas.score * 0.35
        scores.append(combinedScore)

        let memory = await container.learningMemoryRepository.snapshot()
        let request = VoiceCoachRequest(
            sessionID: "voice-\(scenario.id)",
            scenarioID: scenario.id,
            level: scenario.level,
            accent: settings.accentVariant,
            prompt: partnerLine,
            learnerTranscript: transcript,
            localScore: combinedScore,
            previousTurns: Array(
                memory.conversations
                    .filter { $0.scenarioID == scenario.id }
                    .prefix(6)
            )
        )

        do {
            coachReply = try await container.voiceCoachRepository.reply(to: request)
            partnerLine = coachReply?.reply ?? turn.responseOnSuccess
        } catch {
            statusMessage = Lf("تعذر إنشاء رد جديد: %@", "\(error.localizedDescription)")
            partnerLine = combinedScore >= 0.55 ? turn.responseOnSuccess : turn.responseOnRetry
        }

        await container.learningMemoryRepository.recordPronunciation(localReport)
        await container.learningMemoryRepository.recordConversation(.init(
            id: UUID().uuidString,
            scenarioID: scenario.id,
            scenarioTitle: scenario.titleAr,
            transcript: transcript,
            reply: partnerLine,
            score: combinedScore,
            createdAt: .now
        ))
        await container.progressRepository.recordSkill(
            .practicalCommunication,
            correct: combinedScore >= 0.68,
            at: .now
        )

        for weakWord in localReport.needsPractice.prefix(3) where !weakWord.expected.isEmpty {
            await container.learningMemoryRepository.recordMistake(.init(
                id: UUID().uuidString,
                category: L("النطق"),
                source: scenario.titleAr,
                prompt: weakWord.expected,
                learnerAnswer: weakWord.recognized ?? L("لم تُلتقط"),
                correction: weakWord.expected,
                explanationAr: weakWord.tipAr ?? L("قل الكلمة وحدها أولًا، ثم ضعها داخل الجملة."),
                createdAt: .now,
                reviewCount: 0,
                resolved: false
            ))
        }

        if localIdeas.score < 0.5 {
            await container.learningMemoryRepository.recordMistake(.init(
                id: UUID().uuidString,
                category: L("المحادثة"),
                source: scenario.titleAr,
                prompt: turn.promptAr,
                learnerAnswer: transcript,
                correction: turn.sampleAnswer,
                explanationAr: localIdeas.feedbackAr,
                createdAt: .now,
                reviewCount: 0,
                resolved: false
            ))
        }
    }

    private func advance() {
        if turnIndex + 1 >= scenario.turns.count {
            isFinished = true
            if settings.autoSpeakCoachPrompts { speakPartnerLine() }
            return
        }
        turnIndex += 1
        transcript = ""
        report = nil
        ideaEvaluation = nil
        coachReply = nil
        statusMessage = nil
        speechService.resetTranscript()
        if settings.autoSpeakCoachPrompts { speakPartnerLine() }
    }

    private func resetSession() {
        turnIndex = 0
        partnerLine = scenario.openingLine
        transcript = ""
        report = nil
        ideaEvaluation = nil
        coachReply = nil
        scores = []
        isFinished = false
        statusMessage = nil
        speechService.resetTranscript()
        if settings.autoSpeakCoachPrompts { speakPartnerLine() }
    }
}
