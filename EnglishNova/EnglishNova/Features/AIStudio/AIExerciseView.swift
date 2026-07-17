import SwiftUI

/// Generated practice — the learner picks a topic, the server AI generates
/// multiple-choice questions at their level, they answer, and get scored.
/// Powered by /ai/exercise (cached server-side per topic+level).
struct AIExerciseView: View {
    @EnvironmentObject private var session: UserSession
    @State private var topic = ""
    @State private var questions: [ExerciseQuestion] = []
    @State private var selections: [String: Int] = [:]   // question id -> chosen option index
    @State private var revealed = false
    @State private var loading = false
    @State private var errorMessage: String?

    private let service = AIStudioService()
    private let topics = ["Travel", "Daily routine", "Business email", "Food", "Present tenses"]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                InfoCard(title: "مولّد التمارين", systemImage: "wand.and.stars") {
                    Text("اختر موضوعًا وسيولّد لك المدرّب تمارين اختيار من متعدد مناسبة لمستواك.")
                        .font(.footnote).foregroundStyle(.secondary)

                    HStack {
                        Image(systemName: "tag").foregroundStyle(.secondary).frame(width: 22)
                        TextField("موضوع (مثال: Travel)", text: $topic)
                            .environment(\.layoutDirection, .leftToRight)
                            .submitLabel(.go)
                            .onSubmit(generate)
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(topics, id: \.self) { item in
                                Button(item) { topic = item; generate() }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                    .environment(\.layoutDirection, .leftToRight)
                            }
                        }
                    }

                    PrimaryButton(title: "ولّد التمارين", systemImage: "sparkles", isLoading: loading,
                                  isDisabled: trimmed.isEmpty) { generate() }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(Array(questions.enumerated()), id: \.element.id) { index, question in
                    questionCard(number: index + 1, question: question)
                }

                if !questions.isEmpty {
                    if revealed {
                        InfoCard(title: "النتيجة", systemImage: "rosette", tint: AppTheme.success) {
                            AccessibleProgressView(title: "إجاباتك الصحيحة", value: scoreRatio)
                            LabeledContent("الصحيحة", value: "\(correctCount)/\(questions.count)")
                            Button("تمرين جديد") { reset() }
                                .buttonStyle(.bordered)
                        }
                    } else {
                        PrimaryButton(title: "تحقّق من الإجابات", systemImage: "checkmark.circle.fill",
                                      isDisabled: selections.count < questions.count) { check() }
                    }
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle("مولّد التمارين")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func questionCard(number: Int, question: ExerciseQuestion) -> some View {
        InfoCard(title: "سؤال \(number)", systemImage: "questionmark.circle.fill") {
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
                    .background(optionTint(question: question, optionIndex: optionIndex).opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }

            if revealed, let hint = question.hintAr, !hint.isEmpty {
                Label(hint, systemImage: "lightbulb").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Option styling

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

    // MARK: - Scoring

    private var trimmed: String { topic.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var correctCount: Int {
        questions.reduce(0) { $0 + (selections[$1.id] == $1.answerIndex ? 1 : 0) }
    }
    private var scoreRatio: Double {
        questions.isEmpty ? 0 : Double(correctCount) / Double(questions.count)
    }

    private func generate() {
        let value = trimmed
        guard !value.isEmpty, !loading else { return }
        loading = true
        errorMessage = nil
        reset()
        Task {
            do {
                let result = try await service.generateExercise(
                    topic: value, level: session.selectedLevel.rawValue, count: 5)
                questions = result.questions
                if questions.isEmpty { errorMessage = "لم تُولَّد تمارين. جرّب موضوعًا آخر." }
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "تعذّر توليد التمارين."
            }
            loading = false
        }
    }

    private func check() {
        withAnimation { revealed = true }
        ToastCenter.shared.show("أصبت \(correctCount) من \(questions.count)")
    }

    private func reset() {
        selections = [:]
        revealed = false
    }
}
