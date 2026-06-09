import SwiftUI

struct StoryLibraryView: View {
    @State private var levelFilter: CEFRLevel?

    private var interactiveStories: [InteractiveStory] {
        guard let levelFilter else { return InteractiveStoryLibrary.stories }
        return InteractiveStoryLibrary.stories.filter { $0.level == levelFilter }
    }

    private var gradedStories: [GradedStory] {
        guard let levelFilter else { return ReferenceLibrary.stories }
        return ReferenceLibrary.stories.filter { $0.level == levelFilter }
    }

    var body: some View {
        List {
            Section("تصفية المستوى") {
                Picker("المستوى", selection: $levelFilter) {
                    Text("الكل").tag(CEFRLevel?.none)
                    ForEach(CEFRLevel.allCases) { level in
                        Text(level.rawValue).tag(Optional(level))
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("قصص تفاعلية متفرعة") {
                ForEach(interactiveStories) { story in
                    NavigationLink {
                        InteractiveStoryPlayerView(story: story)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(story.level.rawValue) • \(story.titleAr)").font(.headline)
                            Text(story.titleEn).environment(\.layoutDirection, .leftToRight)
                            Text(story.summaryAr).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("قراءة وفهم") {
                ForEach(gradedStories) { story in
                    NavigationLink {
                        StoryReaderView(story: story)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(story.level.rawValue) • \(story.titleAr)").font(.headline)
                            Text(story.titleEn).foregroundStyle(.secondary).environment(\.layoutDirection, .leftToRight)
                        }
                    }
                }
            }
        }
        .navigationTitle("القصص المتدرجة")
    }
}

private struct StoryReaderView: View {
    @EnvironmentObject private var container: AppContainer
    let story: GradedStory
    @State private var selectedAnswers: [String: String] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(story.titleAr).font(.largeTitle.bold())
                Text(story.titleEn).font(.title2).foregroundStyle(.secondary).environment(\.layoutDirection, .leftToRight)
                ForEach(story.paragraphs) { paragraph in
                    InfoCard(title: "فقرة", systemImage: "text.alignleft") {
                        HStack(alignment: .top) {
                            Text(paragraph.english).font(.title3).environment(\.layoutDirection, .leftToRight)
                            Spacer()
                            Button { container.textToSpeech.speak(paragraph.english) } label: { Image(systemName: "speaker.wave.2.fill") }
                                .accessibilityLabel("نطق الفقرة")
                        }
                        Text(paragraph.arabic).foregroundStyle(.secondary)
                    }
                }
                InfoCard(title: "الكلمات المهمة", systemImage: "character.book.closed.fill") {
                    ForEach(story.keyWords) { word in
                        VStack(alignment: .leading) {
                            Text("\(word.english): \(word.arabic)").font(.headline).environment(\.layoutDirection, .leftToRight)
                            Text(word.example).environment(\.layoutDirection, .leftToRight)
                        }
                    }
                    Button("إضافة الكلمات إلى المراجعة") {
                        Task { await container.vocabularyRepository.add(words: story.keyWords) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                ForEach(story.questions) { question in
                    InfoCard(title: "سؤال فهم", systemImage: "questionmark.circle.fill") {
                        Text(question.promptAr).font(.headline)
                        ForEach(question.choices, id: \.self) { choice in
                            Button {
                                selectedAnswers[question.id] = choice
                            } label: {
                                HStack {
                                    Text(choice).environment(\.layoutDirection, .leftToRight)
                                    Spacer()
                                    Image(systemName: selectedAnswers[question.id] == choice ? "checkmark.circle.fill" : "circle")
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        if let selected = selectedAnswers[question.id] {
                            Text(selected == question.answer ? "إجابة صحيحة" : "الصحيح: \(question.answer)")
                                .font(.headline)
                                .accessibilityLabel(selected == question.answer ? "إجابة صحيحة" : "إجابة غير صحيحة. الصحيح \(question.answer)")
                        }
                    }
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle(story.level.rawValue)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct InteractiveStoryPlayerView: View {
    @EnvironmentObject private var container: AppContainer
    let story: InteractiveStory

    @State private var sceneID: String
    @State private var points = 0
    @State private var lastFeedback: String?
    @State private var history: [String] = []
    @State private var didRecordCompletion = false

    init(story: InteractiveStory) {
        self.story = story
        _sceneID = State(initialValue: story.startSceneID)
    }

    private var scene: StoryScene? { story.scene(id: sceneID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(story.titleAr).font(.largeTitle.bold())
                Text(story.titleEn).font(.title2).foregroundStyle(.secondary).environment(\.layoutDirection, .leftToRight)
                AccessibleProgressView(title: "النقاط: \(points) من 20", value: min(1, Double(points) / 20))

                if let feedback = lastFeedback {
                    Label(feedback, systemImage: "lightbulb.fill")
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityAddTraits(.isStaticText)
                }

                if let scene {
                    InfoCard(title: "المشهد", systemImage: "book.pages.fill") {
                        HStack(alignment: .top) {
                            Text(scene.english)
                                .font(.title2.bold())
                                .environment(\.layoutDirection, .leftToRight)
                            Spacer()
                            Button { container.textToSpeech.speak(scene.english) } label: {
                                Image(systemName: "speaker.wave.2.fill")
                            }
                            .accessibilityLabel("نطق نص المشهد")
                        }
                        Text(scene.arabic).foregroundStyle(.secondary)
                        if let hint = scene.narratorHintAr {
                            Label(hint, systemImage: "sparkles")
                                .font(.subheadline)
                        }
                    }

                    if let ending = scene.ending {
                        endingView(ending)
                    } else {
                        ForEach(scene.choices) { choice in
                            Button {
                                choose(choice)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(choice.english)
                                        .font(.headline)
                                        .environment(\.layoutDirection, .leftToRight)
                                    Text(choice.arabic).font(.subheadline).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityHint("ينقلك هذا الاختيار إلى المشهد التالي")
                        }
                    }
                }

                InfoCard(title: "كلمات القصة", systemImage: "character.book.closed.fill") {
                    ForEach(story.keyWords) { word in
                        HStack {
                            Text(word.english).bold().environment(\.layoutDirection, .leftToRight)
                            Text(word.arabic).foregroundStyle(.secondary)
                            Spacer()
                            Button { container.textToSpeech.speak(word.english) } label: { Image(systemName: "speaker.wave.2") }
                                .accessibilityLabel("نطق \(word.english)")
                        }
                    }
                    Button("إضافة الكلمات إلى قاموسي") {
                        Task { await container.vocabularyRepository.add(words: story.keyWords) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle(story.level.rawValue)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func endingView(_ ending: StoryEnding) -> some View {
        InfoCard(title: ending.titleAr, systemImage: "flag.checkered") {
            Text(ending.messageAr).font(.title3)
            Text("وصلت إلى نهاية \(ending.id). يمكنك إعادة القصة لاكتشاف نهاية أخرى.")
                .font(.caption).foregroundStyle(.secondary)
            Button("إعادة القصة") { restart() }
                .buttonStyle(.borderedProminent)
        }
        .task(id: ending.id) {
            guard !didRecordCompletion else { return }
            didRecordCompletion = true
            await container.progressRepository.recordStory(
                storyID: story.id,
                score: min(1, Double(points) / 20),
                endingID: ending.id
            )
        }
    }

    private func choose(_ choice: StoryChoice) {
        history.append(sceneID)
        points += choice.points
        lastFeedback = choice.feedbackAr
        sceneID = choice.nextSceneID
    }

    private func restart() {
        sceneID = story.startSceneID
        points = 0
        lastFeedback = nil
        history = []
        didRecordCompletion = false
    }
}
