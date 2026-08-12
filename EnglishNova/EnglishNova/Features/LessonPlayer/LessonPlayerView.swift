import SwiftUI

struct LessonPlayerView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: LessonPlayerViewModel
    @State private var showExitConfirm = false
    @State private var explainConcept: ExplainConcept?

    private struct ExplainConcept: Identifiable {
        let id = UUID()
        let text: String
    }

    init(lesson: Lesson) {
        _model = StateObject(wrappedValue: LessonPlayerViewModel(lesson: lesson))
    }

    var body: some View {
        VStack(spacing: 16) {
            AccessibleProgressView(title: L("تقدّم الدرس"), value: model.progress)
                .padding(.horizontal)

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
                    Button { showExitConfirm = true } label: { Label(L("خروج"), systemImage: "xmark") }
                        .accessibilityLabel(L("الخروج من الدرس"))
                }
            }
        }
        .alert(L("الخروج من الدرس؟"), isPresented: $showExitConfirm) {
            Button(L("أكمل الدرس"), role: .cancel) {}
            Button(L("خروج"), role: .destructive) { dismiss() }
        } message: {
            Text(L("لن يُسجَّل الدرس كمكتمل إذا خرجت قبل شاشة النتيجة."))
        }
        .sheet(item: $explainConcept) { concept in
            NavigationStack {
                ExplainView(initialConcept: concept.text)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { Button(L("إغلاق")) { explainConcept = nil } }
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

    private var isInformational: Bool {
        model.current.type == .explanation || model.current.type == .flashcard
    }

    @ViewBuilder
    private var actionButton: some View {
        if isInformational {
            PrimaryButton(title: L("التالي"), systemImage: "arrow.forward") {
                if !model.answered { model.submit() }
                model.continueNext()
            }.padding()
        } else if model.answered {
            PrimaryButton(title: L("التالي"), systemImage: "arrow.forward") { model.continueNext() }.padding()
        } else {
            PrimaryButton(title: L("تحقق"), systemImage: "checkmark", isDisabled: !canSubmit) {
                let exercise = model.current
                if exercise.type == .arrangeWords { model.submitArranged() } else { model.submit() }
                Task {
                    await container.progressRepository.recordSkill(skill(for: exercise), correct: model.lastWasCorrect, at: .now)
                }
            }.padding()
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
        InfoCard(title: model.lastWasCorrect ? L("صحيح") : L("راجع الإجابة"),
                 systemImage: model.lastWasCorrect ? "checkmark.seal.fill" : "lightbulb.fill") {
            if !model.lastWasCorrect {
                Text(L("الإجابة الصحيحة")).font(.caption.bold()).foregroundStyle(.secondary)
                Text(model.current.answer).font(.headline).environment(\.layoutDirection, .leftToRight)
            }
            if !model.current.explanationAr.isEmpty { Text(L(model.current.explanationAr)) }
            if !explainSeed.isEmpty {
                Button { explainConcept = ExplainConcept(text: explainSeed) } label: {
                    Label(L("اشرح أكثر"), systemImage: "sparkles").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered).tint(AppTheme.accentTeal)
                .accessibilityHint(L("يفتح شرحًا إضافيًا من المدرّب"))
            }
        }
        .accessibilityLabel(feedbackAccessibilityLabel)
    }

    private var feedbackAccessibilityLabel: String {
        if model.lastWasCorrect {
            return model.current.explanationAr.isEmpty ? L("الإجابة صحيحة") : Lf("الإجابة صحيحة. %@", model.current.explanationAr)
        }
        return Lf("الإجابة غير صحيحة. الإجابة الصحيحة %@. %@", model.current.answer, model.current.explanationAr)
    }

    private var explainSeed: String {
        let answer = model.current.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        return !answer.isEmpty ? answer : (model.current.promptEn ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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

    private var assessment: LessonAssessment { model.assessment }
    private var scorePercent: Int { assessment.percent }

    private var result: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: model.score)
                        .stroke(AppTheme.gradient(scoreColors), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.7), value: model.score)
                    VStack(spacing: 0) {
                        Text("\(scorePercent)%").font(.system(size: 38, weight: .bold, design: .rounded))
                        Text(L("درجة الإتقان")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 150, height: 150).padding(.top, 10)

                Text(headline).font(.title2.bold()).multilineTextAlignment(.center)

                InfoCard(title: L("كيف حُسبت الدرجة؟"), systemImage: "checkmark.seal.fill", tint: AppTheme.brand) {
                    Text(LE(
                        "لا تتساوى كل الأسئلة. الاختيار والاستماع دليل استقبالي، والفراغ والترتيب دليل مضبوط، أما الترجمة والتحدث فلهما وزن أكبر في المستويات المتقدمة.",
                        "Not every item has the same weight. Recognition tasks provide receptive evidence, controlled tasks test form, and translation/speaking carry more weight at higher levels."
                    )).font(.footnote).foregroundStyle(.secondary)
                    if let value = assessment.receptiveScore {
                        LabeledContent(LE("الفهم والاستقبال", "Receptive evidence"), value: "\(Int((value * 100).rounded()))%")
                    }
                    if let value = assessment.controlledScore {
                        LabeledContent(LE("الاستخدام المضبوط", "Controlled use"), value: "\(Int((value * 100).rounded()))%")
                    }
                    if let value = assessment.productiveScore {
                        LabeledContent(LE("الإنتاج اللغوي", "Productive use"), value: "\(Int((value * 100).rounded()))%")
                    }
                    LabeledContent(LE("حد اجتياز هذا المستوى", "Pass threshold for this level"), value: "\(Int(assessment.passThreshold * 100))%")
                    if let floor = assessment.productiveFloor {
                        LabeledContent(LE("الحد الأدنى للإنتاج", "Minimum productive score"), value: "\(Int(floor * 100))%")
                    }
                }

                InfoCard(title: L("الخطوة التالية"), systemImage: "arrow.forward.circle.fill", tint: AppTheme.accentTeal) {
                    ForEach(recommendations, id: \.self) { tip in Label(tip, systemImage: "checkmark.circle").font(.subheadline) }
                }

                PrimaryButton(title: assessment.passed ? L("حفظ النتيجة وإنهاء الدرس") : LE("حفظ المحاولة وإنهاء الدرس", "Save attempt and finish"),
                              systemImage: assessment.passed ? "checkmark.circle.fill" : "arrow.clockwise.circle.fill") {
                    Task {
                        let multiplier = assessment.passed ? 1.0 : 0.25
                        let earned = Int(Double(model.lesson.points) * model.score * multiplier)
                        await container.progressRepository.recordLesson(
                            lessonID: model.lesson.id,
                            score: model.score,
                            passed: assessment.passed,
                            points: earned,
                            minutes: model.elapsedMinutes
                        )
                        await session.award(points: earned)
                        if container.accountService.isAuthenticated { _ = await container.progressSyncService.push(showFeedback: false) }
                        dismiss()
                    }
                }
            }
            .padding(AppTheme.screenPadding)
        }
    }

    private var scoreColors: [Color] {
        assessment.passed ? [AppTheme.success, AppTheme.accentTeal] : [AppTheme.streak, .red]
    }

    private var headline: String {
        if assessment.passed {
            return scorePercent >= 90 ? LE("أظهرت إتقانًا قويًا لأهداف الدرس.", "You showed strong mastery of this lesson's goals.")
                                      : LE("اجتزت الدرس، وما زالت هناك نقاط تستحق التثبيت.", "You passed the lesson, with a few areas still worth reinforcing.")
        }
        if assessment.productiveFloor != nil && (assessment.productiveScore ?? 0) < (assessment.productiveFloor ?? 0) {
            return LE("لم يثبت الاستخدام العملي للغة بما يكفي بعد.", "Productive language use is not strong enough yet.")
        }
        return LE("هذه المحاولة لم تصل إلى حد الإتقان المطلوب لهذا المستوى.", "This attempt did not reach the mastery threshold for this level.")
    }

    private var recommendations: [String] {
        if assessment.passed {
            return [LE("انتقل إلى الدرس التالي.", "Continue to the next lesson."),
                    LE("استخدم فكرتين من الدرس في كلام أو كتابة من عندك.", "Use two ideas from the lesson in your own speaking or writing.")]
        }
        var tips = [LE("راجع الأسئلة التي أخطأت فيها قبل إعادة المحاولة.", "Review the items you missed before trying again.")]
        if (assessment.productiveScore ?? 1) < (assessment.productiveFloor ?? 0) {
            tips.append(LE("ركّز على الترجمة والتحدث بدل إعادة أسئلة الاختيار فقط.", "Focus on translation and speaking instead of repeating recognition questions only."))
        }
        tips.append(LE("اطلب شرحًا إضافيًا لأي قاعدة أو عبارة لم تكن واضحة.", "Ask the tutor for an explanation of any unclear rule or phrase."))
        return tips
    }
}
