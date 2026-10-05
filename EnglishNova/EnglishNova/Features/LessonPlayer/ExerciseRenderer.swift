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
                    ChoiceButton(title: choice, selected: selectedAnswer == choice) {
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

        case .listenType, .dictation:
            VStack(spacing: 12) {
                ReplayAudioButton(text: exercise.speechText ?? exercise.answer)
                TextField(
                    exercise.type == .dictation ? LE("اكتب الجملة كما سمعتها", "Type the sentence you heard") : LE("اكتب الكلمة", "Type the word"),
                    text: $selectedAnswer,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityHint(exercise.accessibilityHint)
            }

        case .trueFalse:
            HStack(spacing: 12) {
                ChoiceButton(title: LE("صح", "True"), selected: selectedAnswer == "true") { selectedAnswer = "true" }
                ChoiceButton(title: LE("خطأ", "False"), selected: selectedAnswer == "false") { selectedAnswer = "false" }
            }

        case .matchPairs:
            MatchPairsView(words: exercise.tokens ?? [], meanings: exercise.choices ?? [], encoded: $selectedAnswer)
        }
    }

    /// Whether the learner has given enough of an answer to check it.
    static func canSubmit(_ exercise: Exercise, selectedAnswer: String, arrangedTokens: [String]) -> Bool {
        switch exercise.type {
        case .explanation, .flashcard: return true
        case .arrangeWords: return !arrangedTokens.isEmpty
        case .matchPairs: return Exercise.pairs(from: selectedAnswer).count == (exercise.tokens ?? []).count
        default: return !selectedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

/// Large replay button used by every audio-first exercise.
struct ReplayAudioButton: View {
    @EnvironmentObject private var container: AppContainer
    let text: String

    var body: some View {
        Button {
            container.textToSpeech.speak(text)
        } label: {
            Label(LE("تشغيل الصوت", "Play audio"), systemImage: "speaker.wave.2.fill")
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.bordered)
        .accessibilityHint(LE("يمكنك أيضًا النقر مرتين بإصبعين لإعادة التشغيل.", "You can also double-tap with two fingers to replay."))
    }
}

/// Matching built from menus: each English word gets a picker of meanings.
/// This works the same with touch, Switch Control and VoiceOver, unlike
/// drag-and-drop or tap-two-tiles patterns.
private struct MatchPairsView: View {
    let words: [String]
    let meanings: [String]
    @Binding var encoded: String

    private var pairs: [String: String] { Exercise.pairs(from: encoded) }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(words, id: \.self) { word in
                HStack(spacing: 12) {
                    Text(word)
                        .font(.headline)
                        .environment(\.layoutDirection, .leftToRight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Menu {
                        ForEach(meanings, id: \.self) { meaning in
                            Button {
                                assign(meaning, to: word)
                            } label: {
                                if pairs[word] == meaning {
                                    Label(meaning, systemImage: "checkmark")
                                } else {
                                    Text(meaning)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(pairs[word] ?? LE("اختر المعنى", "Choose meaning"))
                                .foregroundStyle(pairs[word] == nil ? .secondary : .primary)
                            Image(systemName: "chevron.up.chevron.down").accessibilityHidden(true)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 48)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityLabel(word)
                    .accessibilityValue(pairs[word] ?? LE("لم يُختر معنى بعد", "No meaning chosen yet"))
                    .accessibilityHint(LE("يفتح قائمة المعاني", "Opens the list of meanings"))
                }
                .padding(12)
                .background(.background, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func assign(_ meaning: String, to word: String) {
        var current = pairs
        // A meaning belongs to one word at a time.
        for (key, value) in current where value == meaning { current[key] = nil }
        current[word] = meaning
        encoded = Exercise.encodePairs(words.compactMap { key in current[key].map { (key, $0) } })
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

extension Exercise {
    /// Curriculum copy goes through `L()`; synthesized copy is already localized.
    func display(_ text: String) -> String {
        isSynthesized ? text : L(text)
    }

    var displayPrompt: String { display(promptAr) }

    /// The correct answer as a learner should read it.
    var displayAnswer: String {
        readable(answer)
    }

    /// Turns an encoded response (pairs, true/false) into readable text.
    func readable(_ response: String) -> String {
        switch type {
        case .matchPairs:
            let pairs = Exercise.pairs(from: response)
            return (tokens ?? []).compactMap { word in pairs[word].map { "\(word) = \($0)" } }
                .joined(separator: "، ")
        case .trueFalse:
            if response == "true" { return LE("صح", "True") }
            if response == "false" { return LE("خطأ", "False") }
            return response
        default:
            return isSynthesized ? response : L(response)
        }
    }
}
