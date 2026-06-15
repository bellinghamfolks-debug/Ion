import SwiftUI

@MainActor
final class AdaptivePlacementViewModel: ObservableObject {
    @Published var currentQuestion: PlacementQuestion?
    @Published var selectedAnswer = ""
    @Published var feedbackAr: String?
    @Published var result: PlacementResult?
    @Published var answeredCount = 0
    @Published var isAnswerLocked = false

    private var engine: AdaptivePlacementEngine

    init(startingLevel: CEFRLevel = .a1) {
        engine = AdaptivePlacementEngine(questions: PlacementQuestionBank.all, startingLevel: startingLevel)
        currentQuestion = engine.nextQuestion()
    }

    func submit() {
        guard let question = currentQuestion, !selectedAnswer.isEmpty, !isAnswerLocked else { return }
        engine.submit(question: question, selectedAnswer: selectedAnswer)
        answeredCount = engine.responses.count
        isAnswerLocked = true
        let correct = selectedAnswer == question.answer
        feedbackAr = correct ? "إجابة صحيحة. \(question.explanationAr)" : "الإجابة الصحيحة: \(question.answer). \(question.explanationAr)"
    }

    func advance() {
        guard isAnswerLocked else { return }
        if engine.shouldFinish {
            result = engine.result()
            currentQuestion = nil
            return
        }
        currentQuestion = engine.nextQuestion()
        if currentQuestion == nil { result = engine.result() }
        selectedAnswer = ""
        feedbackAr = nil
        isAnswerLocked = false
    }
}

struct PlacementTestView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: AdaptivePlacementViewModel

    init(startingLevel: CEFRLevel = .a1) {
        _model = StateObject(wrappedValue: AdaptivePlacementViewModel(startingLevel: startingLevel))
    }

    var body: some View {
        Group {
            if let result = model.result {
                resultView(result)
            } else if let question = model.currentQuestion {
                questionView(question)
            } else {
                ProgressView("جاري إعداد السؤال التالي")
            }
        }
        .padding(AppTheme.screenPadding)
        .screenBackground()
        .navigationTitle("اختبار تحديد المستوى")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func questionView(_ question: PlacementQuestion) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AccessibleProgressView(
                    title: "أجبت عن \(model.answeredCount) سؤالًا، والاختبار يتكيف مع إجاباتك",
                    value: min(1, Double(model.answeredCount) / 16)
                )

                HStack {
                    Label(question.level.rawValue, systemImage: question.skill.systemImage)
                    Spacer()
                    Text(question.skill.titleAr)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)

                if let promptAr = question.promptAr {
                    Text(promptAr).font(.headline)
                }
                Text(question.prompt)
                    .font(.title2.bold())
                    .environment(\.layoutDirection, .leftToRight)

                if let speechText = question.speechText {
                    Button {
                        container.textToSpeech.speak(speechText)
                    } label: {
                        Label("تشغيل المقطع", systemImage: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("يشغّل نص السؤال باللغة الإنجليزية")
                }

                ForEach(question.choices, id: \.self) { choice in
                    Button {
                        guard !model.isAnswerLocked else { return }
                        model.selectedAnswer = choice
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: model.selectedAnswer == choice ? "checkmark.circle.fill" : "circle")
                            Text(choice)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .environment(\.layoutDirection, .leftToRight)
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isAnswerLocked)
                    .accessibilityLabel(choice)
                    .accessibilityValue(model.selectedAnswer == choice ? "محدد" : "غير محدد")
                }

                if let feedback = model.feedbackAr {
                    InfoCard(title: "التغذية الراجعة", systemImage: "lightbulb.fill") {
                        Text(feedback)
                        Text("السؤال التالي قد يصبح أسهل أو أصعب بناءً على إجابتك.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityAddTraits(.isStaticText)
                }

                PrimaryButton(
                    title: model.isAnswerLocked ? "السؤال التالي" : "تحقق من الإجابة",
                    systemImage: model.isAnswerLocked ? "arrow.forward.circle.fill" : "checkmark.circle.fill",
                    isDisabled: model.selectedAnswer.isEmpty
                ) {
                    if model.isAnswerLocked { model.advance() } else { model.submit() }
                }
            }
        }
    }

    private func resultView(_ result: PlacementResult) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "scope")
                    .accessibilityHidden(true)
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("المستوى المقترح: \(result.recommendedLevel.rawValue)")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(result.recommendedLevel.titleAr).font(.title2)
                Text("أجبت عن \(result.correctCount) من \(result.responses.count) إجابة صحيحة. ثقة التقدير \(Int(result.confidence * 100))٪.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                InfoCard(title: "خريطة المهارات", systemImage: "chart.bar.xaxis") {
                    ForEach(result.skills) { skill in
                        AccessibleProgressView(
                            title: "\(skill.skill.titleAr): \(Int(skill.score * 100))٪ من \(skill.answered) أسئلة",
                            value: skill.score
                        )
                    }
                }

                Text("هذا تقدير تكيفي إرشادي يختار الأسئلة وفق أدائك، وليس شهادة لغوية معيارية.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                PrimaryButton(title: "اعتماد المستوى", systemImage: "checkmark.seal.fill") {
                    Task {
                        session.selectedLevel = result.recommendedLevel
                        await session.save()
                        await container.progressRepository.savePlacementResult(result)
                        dismiss()
                    }
                }
            }
        }
    }
}
