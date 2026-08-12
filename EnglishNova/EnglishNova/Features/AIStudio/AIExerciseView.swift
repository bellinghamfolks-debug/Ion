import SwiftUI

/// Generated practice can follow a learner-selected topic or let the server
/// choose a focus from synced learning needs and recent results.
struct AIExerciseView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @State private var topic = ""
    @State private var questions: [ExerciseQuestion] = []
    @State private var selections: [String: Int] = [:]
    @State private var revealed = false
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var focusAr: String?
    @State private var reasonAr: String?
    @State private var generatedDomain: String?
    @State private var recordedResult = false
    @State private var autoStarted = false

    let startAdaptive: Bool
    private let service = AIStudioService()
    private let topics = ["Travel", "Daily routine", "Business email", "Food", "Present tenses"]

    init(startAdaptive: Bool = false) {
        self.startAdaptive = startAdaptive
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                InfoCard(title: L("تمارين مخصصة"), systemImage: "wand.and.stars") {
                    Text(L("اكتب موضوعًا تريد التدرب عليه، أو دع المدرّب يختار تمرينًا من أدائك وأخطائك الأخيرة."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    PrimaryButton(
                        title: L("اختر تدريبًا مناسبًا لي"),
                        systemImage: "brain.head.profile",
                        isLoading: loading,
                        isDisabled: loading
                    ) { generate(adaptive: true) }

                    Divider()

                    HStack {
                        Image(systemName: "tag")
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        TextField(L("موضوع، مثل Travel"), text: $topic)
                            .environment(\.layoutDirection, .leftToRight)
                            .submitLabel(.go)
                            .onSubmit { generate(adaptive: false) }
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(topics, id: \.self) { item in
                                Button(item) {
                                    topic = item
                                    generate(adaptive: false)
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                                .environment(\.layoutDirection, .leftToRight)
                            }
                        }
                    }

                    PrimaryButton(
                        title: L("إنشاء تمارين عن الموضوع"),
                        systemImage: "sparkles",
                        isLoading: loading,
                        isDisabled: trimmed.isEmpty || loading
                    ) { generate(adaptive: false) }
                }

                if let focusAr, !focusAr.isEmpty {
                    InfoCard(title: L("اختيار التدريب"), systemImage: "scope", tint: AppTheme.accentTeal) {
                        Text(focusAr).font(.headline)
                        if let reasonAr, !reasonAr.isEmpty {
                            Text(reasonAr).foregroundStyle(.secondary)
                        }
                    }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(Array(questions.enumerated()), id: \.element.id) { index, question in
                    questionCard(number: index + 1, question: question)
                }

                if !questions.isEmpty {
                    if revealed {
                        InfoCard(title: L("النتيجة"), systemImage: "rosette", tint: AppTheme.success) {
                            AccessibleProgressView(title: L("الإجابات الصحيحة"), value: scoreRatio)
                            LabeledContent(L("الصحيحة"), value: "\(correctCount)/\(questions.count)")
                            Text(L("حُفظت النتيجة ضمن تقدّمك حتى تساعد في اختيار التدريب القادم."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button(L("إنشاء تدريب آخر")) { reset() }
                                .buttonStyle(.bordered)
                        }
                    } else {
                        PrimaryButton(
                            title: L("تحقق من الإجابات"),
                            systemImage: "checkmark.circle.fill",
                            isDisabled: selections.count < questions.count
                        ) { check() }
                    }
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle(L("تمارين مخصصة"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard startAdaptive, !autoStarted else { return }
            autoStarted = true
            generate(adaptive: true)
        }
    }

    private func questionCard(number: Int, question: ExerciseQuestion) -> some View {
        InfoCard(title: Lf("سؤال %@", "\(number)"), systemImage: "questionmark.circle.fill") {
            Text(question.prompt)
                .font(.body.weight(.medium))
                .environment(\.layoutDirection, .leftToRight)

            ForEach(Array(question.options.enumerated()), id: \.offset) { optionIndex, option in
                Button {
                    guard !revealed else { return }
                    selections[question.id] = optionIndex
                } label: {
                    HStack {
                        Image(systemName: optionIcon(question: question, optionIndex: optionIndex))
                            .foregroundStyle(optionTint(question: question, optionIndex: optionIndex))
                        Text(option)
                            .environment(\.layoutDirection, .leftToRight)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(10)
                    .background(
                        optionTint(question: question, optionIndex: optionIndex).opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityValue(selections[question.id] == optionIndex ? L("محدد") : L("غير محدد"))
            }

            if revealed, let hint = question.hintAr, !hint.isEmpty {
                Label(hint, systemImage: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func optionIcon(question: ExerciseQuestion, optionIndex: Int) -> String {
        if revealed {
            if optionIndex == question.answerIndex { return "checkmark.circle.fill" }
            if selections[question.id] == optionIndex { return "xmark.circle.fill" }
            return "circle"
        }
        return selections[question.id] == optionIndex ? "largecircle.fill.circle" : "circle"
    }

    private func optionTint(question: ExerciseQuestion, optionIndex: Int) -> Color {
        if revealed {
            if optionIndex == question.answerIndex { return AppTheme.success }
            if selections[question.id] == optionIndex { return AppTheme.streak }
            return .secondary
        }
        return selections[question.id] == optionIndex ? AppTheme.brand : .secondary
    }

    private var trimmed: String { topic.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var correctCount: Int {
        questions.reduce(0) { $0 + (selections[$1.id] == $1.answerIndex ? 1 : 0) }
    }

    private var scoreRatio: Double {
        questions.isEmpty ? 0 : Double(correctCount) / Double(questions.count)
    }

    private func generate(adaptive: Bool) {
        guard !loading else { return }
        if !adaptive && trimmed.isEmpty { return }
        loading = true
        errorMessage = nil
        reset(keepTopic: true)

        Task {
            do {
                let result: ExerciseResult
                if adaptive {
                    _ = await container.progressSyncService.pushIfStale()
                    result = try await service.generateAdaptiveExercise(
                        level: session.selectedLevel.rawValue,
                        count: 5
                    )
                } else {
                    result = try await service.generateExercise(
                        topic: trimmed,
                        level: session.selectedLevel.rawValue,
                        count: 5
                    )
                }
                questions = result.questions
                focusAr = result.focusAr
                reasonAr = result.reasonAr
                generatedDomain = result.domain
                if questions.isEmpty {
                    errorMessage = L("لم تصل تمارين صالحة. حاول مرة أخرى.")
                }
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? L("تعذر إنشاء التمارين.")
            }
            loading = false
        }
    }

    private func check() {
        withAnimation { revealed = true }
        ToastCenter.shared.show(Lf("إجابات صحيحة: %@ من %@", "\(correctCount)", "\(questions.count)"))
        guard !recordedResult else { return }
        recordedResult = true
        Task { await recordLearningResult() }
    }

    private func recordLearningResult() async {
        let domain = mappedDomain(generatedDomain)
        let title = focusAr?.isEmpty == false
            ? focusAr!
            : (trimmed.isEmpty ? L("تدريب مخصص") : trimmed)

        let record = PracticeSessionRecord(
            id: UUID().uuidString,
            domain: domain,
            sourceID: "ai-exercise-\(domain.rawValue)",
            titleAr: title,
            level: session.selectedLevel,
            score: scoreRatio,
            minutes: max(2, questions.count),
            createdAt: .now,
            details: [
                Lf("إجابات صحيحة: %@ من %@", "\(correctCount)", "\(questions.count)"),
                reasonAr ?? ""
            ].filter { !$0.isEmpty }
        )
        await container.progressRepository.recordPracticeSession(record)
        if container.accountService.isAuthenticated {
            _ = await container.progressSyncService.push(showFeedback: false)
        }
    }

    private func mappedDomain(_ raw: String?) -> AdvancedSkillDomain {
        switch raw {
        case "reading": return .reading
        case "listening": return .listening
        case "writing": return .writing
        case "speaking": return .speaking
        case "vocabulary": return .vocabulary
        default: return .grammar
        }
    }

    private func reset(keepTopic: Bool = false) {
        questions = []
        selections = [:]
        revealed = false
        focusAr = nil
        reasonAr = nil
        generatedDomain = nil
        recordedResult = false
        if !keepTopic { topic = "" }
    }
}
