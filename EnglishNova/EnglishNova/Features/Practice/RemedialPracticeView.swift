import SwiftUI

/// "Practise your mistakes": replays unresolved mistakes as real exercises.
/// A right answer marks the mistake resolved; a wrong one keeps it for later.
/// It never records lesson progress, so it cannot pass or fail a lesson.
struct RemedialPracticeView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @Environment(\.dismiss) private var dismiss
    var onFinish: (() -> Void)? = nil

    @State private var items: [RemedialItem] = []
    @State private var isLoading = true
    @State private var index = 0
    @State private var selectedAnswer = ""
    @State private var arrangedTokens: [String] = []
    @State private var answered = false
    @State private var lastWasCorrect = false
    @State private var resolvedCount = 0
    @State private var finished = false
    @State private var startedAt = Date()

    var body: some View {
        Group {
            if isLoading {
                ProgressView(LE("جارٍ تجهيز أخطائك", "Preparing your mistakes"))
            } else if items.isEmpty {
                ContentUnavailableView(
                    LE("لا توجد أخطاء مفتوحة", "No open mistakes"),
                    systemImage: "checkmark.seal",
                    description: Text(LE("أحسنت. ستظهر هنا الأسئلة التي تخطئ فيها داخل الدروس والتدريب.",
                                         "Nice work. Items you miss in lessons and practice will appear here."))
                )
            } else if finished {
                summary
            } else {
                runner
            }
        }
        .screenBackground()
        .navigationTitle(LE("تدرّب على أخطائك", "Practise your mistakes"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var current: Exercise { items[index].exercise }

    private var runner: some View {
        VStack(spacing: 16) {
            AccessibleProgressView(title: LE("تقدّم التدريب", "Practice progress"),
                                   value: Double(index + (answered ? 1 : 0)) / Double(max(items.count, 1)))
                .padding(.horizontal)
            Text(LfE("السؤال %@ من %@", "Question %@ of %@", "\(index + 1)", "\(items.count)"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(current.displayPrompt)
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    if let prompt = current.promptEn, !prompt.isEmpty {
                        Text(prompt).font(.title3).environment(\.layoutDirection, .leftToRight)
                    }
                    ExerciseRenderer(exercise: current, selectedAnswer: $selectedAnswer, arrangedTokens: $arrangedTokens)
                    if answered { feedback }
                }
                .padding(AppTheme.screenPadding)
            }

            if answered {
                PrimaryButton(title: LE("التالي", "Next"), systemImage: "arrow.forward") { next() }.padding()
            } else {
                PrimaryButton(title: LE("تحقق", "Check"), systemImage: "checkmark",
                              isDisabled: !ExerciseRenderer.canSubmit(current, selectedAnswer: selectedAnswer, arrangedTokens: arrangedTokens)) {
                    check()
                }
                .padding()
            }
        }
        .accessibilityAction(.magicTap) {
            if let text = current.speechText, !text.isEmpty { container.textToSpeech.speak(text) }
        }
    }

    private var feedback: some View {
        InfoCard(title: lastWasCorrect ? LE("صحيح", "Correct") : LE("ما زالت تحتاج تدريبًا", "Still needs practice"),
                 systemImage: lastWasCorrect ? "checkmark.seal.fill" : "lightbulb.fill",
                 tint: lastWasCorrect ? AppTheme.success : AppTheme.streak) {
            if !lastWasCorrect {
                Text(LE("الإجابة الصحيحة", "Correct answer")).font(.caption.bold()).foregroundStyle(.secondary)
                Text(current.displayAnswer).font(.headline).environment(\.layoutDirection, .leftToRight)
            }
            if !current.explanationAr.isEmpty, current.type != .matchPairs {
                Text(current.display(current.explanationAr))
            }
        }
    }

    private var summary: some View {
        ScrollView {
            VStack(spacing: 20) {
                CelebrationView(systemImage: "arrow.uturn.backward.circle.fill", tint: AppTheme.accentTeal, size: 96)
                Text(LfE("صحّحت %@ من %@", "You fixed %@ of %@", "\(resolvedCount)", "\(items.count)"))
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(resolvedCount == items.count
                     ? LE("كل الأخطاء في هذه الجولة أصبحت محسومة.", "Every mistake in this round is now resolved.")
                     : LE("ما لم تصححه سيعود إليك في جولة قادمة.", "Anything you did not fix will come back in a later round."))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                PrimaryButton(title: LE("إنهاء", "Done"), systemImage: "checkmark.circle.fill") { dismiss() }
            }
            .padding(AppTheme.screenPadding)
        }
    }

    private func load() async {
        guard isLoading else { return }
        async let memoryValue = container.learningMemoryRepository.snapshot()
        let catalog = try? await container.courseRepository.catalog()
        let memory = await memoryValue
        items = RemedialPracticeEngine.items(mistakes: memory.mistakes, catalog: catalog)
        startedAt = .now
        isLoading = false
    }

    private func check() {
        let response = current.type == .arrangeWords ? arrangedTokens.joined(separator: " ") : selectedAnswer
        lastWasCorrect = current.isCorrect(response)
        answered = true
        FeedbackSoundEngine.shared.play(lastWasCorrect ? .correct : .incorrect)
        AccessibilityNotification.Announcement(
            lastWasCorrect ? LE("صحيح", "Correct") : LfE("غير صحيح. الإجابة الصحيحة %@", "Not quite. The answer is %@", current.displayAnswer)
        ).post()
        let item = items[index]
        let correct = lastWasCorrect
        if correct { resolvedCount += 1 }
        Task {
            await container.progressRepository.recordSkill(item.exercise.type.practicedSkill, correct: correct, at: .now)
            if correct { await container.learningMemoryRepository.markMistakeResolved(id: item.mistakeID, resolved: true) }
        }
    }

    private func next() {
        if index + 1 < items.count {
            index += 1
            selectedAnswer = ""
            arrangedTokens = []
            answered = false
            lastWasCorrect = false
        } else {
            finish()
        }
    }

    private func finish() {
        finished = true
        let total = items.count
        let score = total > 0 ? Double(resolvedCount) / Double(total) : 1
        let minutes = max(1, Int(Date().timeIntervalSince(startedAt) / 60))
        let points = resolvedCount * 2
        FeedbackSoundEngine.shared.play(.success)
        onFinish?()
        Task {
            await container.progressRepository.recordPracticeSession(PracticeSessionRecord(
                id: "remedial-\(UUID().uuidString)",
                domain: .grammar,
                sourceID: "remedial-mistakes",
                titleAr: LE("تدرّب على أخطائك", "Practise your mistakes"),
                level: session.selectedLevel,
                score: score,
                minutes: minutes,
                createdAt: .now,
                details: items.map { $0.exercise.displayAnswer }
            ))
            if points > 0 { await session.award(points: points) }
        }
    }
}
