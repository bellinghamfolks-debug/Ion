import SwiftUI

struct ConversationStudioView: View {
    @EnvironmentObject private var session: UserSession

    var body: some View {
        List {
            Section(L("المدرب الصوتي الجديد")) {
                NavigationLink {
                    VoiceCoachView()
                } label: {
                    Label(L("محادثة صوتية ذكية"), systemImage: "waveform.badge.mic")
                }
                Text(L("يحاورك التطبيق، يحلل الرد كلمة بكلمة، ويحفظ الكلمات والأخطاء المتكررة في ذاكرتك التعليمية."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text(L("تدرّب على موقف كامل بالكتابة أو الصوت. يعمل التقييم الأساسي محليًا، ويبحث عن الأفكار المهمة لا عن التطابق الحرفي فقط."))
                    .font(.subheadline).foregroundStyle(.secondary)
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
                                    Text(scenario.titleEn).environment(\.layoutDirection, .leftToRight)
                                    Text(scenario.roleAr).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L("استوديو المحادثة"))
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
                        Text(line).font(.title3).environment(\.layoutDirection, .leftToRight)
                        Spacer()
                        Button { container.textToSpeech.speak(line, accent: settings.accentVariant, rate: Float(settings.speechRate)) } label: {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        .accessibilityLabel(L("نطق كلام الطرف الآخر"))
                    }
                    if turnIndex == 0 { Text(scenario.openingLineAr).foregroundStyle(.secondary) }
                }

                if isFinished {
                    resultCard
                } else if let turn = currentTurn {
                    InfoCard(title: L("مهمتك"), systemImage: "target") {
                        Text(L(turn.promptAr)).font(.headline)
                        Text(L("لا يلزم أن تطابق النموذج حرفيًا. عبّر بطريقتك واذكر الفكرة الأساسية."))
                            .font(.caption).foregroundStyle(.secondary)
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
                                    await speechService.start(localeIdentifier: settings.accentVariant.localeIdentifier)
                                }
                            }
                        } label: {
                            Label(speechService.state == .listening ? L("إيقاف التسجيل") : L("الإجابة بالصوت"), systemImage: "mic.fill")
                        }
                        .buttonStyle(.bordered)
                        Button {
                            container.textToSpeech.speak(turn.sampleAnswer, accent: settings.accentVariant, rate: Float(settings.speechRate))
                        } label: {
                            Label(L("سماع نموذج"), systemImage: "ear.fill")
                        }
                        .buttonStyle(.bordered)
                    }

                    if let evaluation {
                        InfoCard(title: L("تقييم محلي"), systemImage: evaluation.score >= 0.8 ? "checkmark.seal.fill" : "lightbulb.fill") {
                            AccessibleProgressView(title: Lf("اكتمال الأفكار %@٪", "\(Int(evaluation.score * 100))"), value: evaluation.score)
                            Text(evaluation.feedbackAr)
                            if !evaluation.matchedIdeas.isEmpty {
                                Text(Lf("الأفكار التي التقطها التقييم: %@", "\(evaluation.matchedIdeas.joined(separator: "، "))"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Divider()
                            Text(L("نموذج ممكن:")).font(.caption.bold())
                            Text(turn.sampleAnswer).environment(\.layoutDirection, .leftToRight)
                        }
                    }

                    PrimaryButton(
                        title: evaluation == nil ? L("تقييم الرد") : L("متابعة الحوار"),
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
            AccessibleProgressView(title: Lf("النتيجة العامة %@٪", "\(Int(average * 100))"), value: average)
            Text(average >= 0.8 ? L("أدرت الموقف بوضوح وثقة.") : L("أنهيت الموقف. أعده مرة أخرى وحاول إدخال الأفكار التي ظهرت في النماذج."))
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
            await container.progressRepository.recordSkill(.practicalCommunication, correct: result.score >= 0.6, at: .now)
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

// MARK: - Voice Coach

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
                Text(L("جلسة صوتية متدرجة: استمع، أجب، ثم راجع الدقة والاكتمال والطلاقة والكلمات التي تحتاج تدريبًا. يمكن للخادم الاختياري توليد رد سياقي، وإلا يعمل المدرب المحلي."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section(L("إعداد الجلسة")) {
                Picker(L("اللكنة"), selection: $settings.accentVariant) {
                    ForEach(AccentVariant.allCases) { accent in
                        Text(L(accent.titleAr)).tag(accent)
                    }
                }
                Toggle(L("نطق سؤال المدرب تلقائيًا"), isOn: $settings.autoSpeakCoachPrompts)
            }

            Section(Lf("مناسب لمستواك %@", "\(session.selectedLevel.rawValue)")) {
                ForEach(recommended) { scenario in
                    NavigationLink {
                        VoiceCoachSessionView(scenario: scenario)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(L(scenario.titleAr)).font(.headline)
                            Text(scenario.titleEn).environment(\.layoutDirection, .leftToRight)
                            Text(Lf("%@ جولات • %@", "\(scenario.turns.count)", "\(scenario.roleAr)"))
                                .font(.caption).foregroundStyle(.secondary)
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
        .navigationTitle(L("المدرب الصوتي"))
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
        InfoCard(title: L("المدرب"), systemImage: "waveform.circle.fill") {
            Text(partnerLine.isEmpty ? scenario.openingLine : partnerLine)
                .font(.title3)
                .environment(\.layoutDirection, .leftToRight)
            HStack {
                Button(L("استمع")) { speakPartnerLine() }
                    .buttonStyle(.bordered)
                Text(coachReply?.source == "remote" ? L("رد عبر الإنترنت") : L("رد محلي أو احتياطي"))
                    .font(.caption).foregroundStyle(.secondary)
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
            Text(L("النموذج المستخدم للمقارنة الصوتية:"))
                .font(.caption).foregroundStyle(.secondary)
            Text(turn.sampleAnswer)
                .environment(\.layoutDirection, .leftToRight)
            Button(L("سماع نموذج الإجابة")) {
                container.textToSpeech.speak(turn.sampleAnswer, accent: settings.accentVariant, rate: Float(settings.speechRate))
            }
        }

        TextField(L("سيظهر ردك هنا، ويمكنك تعديله قبل التقييم"), text: $transcript, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(3...8)
            .environment(\.layoutDirection, .leftToRight)
            .disabled(isEvaluating || report != nil)

        HStack {
            Button {
                Task { await toggleRecording() }
            } label: {
                Label(speechService.state == .listening ? L("إيقاف التسجيل") : L("ابدأ الإجابة"), systemImage: speechService.state == .listening ? "stop.circle.fill" : "mic.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isEvaluating || report != nil)

            if speechService.state == .listening {
                Text(L("يستمع الآن"))
                    .font(.caption.bold())
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }

        if isEvaluating { ProgressView(L("يحلل الرد ويجهز الجولة التالية")) }
        if let statusMessage { Text(statusMessage).font(.caption).foregroundStyle(.secondary) }

        if let report, let ideaEvaluation {
            pronunciationReportCard(report, ideaEvaluation: ideaEvaluation)
        }

        if let coachReply {
            InfoCard(title: L("ملاحظة المدرب"), systemImage: "brain.head.profile") {
                Text(coachReply.feedbackAr)
                if let suggestion = coachReply.suggestedAnswer {
                    Text(L("صياغة مقترحة:")).font(.caption.bold())
                    Text(suggestion).environment(\.layoutDirection, .leftToRight)
                }
            }
        }

        PrimaryButton(
            title: report == nil ? L("حلل الرد") : L("انتقل إلى الجولة التالية"),
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
        return InfoCard(title: L("اكتملت الجلسة الصوتية"), systemImage: "checkmark.seal.fill") {
            AccessibleProgressView(title: Lf("متوسط الجلسة %@٪", "\(Int(average * 100))"), value: average)
            Text(average >= 0.82 ? L("استجابتك واضحة ومتوازنة. انتقل إلى موقف أعلى قليلًا.") : L("اكتملت الجلسة. راجع الكلمات المسجلة في دفتر الأخطاء ثم أعد الموقف."))
            Button(L("إعادة الجلسة")) { resetSession() }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func pronunciationReportCard(_ report: PronunciationReport, ideaEvaluation: ConversationEvaluation) -> some View {
        InfoCard(title: L("تقرير الكلام"), systemImage: "chart.bar.doc.horizontal.fill") {
            AccessibleProgressView(title: Lf("النتيجة الكلية %@٪", "\(Int(report.overall * 100))"), value: report.overall)
            LabeledContent(L("دقة الكلمات"), value: "\(Int(report.accuracy * 100))٪")
            LabeledContent(L("اكتمال الجملة"), value: "\(Int(report.completeness * 100))٪")
            LabeledContent(L("الطلاقة"), value: "\(Int(report.fluency * 100))٪")
            LabeledContent(L("السرعة"), value: Lf("%@ كلمة في الدقيقة", "\(Int(report.wordsPerMinute))"))
            LabeledContent(L("اكتمال أفكار الموقف"), value: "\(Int(ideaEvaluation.score * 100))٪")
            Text(L("التقييم الصوتي هنا يعتمد على تفريغ الكلام وتوقيته وثقة نظام التعرف، وليس فحصًا مخبريًا لمخارج الحروف."))
                .font(.caption).foregroundStyle(.secondary)

            if !report.needsPractice.isEmpty {
                Divider()
                Text(L("كلمات تحتاج انتباهًا")).font(.headline)
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
                            Text(Lf("سمعها النظام: %@", "\(recognized)"))
                                .font(.caption).environment(\.layoutDirection, .leftToRight)
                        }
                        if let tip = word.tipAr { Text(tip).font(.caption).foregroundStyle(.secondary) }
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
        container.textToSpeech.speak(line, accent: settings.accentVariant, rate: Float(settings.speechRate))
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
            previousTurns: Array(memory.conversations.filter { $0.scenarioID == scenario.id }.prefix(6))
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
        await container.progressRepository.recordSkill(.practicalCommunication, correct: combinedScore >= 0.68, at: .now)

        for weakWord in localReport.needsPractice.prefix(3) where !weakWord.expected.isEmpty {
            await container.learningMemoryRepository.recordMistake(.init(
                id: UUID().uuidString,
                category: L("النطق"),
                source: scenario.titleAr,
                prompt: weakWord.expected,
                learnerAnswer: weakWord.recognized ?? L("لم تُلتقط"),
                correction: weakWord.expected,
                explanationAr: weakWord.tipAr ?? L("أعد الكلمة منفردة ثم داخل الجملة."),
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
