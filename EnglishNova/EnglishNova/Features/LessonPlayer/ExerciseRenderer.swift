import SwiftUI

struct ExerciseRenderer: View {
    @EnvironmentObject private var container: AppContainer
    let exercise: Exercise
    @Binding var selectedAnswer: String
    @Binding var arrangedTokens: [String]

    var body: some View {
        switch exercise.type {
        case .explanation:
            InfoCard(title: L("شرح الدرس"), systemImage: "book.fill") {
                Text(L(exercise.explanationAr)).font(.title3)
            }

        case .multipleChoice, .listenAndChoose:
            VStack(spacing: 12) {
                if exercise.type == .listenAndChoose {
                    Button {
                        container.textToSpeech.speak(exercise.speechText ?? exercise.answer)
                    } label: {
                        Label(L("تشغيل الصوت"), systemImage: "speaker.wave.2.fill")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.bordered)
                }
                ForEach(exercise.choices ?? [], id: \.self) { choice in
                    ChoiceButton(title: L(choice), selected: selectedAnswer == choice) {
                        selectedAnswer = choice
                    }
                }
            }

        case .fillBlank, .translation:
            TextField(L("اكتب الإجابة"), text: $selectedAnswer, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityHint(L(exercise.accessibilityHint))

        case .arrangeWords:
            ArrangeWordsView(tokens: exercise.tokens ?? [], arranged: $arrangedTokens)

        case .flashcard:
            VStack(spacing: 16) {
                Text(L(exercise.answer))
                    .font(.system(.largeTitle, design: .rounded).bold())
                    .environment(\.layoutDirection, .leftToRight)
                Button {
                    container.textToSpeech.speak(exercise.answer)
                } label: {
                    Label(L("سماع الكلمة"), systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(.bordered)

                if !exercise.explanationAr.isEmpty {
                    Divider()
                    Text(L(exercise.explanationAr))
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
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)
            }
            .padding()
            .frame(minHeight: 52)
            .background(
                selected ? Color.accentColor.opacity(0.15) : Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? L("محدد") : L("غير محدد"))
    }
}

private struct ArrangeWordsView: View {
    let tokens: [String]
    @Binding var arranged: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            let visibleArranged = arranged.map(L).joined(separator: " ")
            Text(arranged.isEmpty ? L("لم تبدأ الجملة بعد.") : visibleArranged)
                .font(.headline)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityLabel(
                    arranged.isEmpty
                        ? L("لم تختر أي كلمة بعد")
                        : Lf("الجملة الحالية: %@", visibleArranged)
                )

            Text(L("اختر الكلمات بالترتيب الصحيح:"))
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                Button("\(index + 1). \(L(token))") {
                    arranged.append(token)
                }
                .buttonStyle(.bordered)
                .disabled(usedCount(token) >= tokenCount(token))
            }

            Button(L("تراجع عن آخر كلمة")) {
                _ = arranged.popLast()
            }
            .disabled(arranged.isEmpty)
        }
    }

    private func usedCount(_ token: String) -> Int {
        arranged.filter { $0 == token }.count
    }

    private func tokenCount(_ token: String) -> Int {
        tokens.filter { $0 == token }.count
    }
}

private struct SpeakExerciseView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var speechService: SpeechService
    let exercise: Exercise
    @Binding var selectedAnswer: String

    var body: some View {
        VStack(spacing: 14) {
            Button {
                container.textToSpeech.speak(exercise.speechText ?? exercise.answer)
            } label: {
                Label(L("سماع النموذج"), systemImage: "speaker.wave.2.fill")
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.bordered)

            Button {
                Task {
                    if speechService.state == .listening {
                        speechService.stop()
                    } else {
                        await speechService.start()
                    }
                }
            } label: {
                Label(
                    speechService.state == .listening ? L("إيقاف التسجيل") : L("ابدأ التسجيل"),
                    systemImage: speechService.state == .listening ? "stop.circle.fill" : "mic.circle.fill"
                )
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)

            Text(speechService.transcript.isEmpty ? L("سيظهر النص المتعرّف إليه هنا.") : speechService.transcript)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                .padding()
                .background(.background, in: RoundedRectangle(cornerRadius: 14))
                .environment(\.layoutDirection, .leftToRight)
                .onChange(of: speechService.transcript) { _, newValue in
                    selectedAnswer = newValue
                }
        }
    }
}
