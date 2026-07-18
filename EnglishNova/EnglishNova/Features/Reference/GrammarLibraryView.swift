import SwiftUI

struct GrammarLibraryView: View {
    @State private var selectedLevel: CEFRLevel? = nil

    private var topics: [GrammarTopic] {
        guard let selectedLevel else { return ReferenceLibrary.grammar }
        return ReferenceLibrary.grammar.filter { $0.level == selectedLevel }
    }

    var body: some View {
        List {
            Section {
                Picker(L("المستوى"), selection: $selectedLevel) {
                    Text(L("الكل")).tag(nil as CEFRLevel?)
                    ForEach(CEFRLevel.allCases) { Text($0.rawValue).tag(Optional($0)) }
                }
            }
            ForEach(topics) { topic in
                NavigationLink {
                    GrammarTopicView(topic: topic)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(topic.level.rawValue) • \(topic.titleAr)").font(.headline)
                        Text(topic.summaryAr).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
        }
        .navigationTitle(L("مكتبة القواعد"))
    }
}

private struct GrammarTopicView: View {
    @EnvironmentObject private var container: AppContainer
    let topic: GrammarTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L(topic.titleAr)).font(.largeTitle.bold())
                Text(topic.titleEn).font(.title2).foregroundStyle(.secondary).environment(\.layoutDirection, .leftToRight)
                InfoCard(title: "الفكرة", systemImage: "lightbulb.fill") { Text(topic.summaryAr) }
                InfoCard(title: "البنية", systemImage: "function") {
                    Text(topic.formula).font(.headline.monospaced()).environment(\.layoutDirection, .leftToRight)
                }
                InfoCard(title: "أمثلة", systemImage: "text.quote") {
                    ForEach(topic.examples) { example in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(example.english).font(.headline).environment(\.layoutDirection, .leftToRight)
                                Spacer()
                                Button { container.textToSpeech.speak(example.english) } label: { Image(systemName: "speaker.wave.2") }
                                    .accessibilityLabel(L("نطق المثال"))
                            }
                            Text(example.arabic).foregroundStyle(.secondary)
                        }
                        Divider()
                    }
                }
                InfoCard(title: "أخطاء شائعة", systemImage: "exclamationmark.triangle.fill") {
                    ForEach(topic.commonMistakes, id: \.self) { Text("• \($0)") }
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle(topic.level.rawValue)
        .navigationBarTitleDisplayMode(.inline)
    }
}
