import SwiftUI

struct LessonPlayerView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: LessonPlayerViewModel
    @State private var showExitConfirm = false
    @State private var explainConcept: ExplainConcept?

    /// Wraps the concept string so `.sheet(item:)` (needs Identifiable) can drive
    /// the "اشرح لي" explanation sheet.
    private struct ExplainConcept: Identifiable { let id = UUID(); let text: String }

    init(lesson: Lesson) { _model = StateObject(wrappedValue: LessonPlayerViewModel(lesson: lesson)) }

    var body: some View {
        VStack(spacing: 16) {
            AccessibleProgressView(title: "تقدم الدرس", value: model.progress).padding(.horizontal)
            if model.phase == .lesson {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(L(model.current.promptAr)).font(.title2.bold())
                        if let prompt = model.current.promptEn, !prompt.isEmpty {
                            Text(prompt).font(.title3).environment(\.layoutDirection, .leftToRight)
                        }
                        ExerciseRenderer(exercise: model.current, selectedAnswer: $model.selectedAnswer, arrangedTokens: $model.arrangedTokens)
                        if model.answered && !isInformational { feedback }
                    }
                    .padding(AppTheme.screenPadding)
                }
                actionButton
            } else {
                result
            }
        }
        .screenBackground()
        .navigationTitle(L(model.lesson.titleAr))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.phase == .lesson)
        .toolbar {
            if model.phase == .lesson {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showExitConfirm = true } label: {
                        Label(L("إنهاء"), systemImage: "xmark")
                    }
                    .accessibilityLabel(L("إنهاء الدرس"))
                }
            }
        }
        .alert(L("إنهاء الدرس؟"), isPresented: $showExitConfirm) {
            Button(L("متابعة الدرس"), role: .cancel) {}
            Button(L("إنهاء وخروج"), role: .destructive) { dismiss() }
        } message: {
            Text(L("إذا خرجت الآن فلن يُحتسب تقدّمك في هذا الدرس. هل تريد الخروج؟"))
        }
        .sheet(item: $explainConcept) { concept in
            NavigationStack {
                ExplainView(initialConcept: concept.text)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(L("تم")) { explainConcept = nil }
                        }
                    }
            }
        }
        .onAppear { Task { await container.vocabularyRepository.add(words: model.lesson.vocabulary) } }
        .task(id: model.currentIndex) {
            guard model.phase == .lesson, settings.autoPlayLessonAudio else { return }
            if let speech = model.current.speechText ?? model.current.promptEn, !speech.isEmpty {
                container.textToSpeech.speak(speech)
            }
        }
    }

    /// Explanations and flashcards are informational — they shouldn't ask the
    /// learner to "check an answer" or show correct/incorrect feedback.
    private var isInformational: Bool {
        model.current.type == .explanation || model.current.type == .flashcard
    }

    @ViewBuilder private var actionButton: some View {
        if isInformational {
            PrimaryButton(title: "التالي", systemImage: "arrow.forward") {
                if !model.answered { model.submit() }
                model.continueNext()
            }
            .padding()
        } else if model.answered {
            PrimaryButton(title: "متابعة", systemImage: "arrow.forward") { model.continueNext() }.padding()
        } else {
            PrimaryButton(title: "تحقق من الإجابة", systemImage: "checkmark", isDisabled: !canSubmit) {
                let exercise = model.current
                if exercise.type == .arrangeWords { model.submitArranged() } else { model.submit() }
                Task { await container.progressRepository.recordSkill(skill(for: exercise), correct: model.lastWasCorrect, at: .now) }
            }
            .padding()
        }
    }

    private var canSubmit: Bool {
        switch model.current.type {
        case .explanation, .flashcard: return true
        case .arrangeWords: return !model.arrangedTokens.isEmpty
        default: return !model.selectedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var feedback: some View {
        InfoCard(title: model.lastWasCorrect ? "إجابة صحيحة" : "لنصححها معًا", systemImage: model.lastWasCorrect ? "checkmark.seal.fill" : "lightbulb.fill") {
            if !model.lastWasCorrect { Text("الإجابة: \(model.current.answer)").font(.headline) }
            Text(model.current.explanationAr)
            if !explainSeed.isEmpty {
                Button {
                    explainConcept = ExplainConcept(text: explainSeed)
                } label: {
                    Label(L("اشرح لي أكثر"), systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.accentTeal)
                .accessibilityHint(L("شرح إضافي من المدرّب الذكي"))
            }
        }
        .accessibilityLabel(model.lastWasCorrect ? "إجابة صحيحة" : "إجابة غير صحيحة. الصحيح \(model.current.answer). \(model.current.explanationAr)")
    }

    /// The English text we ask the AI to explain — prefer the correct answer,
    /// fall back to the English prompt. Trimmed; empty hides the button.
    private var explainSeed: String {
        let answer = model.current.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !answer.isEmpty { return answer }
        return (model.current.promptEn ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func skill(for exercise: Exercise) -> LanguageSkill {
        switch exercise.type {
        case .listenAndChoose: return .listening
        case .speak: return .practicalCommunication
        case .translation, .arrangeWords, .fillBlank: return .grammar
        case .multipleChoice, .flashcard: return .vocabulary
        case .explanation: return .reading
        }
    }

    private var scorePercent: Int { Int((model.score * 100).rounded()) }

    private var result: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 14)
                    Circle().trim(from: 0, to: model.score)
                        .stroke(AppTheme.gradient(scoreColors), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.7), value: model.score)
                    VStack(spacing: 0) {
                        Text("\(scorePercent)٪").font(.system(size: 38, weight: .bold, design: .rounded))
                        Text(L("تقييمك")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 150, height: 150)
                .padding(.top, 10)

                Text(headline).font(.title2.bold()).multilineTextAlignment(.center)

                InfoCard(title: "توصياتنا لك", systemImage: "sparkles", tint: AppTheme.accentTeal) {
                    ForEach(recommendations, id: \.self) { tip in
                        Label(tip, systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }

                PrimaryButton(title: "إنهاء الدرس", systemImage: "checkmark.circle.fill") {
                    Task {
                        let earned = Int(Double(model.lesson.points) * model.score)
                        await container.progressRepository.recordLesson(lessonID: model.lesson.id, score: model.score, points: earned, minutes: model.elapsedMinutes)
                        await session.award(points: earned)
                        // Auto-save to the account so progress is never lost.
                        if container.accountService.isAuthenticated {
                            await container.progressSyncService.push()
                        }
                        dismiss()
                    }
                }
            }
            .padding(AppTheme.screenPadding)
        }
    }

    private var scoreColors: [Color] {
        switch scorePercent {
        case 85...: return [AppTheme.success, AppTheme.accentTeal]
        case 60..<85: return [AppTheme.warning, AppTheme.streak]
        default: return [AppTheme.streak, .red]
        }
    }

    private var headline: String {
        switch scorePercent {
        case 90...: return L("أداء ممتاز! 🎉")
        case 70..<90: return L("أداء جيد جدًا 👏")
        case 50..<70: return L("أداء جيد، وتستطيع أفضل")
        default: return L("بداية جيدة، لنقوّها معًا")
        }
    }

    private var recommendations: [String] {
        switch scorePercent {
        case 90...:
            return [L("أتقنت هذا الدرس — انتقل إلى الدرس التالي بثقة."),
                    L("جرّب استخدام كلمات الدرس في جملة من عندك.")]
        case 70..<90:
            return [L("راجع الكلمات التي ترددت فيها من دفتر المفردات."),
                    L("أعد تمرين النطق مرة إضافية لتثبيت الإيقاع.")]
        case 50..<70:
            return [L("أعد الدرس بعد قليل — التكرار يثبّت المعلومة."),
                    L("ركّز على تمارين الاستماع وملء الفراغ."),
                    L("استخدم المدرّب الصوتي للتدرّب على الجمل.")]
        default:
            return [L("لا بأس، أعد الدرس بهدوء وركّز على الشرح أولًا."),
                    L("استمع للنموذج وكرّره بصوتٍ واضح قبل الإجابة."),
                    L("خفّض الهدف اليومي مؤقتًا وتقدّم خطوة بخطوة.")]
        }
    }
}
