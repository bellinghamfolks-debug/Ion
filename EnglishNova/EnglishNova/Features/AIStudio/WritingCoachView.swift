import SwiftUI

/// Writing practice powered by the server tutor. The result is written back to
/// learning memory so later practice can target recurring mistakes.
struct WritingCoachView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @State private var text = ""
    @State private var result: WritingResult?
    @State private var taskType: WritingTaskType = .free
    @State private var task = ""
    /// The draft and score being revised, when the learner writes a second version.
    @State private var previousDraft: String?
    @State private var previousScore: Int?
    @State private var loading = false
    @State private var errorMessage: String?

    private let service = AIStudioService()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                InfoCard(title: L("تدريب الكتابة"), systemImage: "pencil.and.scribble") {
                    Text(L("اكتب جملة أو فقرة بالإنجليزية. سيقترح المدرّب تصحيحات مناسبة لمستواك، ويشرح أهم ما يحتاج إلى مراجعة."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Picker(LE("نوع الكتابة", "Writing type"), selection: $taskType) {
                        ForEach(WritingTaskType.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: taskType) { _, newValue in
                        if task.isEmpty || WritingTaskType.allCases.contains(where: { suggestedTask(for: $0) == task }) {
                            task = suggestedTask(for: newValue)
                        }
                    }

                    TextField(LE("المهمة (اختياري)", "Task (optional)"), text: $task, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .environment(\.layoutDirection, .leftToRight)

                    if previousDraft != nil {
                        Label(LE("تكتب الآن نسخة محسّنة. سيقارن المدرّب بينها وبين المسودة السابقة.",
                                 "You are writing an improved version. The coach will compare it with your previous draft."),
                              systemImage: "arrow.triangle.2.circlepath")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.accentTeal)
                    }

                    TextEditor(text: $text)
                        .frame(minHeight: 130)
                        .environment(\.layoutDirection, .leftToRight)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel(LE("نصّك بالإنجليزية", "Your English text"))

                    Text(LfE("%@ كلمة", "%@ words", "\(wordCount)"))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    PrimaryButton(
                        title: L("مراجعة النص"),
                        systemImage: "checkmark.seal.fill",
                        isLoading: loading,
                        isDisabled: trimmed.isEmpty
                    ) { run() }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let result {
                    if let score = result.score {
                        InfoCard(title: L("النتيجة"), systemImage: "gauge.with.dots.needle.67percent", tint: AppTheme.accentTeal) {
                            AccessibleProgressView(title: L("تقييم الكتابة"), value: Double(score) / 100)
                            LabeledContent(L("الدرجة"), value: "\(score)/100")
                            if let previousScore {
                                let delta = score - previousScore
                                Label(delta >= 0 ? LfE("تحسّن بمقدار %@ نقطة عن المسودة السابقة", "Up %@ points from your previous draft", "\(delta)")
                                                 : LfE("أقل بمقدار %@ نقطة من المسودة السابقة", "Down %@ points from your previous draft", "\(-delta)"),
                                      systemImage: delta >= 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                                    .foregroundStyle(delta >= 0 ? AppTheme.success : AppTheme.streak)
                            }
                            if let rubric = result.rubric {
                                Divider()
                                rubricRow(LE("إنجاز المهمة", "Task achievement"), rubric.taskAchievement)
                                rubricRow(LE("الترابط والتنظيم", "Coherence"), rubric.coherence)
                                rubricRow(LE("المفردات", "Vocabulary"), rubric.vocabulary)
                                rubricRow(LE("القواعد", "Grammar"), rubric.grammar)
                            }
                        }
                    }

                    if let revision = result.revisionAr, !revision.isEmpty {
                        InfoCard(title: LE("مقارنة بالمسودة السابقة", "Compared with your previous draft"), systemImage: "arrow.left.arrow.right", tint: AppTheme.accentTeal) {
                            Text(revision)
                        }
                    }

                    InfoCard(title: L("النص بعد المراجعة"), systemImage: "text.badge.checkmark", tint: AppTheme.success) {
                        Text(result.corrected)
                            .font(.body.weight(.medium))
                            .environment(\.layoutDirection, .leftToRight)
                            .textSelection(.enabled)
                    }

                    InfoCard(title: L("ملاحظات المدرّب"), systemImage: "brain.head.profile", tint: AppTheme.warning) {
                        Text(result.feedbackAr)
                        if !result.strengthsAr.isEmpty {
                            Divider()
                            Text(L("ما كان جيدًا"))
                                .font(.headline)
                            ForEach(result.strengthsAr, id: \.self) { item in
                                Label(item, systemImage: "checkmark.circle.fill")
                            }
                        }
                        if !result.improvementsAr.isEmpty {
                            Divider()
                            Text(L("ما يستحق المراجعة"))
                                .font(.headline)
                            ForEach(result.improvementsAr, id: \.self) { item in
                                Label(item, systemImage: "arrow.up.circle.fill")
                            }
                        }
                    }

                    if !result.corrections.isEmpty {
                        InfoCard(title: L("تصحيحات محفوظة للتدريب القادم"), systemImage: "bookmark.fill", tint: AppTheme.brandSecondary) {
                            ForEach(result.corrections) { correction in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(correction.original)
                                        .strikethrough()
                                        .environment(\.layoutDirection, .leftToRight)
                                    Text(correction.replacement)
                                        .font(.headline)
                                        .environment(\.layoutDirection, .leftToRight)
                                    Text(correction.reasonAr)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .combine)
                                if correction.id != result.corrections.last?.id { Divider() }
                            }
                        }
                    }

                    InfoCard(title: LE("حسّن نصّك", "Improve your text"), systemImage: "pencil.line", tint: AppTheme.brand) {
                        Text(LE("أعد كتابة النص بنفسك مستفيدًا من الملاحظات، ثم اطلب مراجعته مرة أخرى لترى تقدّمك.",
                                "Rewrite the text yourself using the feedback, then check it again to see your progress."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button {
                            previousDraft = trimmed
                            previousScore = result.score
                            self.result = nil
                            AccessibilityNotification.Announcement(LE("عدّل نصك ثم اضغط مراجعة النص.", "Edit your text, then tap Check text.")).post()
                        } label: {
                            Label(LE("اكتب نسخة محسّنة", "Write an improved version"), systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if let task = result.nextTaskEn, !task.isEmpty {
                        InfoCard(title: L("جرّب مرة أخرى"), systemImage: "arrow.triangle.2.circlepath") {
                            Text(task)
                                .environment(\.layoutDirection, .leftToRight)
                            Button(L("ابدأ إجابة جديدة")) {
                                text = ""
                                self.task = task
                                previousDraft = nil
                                previousScore = nil
                                self.result = nil
                                ToastCenter.shared.show(L("اكتب إجابتك الجديدة"), style: .info)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle(L("تدريب الكتابة"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var wordCount: Int { text.split { $0.isWhitespace || $0.isNewline }.count }

    private func rubricRow(_ title: String, _ value: Int?) -> some View {
        Group {
            if let value {
                AccessibleProgressView(title: LfE("%@: %@ من 100", "%@: %@ of 100", title, "\(value)"), value: Double(value) / 100)
            }
        }
    }

    private func suggestedTask(for type: WritingTaskType) -> String {
        switch type {
        case .free: return ""
        case .email: return "Write an email to a friend inviting them to dinner this weekend."
        case .opinion: return "Do you think students should learn online or in a classroom? Give reasons."
        case .story: return "Write a short story that begins: \"The phone rang at midnight.\""
        case .description: return "Describe your favourite place in your city."
        case .ieltsTask2: return "Some people think governments should spend more on public transport than on roads. To what extent do you agree or disagree?"
        }
    }

    private func run() {
        let value = trimmed
        guard !value.isEmpty, !loading else { return }
        loading = true
        errorMessage = nil
        Task {
            do {
                _ = await container.progressSyncService.pushIfStale()
                let taskText = task.trimmingCharacters(in: .whitespacesAndNewlines)
                let analyzed = try await service.correctWriting(
                    text: value,
                    level: session.selectedLevel.rawValue,
                    task: taskText.isEmpty ? nil : taskText,
                    taskType: taskType,
                    previousText: previousDraft
                )
                result = analyzed
                await recordLearning(from: analyzed, originalText: value)
                ToastCenter.shared.show(L("تمت مراجعة النص وحفظ نتيجته ضمن تقدّمك"))
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? L("تعذرت مراجعة النص.")
            }
            loading = false
        }
    }

    private func recordLearning(from result: WritingResult, originalText: String) async {
        for correction in result.corrections.prefix(8) {
            await container.learningMemoryRepository.recordMistake(.init(
                id: UUID().uuidString,
                category: L("الكتابة"),
                source: L("تدريب الكتابة"),
                prompt: correction.original,
                learnerAnswer: correction.original,
                correction: correction.replacement,
                explanationAr: correction.reasonAr,
                createdAt: .now,
                reviewCount: 0,
                resolved: false
            ))
        }

        if let score = result.score {
            let wordCount = originalText.split { $0.isWhitespace || $0.isNewline }.count
            let record = PracticeSessionRecord(
                id: UUID().uuidString,
                domain: .writing,
                sourceID: "ai-writing",
                titleAr: L("تدريب كتابة"),
                level: session.selectedLevel,
                score: Double(score) / 100,
                minutes: min(15, max(2, wordCount / 20 + 1)),
                createdAt: .now,
                details: Array((result.strengthsAr + result.improvementsAr).prefix(6))
            )
            await container.progressRepository.recordPracticeSession(record)
        }

        if container.accountService.isAuthenticated {
            _ = await container.progressSyncService.push(showFeedback: false)
        }
    }
}
