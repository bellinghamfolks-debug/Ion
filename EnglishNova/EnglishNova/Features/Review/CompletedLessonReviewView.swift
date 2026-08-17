import SwiftUI

struct CompletedLessonReviewListView: View {
    @EnvironmentObject private var container: AppContainer
    @StateObject private var model = LessonReviewQueueViewModel()

    var body: some View {
        Group {
            if model.isLoading {
                ProgressView(LE("جارٍ تجهيز مراجعات الدروس", "Preparing lesson reviews"))
            } else if let error = model.errorMessage {
                ContentUnavailableView(
                    LE("تعذر تحميل المراجعات", "Reviews unavailable"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if model.candidates.isEmpty {
                ContentUnavailableView(
                    LE("لا توجد دروس مجتازة بعد", "No completed lessons yet"),
                    systemImage: "books.vertical",
                    description: Text(LE(
                        "بعد اجتياز أول درس سيبدأ التطبيق بجدولة مراجعات قصيرة لتثبيت ما تعلمته.",
                        "After you pass your first lesson, short spaced reviews will be scheduled to strengthen retention."
                    ))
                )
            } else {
                List {
                    if !model.due.isEmpty {
                        Section {
                            ForEach(model.due) { candidate in
                                reviewLink(candidate)
                            }
                        } header: {
                            Text(LE("مستحقة الآن", "Due now"))
                        } footer: {
                            Text(LE(
                                "الأولوية للأقدم والأضعف حتى تراجع ما يُرجح أن تنساه أولًا.",
                                "Older and weaker material is prioritized so you revisit what is most likely to fade first."
                            ))
                        }
                    }

                    let scheduled = model.candidates.filter { !$0.isDue }
                    if !scheduled.isEmpty {
                        Section {
                            ForEach(scheduled) { candidate in
                                reviewLink(candidate)
                            }
                        } header: {
                            Text(LE("الدروس المجتازة", "Completed lessons"))
                        } footer: {
                            Text(LE(
                                "يمكنك مراجعة أي درس مبكرًا، لكن الجدول المقترح يقلل التكرار غير الضروري.",
                                "You can review any lesson early, but the suggested schedule avoids unnecessary repetition."
                            ))
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await reload() }
            }
        }
        .navigationTitle(LE("مراجعة الدروس", "Lesson review"))
        .task { await reload() }
    }

    @ViewBuilder
    private func reviewLink(_ candidate: LessonReviewCandidate) -> some View {
        NavigationLink {
            LessonReviewSessionView(candidate: candidate)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(LE(candidate.lesson.titleAr, candidate.lesson.titleEn))
                    .font(.headline)
                HStack(spacing: 10) {
                    Text(candidate.lesson.reviewLevel.rawValue)
                    Text(dueText(candidate))
                    Text(LfE(
                        "أفضل نتيجة في الدرس %@٪",
                        "Lesson best %@%",
                        "\(Int((candidate.progress.bestScore * 100).rounded()))"
                    ))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .accessibilityHint(LE(
            "يفتح جلسة مراجعة قصيرة من تمارين هذا الدرس.",
            "Opens a short review session using exercises from this lesson."
        ))
    }

    private func dueText(_ candidate: LessonReviewCandidate) -> String {
        if candidate.isDue {
            return LE("مستحقة الآن", "Due now")
        }
        let start = Date().startOfDay
        let due = candidate.dueDate.startOfDay
        let days = max(1, Calendar.current.dateComponents([.day], from: start, to: due).day ?? 1)
        if days == 1 { return LE("المراجعة غدًا", "Review tomorrow") }
        return LfE("بعد %@ أيام", "In %@ days", "\(days)")
    }

    private func reload() async {
        await model.load(
            courseRepository: container.courseRepository,
            progressRepository: container.progressRepository
        )
    }
}

struct LessonReviewSessionView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: LessonReviewSessionViewModel
    @State private var showExitConfirm = false
    @State private var isSaving = false

    init(candidate: LessonReviewCandidate) {
        _model = StateObject(wrappedValue: LessonReviewSessionViewModel(candidate: candidate))
    }

    var body: some View {
        VStack(spacing: 16) {
            if model.exercises.isEmpty {
                ContentUnavailableView(
                    LE("لا توجد تمارين مناسبة للمراجعة", "No suitable review exercises"),
                    systemImage: "checkmark.circle",
                    description: Text(LE(
                        "هذا الدرس لا يحتوي حاليًا أسئلة قابلة للتقييم.",
                        "This lesson currently has no gradable review items."
                    ))
                )
            } else if model.phase == .review, let exercise = model.current {
                AccessibleProgressView(title: LE("تقدّم المراجعة", "Review progress"), value: model.progress)
                    .padding(.horizontal)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(displayPrompt(exercise))
                            .font(.title2.bold())
                        ExerciseRenderer(
                            exercise: exercise,
                            selectedAnswer: $model.selectedAnswer,
                            arrangedTokens: $model.arrangedTokens
                        )
                        if model.answered { feedback(exercise) }
                    }
                    .padding(AppTheme.screenPadding)
                }
                actionButton(exercise)
            } else {
                resultView
            }
        }
        .screenBackground()
        .navigationTitle(LE(model.candidate.lesson.titleAr, model.candidate.lesson.titleEn))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.phase == .review && !model.exercises.isEmpty)
        .toolbar {
            if model.phase == .review && !model.exercises.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showExitConfirm = true } label: {
                        Label(LE("خروج", "Exit"), systemImage: "xmark")
                    }
                }
            }
        }
        .alert(LE("الخروج من المراجعة؟", "Exit review?"), isPresented: $showExitConfirm) {
            Button(LE("أكمل المراجعة", "Continue review"), role: .cancel) {}
            Button(LE("خروج", "Exit"), role: .destructive) { dismiss() }
        } message: {
            Text(LE(
                "لن تُحفظ نتيجة هذه الجلسة إذا خرجت الآن.",
                "This review result will not be saved if you exit now."
            ))
        }
        .task(id: model.currentIndex) {
            guard model.phase == .review,
                  settings.autoPlayLessonAudio,
                  let current = model.current,
                  let speech = current.speechText ?? current.promptEn,
                  !speech.isEmpty else { return }
            container.textToSpeech.speak(speech)
        }
    }

