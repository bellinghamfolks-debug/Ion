import SwiftUI

struct LessonPlayerView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: LessonPlayerViewModel

    init(lesson: Lesson) { _model = StateObject(wrappedValue: LessonPlayerViewModel(lesson: lesson)) }

    var body: some View {
        VStack(spacing: 16) {
            AccessibleProgressView(title: "تقدم الدرس", value: model.progress).padding(.horizontal)
            if model.phase == .lesson {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(model.current.promptAr).font(.title2.bold())
                        if let prompt = model.current.promptEn, !prompt.isEmpty {
                            Text(prompt).font(.title3).environment(\.layoutDirection, .leftToRight)
                        }
                        ExerciseRenderer(exercise: model.current, selectedAnswer: $model.selectedAnswer, arrangedTokens: $model.arrangedTokens)
                        if model.answered { feedback }
                    }
                    .padding(AppTheme.screenPadding)
                }
                actionButton
            } else {
                result
            }
        }
        .screenBackground()
        .navigationTitle(model.lesson.titleAr)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await container.vocabularyRepository.add(words: model.lesson.vocabulary) } }
        .task(id: model.currentIndex) {
            guard model.phase == .lesson, settings.autoPlayLessonAudio else { return }
            if let speech = model.current.speechText ?? model.current.promptEn, !speech.isEmpty {
                container.textToSpeech.speak(speech)
            }
        }
    }

    @ViewBuilder private var actionButton: some View {
        if model.answered {
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
        }
        .accessibilityLabel(model.lastWasCorrect ? "إجابة صحيحة" : "إجابة غير صحيحة. الصحيح \(model.current.answer). \(model.current.explanationAr)")
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

    private var result: some View {
        VStack(spacing: 20) {
            Image(systemName: model.score >= 0.7 ? "trophy.fill" : "arrow.counterclockwise.circle.fill").accessibilityHidden(true).font(.system(size: 72)).foregroundStyle(.tint)
            Text(model.score >= 0.7 ? "أحسنت، اكتمل الدرس" : "محاولة قوية، ونحتاج جولة أخرى").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("نتيجتك \(Int(model.score * 100))٪").font(.title2)
            PrimaryButton(title: "حفظ النتيجة والعودة", systemImage: "checkmark.circle.fill") {
                Task {
                    let earned = Int(Double(model.lesson.points) * model.score)
                    await container.progressRepository.recordLesson(lessonID: model.lesson.id, score: model.score, points: earned, minutes: model.elapsedMinutes)
                    await session.award(points: earned)
                    dismiss()
                }
            }
        }
        .padding(AppTheme.screenPadding)
        .accessibilityElement(children: .combine)
    }
}
