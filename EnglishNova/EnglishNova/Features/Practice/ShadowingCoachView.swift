import SwiftUI

/// Pronunciation coach built on shadowing: hear a sentence (normal, then
/// slow), say it straight after, and see which words need work. Recognition
/// runs with Apple's speech service; no recording is uploaded by EnglishNova.
struct ShadowingCoachView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var textToSpeech: TextToSpeechService
    @EnvironmentObject private var session: UserSession

    @State private var sentences: [String] = []
    @State private var index = 0
    @State private var report: PronunciationReport?
    @State private var reports: [PronunciationReport] = []
    @State private var handsFree = true
    @State private var silenceTask: Task<Void, Never>?
    @State private var finished = false
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView(LE("جارٍ اختيار جمل من دروسك", "Picking sentences from your lessons"))
            } else if finished {
                summary
            } else if sentences.indices.contains(index) {
                practice(sentences[index])
            }
        }
        .screenBackground()
        .navigationTitle(LE("مدرّب النطق", "Pronunciation coach"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onDisappear {
            silenceTask?.cancel()
            speechService.stop()
            textToSpeech.stop()
        }
        .onChange(of: speechService.transcript) { _, newValue in
            scheduleAutoStop(after: newValue)
        }
        .onChange(of: speechService.state) { old, new in
            // Analyze as soon as recognition ends, whoever stopped it.
            if old == .listening, new != .listening, !speechService.transcript.isEmpty, report == nil {
                analyze()
            }
        }
    }

    private func practice(_ sentence: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(LfE("الجملة %@ من %@", "Sentence %@ of %@", "\(index + 1)", "\(sentences.count)"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                AccessibleProgressView(title: LE("تقدّم الجلسة", "Session progress"),
                                       value: Double(index) / Double(max(sentences.count, 1)))

                Text(sentence)
                    .font(.title2.bold())
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityAddTraits(.isHeader)

                Text(LE("استمع، ثم قل الجملة مباشرة بعد النموذج كأنك ظلّه. التقليد السريع يدرّب الإيقاع والنبر.",
                        "Listen, then say the sentence right after the model like its shadow. Quick imitation trains rhythm and stress."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { listenButtons(sentence) }
                    VStack(spacing: 10) { listenButtons(sentence) }
                }

                Toggle(LE("إيقاف التسجيل تلقائيًا عند الصمت", "Stop recording automatically on silence"), isOn: $handsFree)

                Button {
                    toggleRecording()
                } label: {
                    Label(speechService.state == .listening ? LE("إيقاف", "Stop") : LE("قل الجملة الآن", "Say it now"),
                          systemImage: speechService.state == .listening ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: AppTheme.minimumTapHeight)
                }
                .buttonStyle(.borderedProminent)
                .tint(speechService.state == .listening ? AppTheme.streak : AppTheme.brand)

                if !speechService.transcript.isEmpty {
                    Text(speechService.transcript)
                        .environment(\.layoutDirection, .leftToRight)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(LfE("سمعتُ: %@", "I heard: %@", speechService.transcript))
                }

                if case .failed(let message) = speechService.state {
                    Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }

                if let report { feedback(report, sentence: sentence) }
            }
            .padding(AppTheme.screenPadding)
        }
        .accessibilityAction(.magicTap) { toggleRecording() }
    }

    @ViewBuilder
    private func listenButtons(_ sentence: String) -> some View {
        Button {
            textToSpeech.speak(sentence, accent: settings.accentVariant, rate: Float(settings.speechRate))
        } label: {
            Label(LE("استمع", "Listen"), systemImage: "speaker.wave.2.fill")
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.bordered)
        Button {
            textToSpeech.speak(sentence, accent: settings.accentVariant, rate: 0.32)
        } label: {
            Label(LE("استمع ببطء", "Listen slowly"), systemImage: "tortoise.fill")
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.bordered)
    }

    private func feedback(_ report: PronunciationReport, sentence: String) -> some View {
        InfoCard(title: LfE("النتيجة %@٪", "Score %@%", "\(Int((report.overall * 100).rounded()))"),
                 systemImage: report.overall >= 0.8 ? "checkmark.seal.fill" : "waveform.badge.exclamationmark",
                 tint: report.overall >= 0.8 ? AppTheme.success : AppTheme.warning) {
            // Each word is a button: tap to hear it alone.
            FlowWords(words: report.words) { word in
                textToSpeech.speak(word, accent: settings.accentVariant, rate: 0.34)
            }
            if let tip = report.tipsAr.first {
                Text(tip).font(.footnote)
            }
            HStack {
                Button(LE("أعد المحاولة", "Try again")) {
                    self.report = nil
                    speechService.resetTranscript()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button(index + 1 < sentences.count ? LE("الجملة التالية", "Next sentence") : LE("إنهاء", "Finish")) {
                    next()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var summary: some View {
        let average = reports.isEmpty ? 0 : reports.map(\.overall).reduce(0, +) / Double(reports.count)
        let weak = Array(Set(reports.flatMap(\.needsPractice).map(\.expected).filter { !$0.isEmpty })).sorted().prefix(8)
        return ScrollView {
            VStack(spacing: 18) {
                CelebrationView(systemImage: "waveform.and.mic", tint: AppTheme.accentTeal, size: 96)
                Text(LfE("متوسط نطقك %@٪", "Your average %@%", "\(Int((average * 100).rounded()))"))
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                if !weak.isEmpty {
                    InfoCard(title: LE("كلمات تستحق تدريبًا", "Words worth practising"), systemImage: "text.word.spacing", tint: AppTheme.warning) {
                        ForEach(Array(weak), id: \.self) { word in
                            Button {
                                textToSpeech.speak(word, accent: settings.accentVariant, rate: 0.34)
                            } label: {
                                Label(word, systemImage: "speaker.wave.2")
                                    .environment(\.layoutDirection, .leftToRight)
                            }
                        }
                        Text(LE("حُفظت هذه الكلمات لتعود إليك في «تدرّب على أخطائك».", "These words are saved to come back in “Practise your mistakes”."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                PrimaryButton(title: LE("جلسة جديدة", "New session"), systemImage: "arrow.clockwise") {
                    reports = []
                    index = 0
                    report = nil
                    finished = false
                    sentences.shuffle()
                }
            }
            .padding(AppTheme.screenPadding)
        }
    }

    // MARK: - Flow

    private func load() async {
        guard isLoading else { return }
        let catalog = try? await container.courseRepository.catalog()
        let progress = await container.progressRepository.snapshot()
        sentences = ShadowingSentencePicker.sentences(catalog: catalog, progress: progress, level: session.selectedLevel)
        isLoading = false
    }

    private func toggleRecording() {
        Task {
            if speechService.state == .listening {
                speechService.stop()
            } else {
                report = nil
                textToSpeech.stop()
                speechService.resetTranscript()
                await speechService.start(localeIdentifier: settings.accentVariant.localeIdentifier)
            }
        }
    }

    private func scheduleAutoStop(after transcript: String) {
        silenceTask?.cancel()
        guard handsFree, speechService.state == .listening, !transcript.isEmpty else { return }
        silenceTask = Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled, speechService.state == .listening, speechService.transcript == transcript else { return }
            speechService.stop()
        }
    }

    private func analyze() {
        guard sentences.indices.contains(index) else { return }
        let value = PronunciationAnalyzer.analyze(
            target: sentences[index],
            recognized: speechService.transcript,
            accent: settings.accentVariant,
            duration: speechService.elapsedTime,
            segments: speechService.segments
        )
        report = value
        reports.append(value)
        AccessibilityNotification.Announcement(LfE("النتيجة %@ بالمئة", "Score %@ percent", "\(Int((value.overall * 100).rounded()))")).post()
        Task {
            await container.learningMemoryRepository.recordPronunciation(value)
            await container.progressRepository.recordSkill(.practicalCommunication, correct: value.overall >= 0.72, at: .now)
            for word in value.needsPractice.prefix(2) where !word.expected.isEmpty {
                await container.learningMemoryRepository.recordMistake(.init(
                    id: UUID().uuidString,
                    category: L("النطق"),
                    source: LE("مدرّب النطق", "Pronunciation coach"),
                    prompt: word.expected,
                    learnerAnswer: word.recognized ?? "",
                    correction: word.expected,
                    explanationAr: word.tipAr ?? LE("قل الكلمة وحدها ببطء، ثم داخل الجملة.", "Say the word slowly on its own, then inside the sentence."),
                    createdAt: .now,
                    reviewCount: 0,
                    resolved: false
                ))
            }
        }
    }

    private func next() {
        speechService.resetTranscript()
        report = nil
        if index + 1 < sentences.count {
            index += 1
        } else {
            finished = true
            FeedbackSoundEngine.shared.play(.success)
            let average = reports.isEmpty ? 0 : reports.map(\.overall).reduce(0, +) / Double(reports.count)
            Task {
                await container.progressRepository.recordPracticeSession(PracticeSessionRecord(
                    id: "shadowing-\(UUID().uuidString)",
                    domain: .speaking,
                    sourceID: "shadowing",
                    titleAr: LE("مدرّب النطق", "Pronunciation coach"),
                    level: session.selectedLevel,
                    score: average,
                    minutes: max(1, reports.count / 2),
                    createdAt: .now,
                    details: sentences
                ))
            }
        }
    }
}

/// Words of a pronunciation report as tappable chips, coloured by result.
private struct FlowWords: View {
    let words: [WordPronunciationResult]
    let onTap: (String) -> Void

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 80), spacing: 8)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(words.filter { $0.issue != .extra }) { word in
                Button {
                    onTap(word.expected)
                } label: {
                    Text(word.expected)
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(color(for: word.issue).opacity(0.16), in: Capsule())
                        .foregroundStyle(color(for: word.issue))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(word.expected), \(word.issue.titleAr)")
                .accessibilityHint(LE("انقر لسماع الكلمة وحدها", "Tap to hear the word alone"))
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func color(for issue: PronunciationIssueKind) -> Color {
        switch issue {
        case .accurate: return AppTheme.success
        case .close: return AppTheme.accentTeal
        case .substituted, .extra: return AppTheme.warning
        case .omitted: return AppTheme.streak
        }
    }
}

/// Picks real sentences from what the learner studied (recent lessons first),
/// topped up from the current level. Pure, so it can be tested.
enum ShadowingSentencePicker {
    static func sentences(catalog: CourseCatalog?, progress: UserProgressSnapshot, level: CEFRLevel, limit: Int = 6) -> [String] {
        let allLessons = catalog?.levels.flatMap { $0.units.flatMap(\.lessons) } ?? []
        let completed = progress.lessons.values
            .filter { $0.completedAt != nil }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            .compactMap { record in allLessons.first { $0.id == record.lessonID } }
        let current = catalog?.levels.first { $0.level == level }?.units.flatMap(\.lessons) ?? []
        var seen = Set<String>()
        var result: [String] = []
        for lesson in completed + current {
            let candidates = lesson.exercises.filter { $0.type == .arrangeWords || $0.type == .speak || $0.type == .translation }
                .map(\.answer) + lesson.vocabulary.map(\.example)
            for sentence in candidates {
                let clean = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                let count = clean.split(separator: " ").count
                let lower = clean.lowercased()
                guard (3...14).contains(count),
                      !lower.contains("key word"), !lower.contains("today’s"), !lower.contains("today's"),
                      clean.range(of: #"[؀-ۿ]"#, options: .regularExpression) == nil,
                      seen.insert(lower).inserted else { continue }
                result.append(clean)
                if result.count >= limit { return result }
            }
        }
        return result.isEmpty ? ["I would like a cup of coffee, please.", "Could you say that again, please?"] : result
    }
}