    private func displayPrompt(_ exercise: Exercise) -> String {
        let english = exercise.promptEn?.trimmingCharacters(in: .whitespacesAndNewlines)
        return LE(exercise.promptAr, (english?.isEmpty == false ? english! : L(exercise.promptAr)))
    }

    @ViewBuilder
    private func actionButton(_ exercise: Exercise) -> some View {
        if model.answered {
            PrimaryButton(title: LE("التالي", "Next"), systemImage: "arrow.forward") {
                model.continueNext()
            }
            .padding()
        } else {
            PrimaryButton(
                title: LE("تحقق", "Check"),
                systemImage: "checkmark",
                isDisabled: !canSubmit(exercise)
            ) {
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

    private func canSubmit(_ exercise: Exercise) -> Bool {
        if exercise.type == .arrangeWords { return !model.arrangedTokens.isEmpty }
        return !model.selectedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func feedback(_ exercise: Exercise) -> some View {
        InfoCard(
            title: model.lastWasCorrect ? LE("صحيح", "Correct") : LE("راجع الإجابة", "Review the answer"),
            systemImage: model.lastWasCorrect ? "checkmark.seal.fill" : "lightbulb.fill"
        ) {
            if !model.lastWasCorrect {
                Text(LE("الإجابة الصحيحة", "Correct answer"))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(L(exercise.answer))
                    .font(.headline)
                    .environment(\.layoutDirection, .leftToRight)
            }
            if !exercise.explanationAr.isEmpty {
                Text(L(exercise.explanationAr))
            }
        }
    }

    private var resultView: some View {
        ScrollView {
            VStack(spacing: 22) {
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: model.score)
                        .stroke(AppTheme.gradient([AppTheme.brand, AppTheme.accentTeal]), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text("\(model.scorePercent)%")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                        Text(LE("ثبات المعلومة", "Retention score"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 155, height: 155)

                Text(resultHeadline)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                InfoCard(
                    title: LE("المراجعة التالية", "Next review"),
                    systemImage: "calendar.badge.clock",
                    tint: AppTheme.accentTeal
                ) {
                    Text(nextReviewText)
                    Text(LE(
                        "يتغير الموعد حسب قدرتك على الاسترجاع، وليس حسب عدد مرات فتح الدرس.",
                        "The interval changes with retrieval performance, not with how often the lesson is opened."
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                InfoCard(
                    title: LE("لماذا هذه الجلسة قصيرة؟", "Why is this session short?"),
                    systemImage: "brain.head.profile"
                ) {
                    Text(LE(
                        "المراجعة تختبر عينة متوازنة من الدرس، وتزيد أسئلة الإنتاج اللغوي في المستويات الأعلى حتى تثبت القدرة على الاستخدام لا مجرد التعرف على الإجابة.",
                        "The review samples the lesson and increases productive tasks at higher levels, reinforcing actual use rather than simple answer recognition."
                    ))
                }

                PrimaryButton(
                    title: isSaving ? LE("جارٍ الحفظ", "Saving") : LE("حفظ المراجعة", "Save review"),
                    systemImage: "checkmark.circle.fill",
                    isDisabled: isSaving || model.exercises.isEmpty
                ) {
                    saveReview()
                }
            }
            .padding(AppTheme.screenPadding)
        }
    }

    private var resultHeadline: String {
        switch model.score {
        case 0.90...:
            return LE("المعلومة ثابتة بدرجة قوية.", "Your recall is strong and stable.")
        case 0.75..<0.90:
            return LE("التذكر جيد، مع نقاط قليلة تستحق التثبيت.", "Recall is good, with a few areas worth reinforcing.")
        case 0.60..<0.75:
            return LE("المعلومة بدأت تضعف؛ ستعود للمراجعة قريبًا.", "Retention is fading, so this lesson will return soon.")
        default:
            return LE("تحتاج هذا الدرس إلى استرجاع قريب قبل أن يضعف أكثر.", "This lesson needs another retrieval session soon.")
        }
    }

    private var nextReviewText: String {
        let days = model.predictedState.intervalDays
        if days == 1 { return LE("غدًا", "Tomorrow") }
        return LfE("بعد %@ أيام", "In %@ days", "\(days)")
    }

    private func saveReview() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            let earned = max(2, Int((model.score * 10).rounded()))
            _ = await container.progressRepository.recordLessonReview(
                lessonID: model.candidate.lesson.id,
                score: model.score,
                minutes: model.elapsedMinutes,
                points: earned,
                at: .now
            )
            await session.award(points: earned)
            if container.accountService.isAuthenticated {
                _ = await container.progressSyncService.push(showFeedback: false)
            }
            dismiss()
        }
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
}
