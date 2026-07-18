import SwiftUI

struct ExerciseRenderer: View {
    @EnvironmentObject private var container: AppContainer
    let exercise: Exercise
    @Binding var selectedAnswer: String
    @Binding var arrangedTokens: [String]

    var body: some View {
        switch exercise.type {
        case .explanation:
            InfoCard(title: "شرح", systemImage: "book.fill") { Text(exercise.explanationAr).font(.title3) }
        case .multipleChoice, .listenAndChoose:
            VStack(spacing: 12) {
                if exercise.type == .listenAndChoose {
                    Button { container.textToSpeech.speak(exercise.speechText ?? exercise.answer) } label: {
                        Label(L("استمع إلى الجملة"), systemImage: "speaker.wave.2.fill").frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.bordered)
                }
                ForEach(exercise.choices ?? [], id: \.self) { choice in
                    ChoiceButton(title: choice, selected: selectedAnswer == choice) { selectedAnswer = choice }
                }
            }
        case .fillBlank, .translation:
            TextField(L("اكتب إجابتك"), text: $selectedAnswer, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityHint(L(exercise.accessibilityHint))
        case .arrangeWords:
            ArrangeWordsView(tokens: exercise.tokens ?? [], arranged: $arrangedTokens)
        case .flashcard:
            VStack(spacing: 16) {
                Text(exercise.answer).font(.system(.largeTitle, design: .rounded).bold())
                    .environment(\.layoutDirection, .leftToRight)
                Button { container.textToSpeech.speak(exercise.answer) } label: { Label(L("نطق الكلمة"), systemImage: "speaker.wave.2.fill") }
                    .buttonStyle(.bordered)
                if !exercise.explanationAr.isEmpty {
                    Divider()
                    Text(exercise.explanationAr)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(32)
            .background(.background, in: RoundedRectangle(cornerRadius: 20))
        case .speak:
            SpeakExerciseView(exercise: exercise, selectedAnswer: $selectedAnswer)
        }
    }
}

private struct ChoiceButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            }
            .padding()
            .frame(minHeight: 52)
            .background(selected ? Color.accentColor.opacity(0.15) : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? "محدد" : "غير محدد")
    }
}

private struct ArrangeWordsView: View {
    let tokens: [String]
    @Binding var arranged: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("الجملة الحالية: \(arranged.joined(separator: " "))")
                .font(.headline)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityLabel(arranged.isEmpty ? "لم تختر كلمات بعد" : "الجملة الحالية \(arranged.joined(separator: " "))")
            ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                Button("\(index + 1). \(token)") { arranged.append(token) }
                    .buttonStyle(.bordered)
                    .disabled(usedCount(token) >= tokenCount(token))
            }
            Button(L("حذف آخر كلمة")) { _ = arranged.popLast() }
                .disabled(arranged.isEmpty)
        }
    }
    private func usedCount(_ token: String) -> Int { arranged.filter { $0 == token }.count }
    private func tokenCount(_ token: String) -> Int { tokens.filter { $0 == token }.count }
}

private struct SpeakExerciseView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var speechService: SpeechService
    let exercise: Exercise
    @Binding var selectedAnswer: String

    var body: some View {
        VStack(spacing: 14) {
            Button { container.textToSpeech.speak(exercise.speechText ?? exercise.answer) } label: {
                Label(L("استمع للنموذج"), systemImage: "speaker.wave.2.fill").frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.bordered)
            Button {
                Task {
                    if speechService.state == .listening { speechService.stop() }
                    else { await speechService.start() }
                }
            } label: {
                Label(speechService.state == .listening ? "إيقاف التسجيل" : "ابدأ النطق", systemImage: speechService.state == .listening ? "stop.circle.fill" : "mic.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            Text(speechService.transcript.isEmpty ? "سيظهر كلامك هنا" : speechService.transcript)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                .padding().background(.background, in: RoundedRectangle(cornerRadius: 14))
                .environment(\.layoutDirection, .leftToRight)
                .onChange(of: speechService.transcript) { _, newValue in selectedAnswer = newValue }
        }
    }
}
