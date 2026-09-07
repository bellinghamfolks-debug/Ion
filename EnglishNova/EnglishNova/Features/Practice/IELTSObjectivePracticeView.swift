import Foundation
import SwiftUI

/// IELTS-style objective practice built from original offline material.
/// Reading exposes the complete passage; Listening keeps the transcript hidden
/// until submission and plays it through the learner's selected iOS voice.
struct IELTSObjectivePracticeView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var textToSpeech: TextToSpeechService

    let section: IELTSSection

    @State private var moduleIndex = 0
    @State private var answers: [String: String] = [:]
    @State private var submitted = false
    @State private var replayCount = 0
    @State private var startedAt = Date()
    @State private var isSaving = false

    private var modules: [IELTSObjectiveModule] {
        IELTSObjectiveLibrary.modules(for: section)
    }

    private var module: IELTSObjectiveModule {
        modules[moduleIndex % max(1, modules.count)]
    }

    private var correctCount: Int {
        module.questions.filter { answers[$0.id] == $0.answer }.count
    }

    private var score: Double {
        guard !module.questions.isEmpty else { return 0 }
        return Double(correctCount) / Double(module.questions.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                sourceCard
                ForEach(Array(module.questions.enumerated()), id: \.element.id) { number, question in
                    questionCard(question, number: number + 1)
                }
                resultOrSubmit
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle(section == .listening ? "IELTS Listening" : "IELTS Reading")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { textToSpeech.stop() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L(module.titleAr))
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(L(module.contextAr)).foregroundStyle(.secondary)
            Label(
                Lf("الوحدة %@ من %@ • %@ أسئلة • %@ دقيقة مقترحة", "\(moduleIndex + 1)", "\(modules.count)", "\(module.questions.count)", "\(module.recommendedMinutes)"),
                systemImage: "timer"
            )
            .font(.subheadline)
        }
    }

    @ViewBuilder
    private var sourceCard: some View {
        if section == .reading {
            InfoCard(title: L("النص الأكاديمي"), systemImage: "book.pages.fill") {
                Text(module.sourceText)
                    .font(.title3)
                    .lineSpacing(7)
                    .environment(\.layoutDirection, .leftToRight)
                    .textSelection(.enabled)
                    .accessibilityLabel(Lf("النص الإنجليزي الكامل. %@", "\(module.sourceText)"))
            }
        } else {
            InfoCard(title: L("المقطع الصوتي"), systemImage: "headphones") {
                Button {
                    replayCount += 1
                    textToSpeech.speak(
                        module.sourceText,
                        accent: settings.accentVariant,
                        rate: Float(settings.speechRate)
                    )
                } label: {
                    Label(
                        replayCount == 0
                            ? L("تشغيل المقطع")
                            : Lf("إعادة المقطع، شُغّل %@ مرة", "\(replayCount)"),
                        systemImage: textToSpeech.isSpeaking ? "stop.circle.fill" : "play.circle.fill"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                Text(L("استمع مرة واحدة أولًا، ودوّن الكلمات المفتاحية. الصوت الاصطناعي المحلي تدريب فهم، وليس محاكاة كاملة للهجات بشرية."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if submitted {
                    DisclosureGroup(L("إظهار النص بعد التصحيح")) {
                        Text(module.sourceText)
                            .environment(\.layoutDirection, .leftToRight)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func questionCard(_ question: ComprehensionQuestion, number: Int) -> some View {
        InfoCard(title: Lf("السؤال %@", "\(number)"), systemImage: "questionmark.circle.fill") {
            Text(question.prompt)
                .font(.headline)
                .environment(\.layoutDirection, .leftToRight)
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
                    .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(choiceTint(choice, question: question))
                .accessibilityLabel(choiceAccessibilityLabel(choice, question: question))
            }
            if submitted {
                Text(answers[question.id] == question.answer ? L("إجابة صحيحة") : Lf("الصحيح: %@", "\(question.answer)"))
                    .font(.caption.bold())
                Text(L(question.explanationAr)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var resultOrSubmit: some View {
        if submitted {
            InfoCard(title: L("النتيجة المقيسة"), systemImage: score >= 0.575 ? "checkmark.seal.fill" : "arrow.clockwise.circle.fill") {
                AccessibleProgressView(
                    title: Lf("%@ إجابات صحيحة من %@", "\(correctCount)", "\(module.questions.count)"),
                    value: score
                )
                Text(L("تتكون كل وحدة من 10 أسئلة تدريبية. لا تُعامل نتيجتها وحدها كنتيجة نموذج رسمي كامل من 40 سؤالًا."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PrimaryButton(title: L("الوحدة التالية"), systemImage: "arrow.forward.circle.fill") {
                    nextModule()
                }
            }
        } else {
            PrimaryButton(title: L("تصحيح الإجابات وتسجيل الوقت"), systemImage: "checkmark.circle.fill") {
                submit()
            }
            .disabled(answers.count < module.questions.count || isSaving)
            .accessibilityHint(Lf("يجب اختيار إجابة لكل الأسئلة وعددها %@", "\(module.questions.count)"))
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

    private func choiceAccessibilityLabel(_ choice: String, question: ComprehensionQuestion) -> String {
        if submitted && choice == question.answer { return Lf("%@، الإجابة الصحيحة", "\(choice)") }
        if submitted && answers[question.id] == choice { return Lf("%@، إجابتك غير صحيحة", "\(choice)") }
        if answers[question.id] == choice { return Lf("%@، محدد", "\(choice)") }
        return choice
    }

    private func submit() {
        submitted = true
        isSaving = true
        textToSpeech.stop()
        let elapsed = max(1, Int(ceil(Date().timeIntervalSince(startedAt) / 60)))
        let measuredMinutes = min(module.recommendedMinutes, elapsed)
        let day = Int(Date().startOfDay.timeIntervalSince1970)
        let currentModule = module
        let currentAnswers = answers
        let currentScore = score

        Task {
            await container.progressRepository.recordPracticeSession(.init(
                id: "\(currentModule.id)-\(day)",
                domain: section.practiceDomain,
                sourceID: currentModule.id,
                titleAr: currentModule.titleAr,
                level: session.selectedLevel,
                score: currentScore,
                minutes: measuredMinutes,
                createdAt: .now,
                details: currentModule.questions.compactMap { question in
                    currentAnswers[question.id] == question.answer ? nil : "\(question.prompt): \(question.answer)"
                }
            ))
            for question in currentModule.questions where currentAnswers[question.id] != question.answer {
                await container.learningMemoryRepository.recordMistake(.init(
                    id: "\(currentModule.id)-\(question.id)-\(day)",
                    category: section.titleAr,
                    source: currentModule.titleAr,
                    prompt: question.prompt,
                    learnerAnswer: currentAnswers[question.id] ?? L("دون إجابة"),
                    correction: question.answer,
                    explanationAr: question.explanationAr,
                    createdAt: .now,
                    reviewCount: 0,
                    resolved: false
                ))
            }
            isSaving = false
            ToastCenter.shared.show(L("حُفظت نتيجة التدريب والوقت الفعلي"), style: .success)
        }
    }

    private func nextModule() {
        textToSpeech.stop()
        moduleIndex = (moduleIndex + 1) % max(1, modules.count)
        answers = [:]
        submitted = false
        replayCount = 0
        startedAt = .now
    }
}
