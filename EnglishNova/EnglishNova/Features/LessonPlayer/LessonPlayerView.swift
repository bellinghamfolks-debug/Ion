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
                        Text(L(model.current.promptAr))
                            .font(.title2.bold())
                        if let prompt = model.current.promptEn, !prompt.isEmpty {
                            Text(prompt)
                                .font(.title3)
                                .environment(\.layoutDirection, .leftToRight)
                        }
                        ExerciseRenderer(
                            exercise: model.current,
                            selectedAnswer: $model.selectedAnswer,
                            arrangedTokens: $model.arrangedTokens
                        )
                        if model.answered && !isInformational {
                            feedback
                        }
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
                        Label(L("خروج"), systemImage: "xmark")
                    }
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
                        ToolbarItem(placement: .topBarLeading) {
                            Button(L("إغلاق")) { explainConcept = nil }
                        }
                    }
            }
        }
        .onAppear {
            Task { await container.vocabularyRepository.add(words: model.lesson.vocabulary) }
        }
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
            }
            .padding()
        } else if model.answered {
            PrimaryButton(title: L("التالي"), systemImage: "arrow.forward") {
                model.continueNext()
            }
            .padding()
        } else {
            PrimaryButton(
                title: L("تحقق"),
                systemImage: "checkmark",
                isDisabled: !canSubmit
            ) {
                let exercise = model.current
                if exercise.type == .arrangeWords {
                    model.submitArranged()
                } else {
                    model.submit()
                }
                Task {
                    await container.progressRepository.recordSkill(
                        skill(for: exercise),
                        correct: model.lastWasCorrect,
                        at: .now
                    )
                }
            }
            .padding()
        }
    }

    private var canSubmit: Bool {
        switch model.current.type {
        case .explanation, .flashcard:
            return true
        case .arrangeWords:
            return !model.arrangedTokens.isEmpty
        default:
            return !model.selectedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var feedback: some View {
        InfoCard(
            title: model.lastWasCorrect ? L("صحيح") : L("راجع الإجابة"),
            systemImage: model.lastWasCorrect ? "checkmark.seal.fill" : "lightbulb.fill"
        ) {
            if !model.lastWasCorrect {
                Text(L("الإجابة الصحيحة"))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(model.current.answer)
                    .font(.headline)
                    .environment(\.layoutDirection, .leftToRight)
            }

            if !model.current.explanationAr.isEmpty {
                Text(L(model.current.explanationAr))
            }

            if !explainSeed.isEmpty {
                Button {
                    explainConcept = ExplainConcept(text: explainSeed)
                } label: {
                    Label(L("اشرح أكثر"), systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.accentTeal)
                .accessibilityHint(L("يفتح شرحًا إضافيًا من المدرّب"))
            }
        }
        .accessibilityLabel(feedbackAccessibilityLabel)
    }

    private var feedbackAccessibilityLabel: String {
        if model.lastWasCorrect {
            return model.current.explanationAr.isEmpty
                ? L("الإجابة صحيحة")
                : Lf("الإجابة صحيحة. %@", model.current.explanationAr)
        }
        return Lf(
            "الإجابة غير صحيحة. الإجابة الصحيحة %@. %@",
            model.current.answer,
            model.current.explanationAr
        )
    }

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
                    Circle()
                        .trim(from: 0, to: model.score)
                        .stroke(
                            AppTheme.gradient(scoreColors),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.7), value: model.score)
                    VStack(spacing: 0) {
                        Text("\(scorePercent)٪")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                        Text(L("النتيجة"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 150, height: 150)
                .padding(.top, 10)

                Text(headline)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                InfoCard(title: L("الخطوة التالية"), systemImage: "arrow.forward.circle.fill", tint: AppTheme.accentTeal) {
                    ForEach(recommendations, id: \.self) { tip in
                        Label(tip, systemImage: "checkmark.circle")
                            .font(.subheadline)
                    }
                }

                PrimaryButton(title: L("حفظ النتيجة وإنهاء الدرس"), systemImage: "checkmark.circle.fill") {
                    Task {
                        let earned = Int(Double(model.lesson.points) * model.score)
                        await container.progressRepository.recordLesson(
                            lessonID: model.lesson.id,
                            score: model.score,
                            points: earned,
                            minutes: model.elapsedMinutes
                        )
                        await session.award(points: earned)
                        if container.accountService.isAuthenticated {
                            _ = await container.progressSyncService.push(showFeedback: false)
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
        case 90...: return L("أتقنت معظم أهداف الدرس.")
        case 75..<90: return L("نتيجة جيدة. بقيت نقاط قليلة للمراجعة.")
        case 55..<75: return L("تحتاج بعض أجزاء الدرس إلى مراجعة أخرى.")
        default: return L("راجع الشرح ثم أعد الدرس عندما تكون جاهزًا.")
        }
    }

    private var recommendations: [String] {
        switch scorePercent {
        case 90...:
            return [
                L("انتقل إلى الدرس التالي."),
                L("استخدم كلمتين من هذا الدرس في جملة من عندك.")
            ]
        case 75..<90:
            return [
                L("راجع الكلمات التي أخطأت فيها."),
                L("أعد سؤالًا أو سؤالين من النوع الذي كان أصعب عليك.")
            ]
        case 55..<75:
            return [
                L("راجع شرح الدرس قبل المحاولة التالية."),
                L("ابدأ بالمفردات ثم عد إلى الاستماع أو القواعد التي أخطأت فيها.")
            ]
        default:
            return [
                L("أعد الدرس ببطء وابدأ بالشرح والأمثلة."),
                L("قسّم التدريب إلى جلسة أقصر إذا كان الدرس مرهقًا."),
                L("اطلب شرحًا إضافيًا عندما تكون القاعدة غير واضحة.")
            ]
        }
    }
}
