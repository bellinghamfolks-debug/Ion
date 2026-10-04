import SwiftUI

/// Entry screen for the full mock: pick a section and optional extra time.
struct MockExamHubView: View {
    @State private var extraTime = false

    var body: some View {
        List {
            Section {
                Text(LE("محاكاة كاملة بتوقيت حقيقي: 40 سؤالًا، بلا تصحيح حتى النهاية، ثم Band تقريبي ومراجعة لكل إجابة.",
                        "A full timed mock: 40 questions, no feedback until the end, then an approximate band and a review of every answer."))
                    .foregroundStyle(.secondary)
                Toggle(LE("وقت إضافي 25٪", "25% extra time"), isOn: $extraTime)
                Text(LE("ترتيب شائع لذوي الإعاقة في الاختبارات الرسمية. استخدمه إن كنت ستطلبه في اختبارك الحقيقي.",
                        "A common access arrangement in official tests. Use it if you will request it for your real exam."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(LE("اختر القسم", "Choose a section")) {
                ForEach([IELTSSection.listening, .reading], id: \.self) { section in
                    let exam = MockExamSection.ielts(section)
                    NavigationLink {
                        MockExamView(exam: exam, extraTime: extraTime)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section == .listening ? "IELTS Listening" : "IELTS Academic Reading")
                                .font(.headline)
                            Text(LfE("%@ سؤالًا • %@ دقيقة", "%@ questions • %@ minutes",
                                     "\(exam.questions.count)", "\(exam.minutes(extraTime: extraTime))"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(LE("اختبار تجريبي كامل", "Full mock test"))
    }
}

struct MockExamView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var textToSpeech: TextToSpeechService
    @Environment(\.dismiss) private var dismiss

    let exam: MockExamSection
    let extraTime: Bool

    @State private var started = false
    @State private var moduleIndex = 0
    @State private var answers: [String: String] = [:]
    @State private var startedAt = Date()
    @State private var now = Date()
    @State private var result: MockExamResult?
    @State private var showSubmitConfirm = false
    @State private var showExitConfirm = false
    @State private var announced: Set<Int> = []
    @State private var playCounts: [String: Int] = [:]

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var deadline: Date { startedAt.addingTimeInterval(Double(exam.minutes(extraTime: extraTime)) * 60) }
    private var secondsLeft: Int { max(0, Int(deadline.timeIntervalSince(now))) }

    var body: some View {
        Group {
            if let result {
                resultView(result)
            } else if started {
                examView
            } else {
                intro
            }
        }
        .screenBackground()
        .navigationTitle(exam.section == .listening ? "IELTS Listening" : "IELTS Reading")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(started && result == nil)
        .toolbar {
            if started && result == nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showExitConfirm = true } label: { Label(LE("خروج", "Exit"), systemImage: "xmark") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text(timeText)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(secondsLeft < 300 ? AppTheme.streak : .primary)
                        .accessibilityLabel(LfE("الوقت المتبقي %@", "Time left %@", spokenTime))
                }
            }
        }
        .onReceive(ticker) { value in
            guard started, result == nil else { return }
            now = value
            let minutesLeft = Int(ceil(Double(secondsLeft) / 60))
            if MockExamEngine.announcementMarks.contains(minutesLeft), !announced.contains(minutesLeft), secondsLeft > 0 {
                announced.insert(minutesLeft)
                AccessibilityNotification.Announcement(LfE("بقي %@ دقائق", "%@ minutes left", "\(minutesLeft)")).post()
            }
            if secondsLeft == 0 { finish() }
        }
        .accessibilityAction(.escape) { if started && result == nil { showExitConfirm = true } else { dismiss() } }
        .alert(LE("إنهاء الاختبار وتسليمه؟", "Finish and submit the test?"), isPresented: $showSubmitConfirm) {
            Button(LE("متابعة الحل", "Keep working"), role: .cancel) {}
            Button(LE("تسليم", "Submit")) { finish() }
        } message: {
            Text(LfE("أجبت عن %@ من %@ سؤالًا.", "You answered %@ of %@ questions.", "\(answeredCount)", "\(exam.questions.count)"))
        }
        .alert(LE("الخروج من الاختبار؟", "Leave the test?"), isPresented: $showExitConfirm) {
            Button(LE("متابعة", "Continue"), role: .cancel) {}
            Button(LE("خروج بلا حفظ", "Leave without saving"), role: .destructive) { textToSpeech.stop(); dismiss() }
        }
        .onDisappear { textToSpeech.stop() }
    }

    // MARK: - Intro

    private var intro: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(exam.section == .listening ? "IELTS Listening" : "IELTS Academic Reading")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                InfoCard(title: LE("قبل أن تبدأ", "Before you start"), systemImage: "checklist") {
                    Label(LfE("%@ سؤالًا في %@ أقسام", "%@ questions in %@ parts", "\(exam.questions.count)", "\(exam.modules.count)"), systemImage: "list.number")
                    Label(LfE("المدة %@ دقيقة", "%@ minutes", "\(exam.minutes(extraTime: extraTime))"), systemImage: "timer")
                    Label(LE("لا يظهر التصحيح إلا بعد التسليم", "Answers are marked only after you submit"), systemImage: "eye.slash")
                    if exam.section == .listening {
                        Label(LE("في الاختبار الحقيقي تسمع كل مقطع مرة واحدة. هنا يمكنك الإعادة، لكن حاول ألا تفعل.",
                                 "In the real test you hear each recording once. You can replay here, but try not to."),
                              systemImage: "headphones")
                    }
                    Label(LE("يعلن VoiceOver الوقت عند بقاء 10 و5 ودقيقة واحدة", "VoiceOver announces the time at 10, 5 and 1 minutes left"), systemImage: "speaker.wave.2")
                }
                PrimaryButton(title: LE("ابدأ الاختبار", "Start the test"), systemImage: "play.fill") {
                    startedAt = .now
                    now = .now
                    started = true
                }
            }
            .padding(AppTheme.screenPadding)
        }
    }

    // MARK: - Exam

    private var module: IELTSObjectiveModule { exam.modules[moduleIndex] }
    private var answeredCount: Int { exam.questions.filter { !(answers[$0.id] ?? "").isEmpty }.count }

    private var examView: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(answeredCount), total: Double(max(exam.questions.count, 1)))
                .tint(AppTheme.brand)
                .padding(.horizontal)
                .accessibilityLabel(LfE("أجبت عن %@ من %@", "Answered %@ of %@", "\(answeredCount)", "\(exam.questions.count)"))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(LfE("الجزء %@ من %@", "Part %@ of %@", "\(moduleIndex + 1)", "\(exam.modules.count)"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(L(module.titleAr))
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    source
                    ForEach(Array(module.questions.enumerated()), id: \.element.id) { offset, question in
                        questionCard(question, number: questionNumber(offset))
                    }
                }
                .padding(AppTheme.screenPadding)
            }
            navigationBar
        }
    }

    @ViewBuilder
    private var source: some View {
        if exam.section == .reading {
            InfoCard(title: L("النص الأكاديمي"), systemImage: "book.pages.fill") {
                Text(module.sourceText)
                    .lineSpacing(6)
                    .environment(\.layoutDirection, .leftToRight)
                    .textSelection(.enabled)
            }
        } else {
            InfoCard(title: L("المقطع الصوتي"), systemImage: "headphones") {
                Button {
                    playCounts[module.id, default: 0] += 1
                    textToSpeech.speak(module.sourceText, accent: settings.accentVariant, rate: Float(settings.speechRate))
                } label: {
                    Label((playCounts[module.id] ?? 0) == 0 ? L("تشغيل المقطع") : LfE("إعادة المقطع (%@)", "Replay (%@)", "\(playCounts[module.id] ?? 0)"),
                          systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func questionNumber(_ offset: Int) -> Int {
        exam.modules.prefix(moduleIndex).reduce(0) { $0 + $1.questions.count } + offset + 1
    }

    private func questionCard(_ question: ComprehensionQuestion, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(number). \(question.prompt)")
                .font(.headline)
                .environment(\.layoutDirection, .leftToRight)
            ForEach(question.choices, id: \.self) { choice in
                let selected = answers[question.id] == choice
                Button {
                    answers[question.id] = choice
                } label: {
                    HStack {
                        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                            .accessibilityHidden(true)
                        Text(choice).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .frame(minHeight: 48)
                    .background(selected ? AppTheme.brand.opacity(0.14) : Color(uiColor: .secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(14)
        .background(AppTheme.cardSurface, in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius))
    }

    private var navigationBar: some View {
        HStack(spacing: 12) {
            Button {
                textToSpeech.stop()
                moduleIndex -= 1
            } label: {
                Label(LE("السابق", "Previous"), systemImage: "chevron.backward")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered)
            .disabled(moduleIndex == 0)

            if moduleIndex + 1 < exam.modules.count {
                Button {
                    textToSpeech.stop()
                    moduleIndex += 1
                } label: {
                    Label(LE("التالي", "Next"), systemImage: "chevron.forward")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button { showSubmitConfirm = true } label: {
                    Label(LE("تسليم", "Submit"), systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.success)
            }
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Result

    private func resultView(_ result: MockExamResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 6) {
                    Text(String(format: "%.1f", result.band))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                    Text(LE("Band تقريبي", "Approximate band"))
                        .foregroundStyle(.secondary)
                    Text(LfE("%@ من %@ صحيحة • %@ دقيقة", "%@ of %@ correct • %@ min", "\(result.correct)", "\(result.total)", "\(result.minutesUsed)"))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)

                Text(LE("التحويل إلى Band تقريبي لأن الحدود الرسمية تختلف قليلًا بين النسخ.",
                        "The band is approximate because official cut-offs vary slightly between versions."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                InfoCard(title: LE("حسب الجزء", "By part"), systemImage: "chart.bar.fill") {
                    ForEach(result.modules) { item in
                        AccessibleProgressView(title: "\(L(item.titleAr)): \(item.correct)/\(item.total)",
                                               value: Double(item.correct) / Double(max(item.total, 1)))
                    }
                }

                InfoCard(title: LE("راجع إجاباتك", "Review your answers"), systemImage: "checkmark.circle") {
                    ForEach(exam.questions) { question in
                        let mine = answers[question.id] ?? ""
                        let right = mine == question.answer
                        VStack(alignment: .leading, spacing: 4) {
                            Label(question.prompt, systemImage: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(right ? AppTheme.success : AppTheme.streak)
                                .environment(\.layoutDirection, .leftToRight)
                            if !right {
                                Text(LfE("إجابتك: %@ • الصحيحة: %@", "Yours: %@ • Correct: %@",
                                         mine.isEmpty ? LE("بلا إجابة", "none") : mine, question.answer))
                                    .font(.caption)
                                Text(question.explanationAr).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        Divider()
                    }
                }

                PrimaryButton(title: LE("إنهاء", "Done"), systemImage: "checkmark") { dismiss() }
            }
            .padding(AppTheme.screenPadding)
        }
    }

    // MARK: - Helpers

    private var timeText: String { String(format: "%02d:%02d", secondsLeft / 60, secondsLeft % 60) }

    private var spokenTime: String {
        LfE("%@ دقيقة و%@ ثانية", "%@ minutes %@ seconds", "\(secondsLeft / 60)", "\(secondsLeft % 60)")
    }

    private func finish() {
        guard result == nil else { return }
        textToSpeech.stop()
        let minutes = Int(ceil(Date().timeIntervalSince(startedAt) / 60))
        let graded = MockExamEngine.grade(exam, answers: answers, minutesUsed: minutes)
        result = graded
        FeedbackSoundEngine.shared.play(.lessonComplete)
        AccessibilityNotification.Announcement(LfE("انتهى الاختبار. Band تقريبي %@", "Test finished. Approximate band %@",
                                                   String(format: "%.1f", graded.band))).post()
        Task {
            await container.progressRepository.recordPracticeSession(PracticeSessionRecord(
                id: graded.sessionID(day: .now),
                domain: exam.section == .listening ? .listening : .reading,
                sourceID: exam.section == .listening ? "ielts-full-listening" : "ielts-full-reading",
                titleAr: exam.section == .listening ? "IELTS Listening 40" : "IELTS Academic Reading 40",
                level: .b2,
                score: graded.score,
                minutes: graded.minutesUsed,
                createdAt: .now,
                details: ["\(graded.correct)/\(graded.total)", "Band \(graded.band)", extraTime ? "extra-time" : "standard-time"]
            ))
        }
    }
}
