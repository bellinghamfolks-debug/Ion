import SwiftUI

enum WordbookFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case due
    case mastered

    var id: String { rawValue }
    var titleAr: String {
        switch self {
        case .all: return L("الكل")
        case .favorites: return L("المفضلة")
        case .due: return L("مستحقة")
        case .mastered: return L("متقنة")
        }
    }
}

@MainActor
final class WordbookViewModel: ObservableObject {
    @Published var cards: [ReviewCard] = []
    @Published var query = ""
    @Published var filter: WordbookFilter = .all
    @Published var selectedTag = ""
    @Published var isLoading = true

    var tags: [String] {
        Array(Set(cards.flatMap(\.tags))).sorted()
    }

    var filtered: [ReviewCard] {
        cards.filter { card in
            let matchesQuery = query.isEmpty ||
                card.word.english.localizedCaseInsensitiveContains(query) ||
                card.word.arabic.localizedCaseInsensitiveContains(query) ||
                card.note.localizedCaseInsensitiveContains(query) ||
                card.tags.contains { $0.localizedCaseInsensitiveContains(query) }
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .favorites: matchesFilter = card.isFavorite
            case .due: matchesFilter = card.dueDate <= .now
            case .mastered: matchesFilter = card.confidence >= 0.72
            }
            let matchesTag = selectedTag.isEmpty || card.tags.contains(selectedTag)
            return matchesQuery && matchesFilter && matchesTag
        }
    }

    func load(repository: VocabularyRepositoryProtocol) async {
        isLoading = true
        cards = await repository.allCards().sorted { $0.word.english.localizedCaseInsensitiveCompare($1.word.english) == .orderedAscending }
        isLoading = false
    }
}

struct WordbookView: View {
    @EnvironmentObject private var container: AppContainer
    @StateObject private var model = WordbookViewModel()

    var body: some View {
        List {
            Section(L("التصفية")) {
                Picker(L("نوع الكلمات"), selection: $model.filter) {
                    ForEach(WordbookFilter.allCases) { filter in
                        Text(L(filter.titleAr)).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                if !model.tags.isEmpty {
                    Picker(L("التصنيف"), selection: $model.selectedTag) {
                        Text(L("كل التصنيفات")).tag("")
                        ForEach(model.tags, id: \.self) { Text($0).tag($0) }
                    }
                }
                Text("\(model.filtered.count) كلمة ظاهرة من أصل \(model.cards.count)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if model.isLoading {
                ProgressView(L("جاري تحميل كلماتك"))
            } else if model.filtered.isEmpty {
                ContentUnavailableView(
                    "لا توجد كلمات مطابقة",
                    systemImage: "character.book.closed",
                    description: Text(L("أضف كلمات من الدروس أو غيّر البحث والتصفية."))
                )
            }

            ForEach(model.filtered) { card in
                NavigationLink {
                    WordDetailView(card: card) {
                        await model.load(repository: container.vocabularyRepository)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(card.word.english).font(.headline).environment(\.layoutDirection, .leftToRight)
                            if card.isFavorite {
                                Image(systemName: "star.fill").accessibilityLabel(L("مفضلة"))
                            }
                            Spacer()
                            Text("\(Int(card.confidence * 100))٪")
                                .font(.caption.monospacedDigit())
                        }
                        Text(card.word.arabic)
                        Text(card.word.example)
                            .font(.caption).foregroundStyle(.secondary)
                            .environment(\.layoutDirection, .leftToRight)
                        if !card.tags.isEmpty {
                            Text("التصنيفات: \(card.tags.joined(separator: "، "))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("المراجعة القادمة: \(card.dueDate, format: .dateTime.day().month().year())")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                .swipeActions(edge: .leading) {
                    Button {
                        Task {
                            await container.vocabularyRepository.updateMetadata(
                                cardID: card.id,
                                isFavorite: !card.isFavorite,
                                tags: card.tags,
                                note: card.note
                            )
                            await model.load(repository: container.vocabularyRepository)
                        }
                    } label: {
                        Label(card.isFavorite ? "إلغاء المفضلة" : "مفضلة", systemImage: card.isFavorite ? "star.slash" : "star")
                    }
                }
            }
        }
        .searchable(text: $model.query, prompt: L("ابحث بالكلمة أو المعنى أو الملاحظة"))
        .navigationTitle(L("قاموسي الشخصي"))
        .task { await model.load(repository: container.vocabularyRepository) }
        .refreshable { await model.load(repository: container.vocabularyRepository) }
    }
}

private struct WordDetailView: View {
    @EnvironmentObject private var container: AppContainer
    @Environment(\.dismiss) private var dismiss
    let card: ReviewCard
    let onChange: () async -> Void

    @State private var isFavorite: Bool
    @State private var tagsText: String
    @State private var note: String
    @State private var showDeleteConfirmation = false

    init(card: ReviewCard, onChange: @escaping () async -> Void) {
        self.card = card
        self.onChange = onChange
        _isFavorite = State(initialValue: card.isFavorite)
        _tagsText = State(initialValue: card.tags.joined(separator: "، "))
        _note = State(initialValue: card.note)
    }

    var body: some View {
        Form {
            Section(L("الكلمة")) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(card.word.english).font(.largeTitle.bold()).environment(\.layoutDirection, .leftToRight)
                        Text(card.word.arabic).font(.title2)
                        if let phonetic = card.word.phonetic { Text(phonetic).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button { container.textToSpeech.speak(card.word.english) } label: {
                        Image(systemName: "speaker.wave.2.fill").font(.title)
                    }
                    .accessibilityLabel("نطق \(card.word.english)")
                }
                Text(card.word.example).environment(\.layoutDirection, .leftToRight)
                Text(card.word.exampleArabic).foregroundStyle(.secondary)
            }

            Section(L("التنظيم")) {
                Toggle(L("إضافة إلى المفضلة"), isOn: $isFavorite)
                TextField(L("تصنيفات مفصولة بفواصل"), text: $tagsText, axis: .vertical)
                TextField(L("ملاحظة شخصية أو وسيلة تذكّر"), text: $note, axis: .vertical)
            }

            Section(L("التقدم")) {
                AccessibleProgressView(title: "درجة الإتقان \(Int(card.confidence * 100))٪", value: card.confidence)
                LabeledContent(L("عدد النجاحات المتتالية"), value: "\(card.repetitions)")
                LabeledContent(L("الفاصل الحالي"), value: "\(card.intervalDays) يوم")
                LabeledContent(L("المراجعة القادمة"), value: card.dueDate.formatted(date: .abbreviated, time: .omitted))
            }

            Section {
                Button(L("حفظ التعديلات")) {
                    Task {
                        let tags = tagsText
                            .replacingOccurrences(of: ",", with: "،")
                            .split(separator: "،")
                            .map(String.init)
                        await container.vocabularyRepository.updateMetadata(
                            cardID: card.id,
                            isFavorite: isFavorite,
                            tags: tags,
                            note: note
                        )
                        await onChange()
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button(L("حذف الكلمة من القاموس"), role: .destructive) {
                    showDeleteConfirmation = true
                }
            }
        }
        .navigationTitle(L("تفاصيل الكلمة"))
        .confirmationDialog("حذف \(card.word.english)؟", isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible) {
            Button(L("حذف"), role: .destructive) {
                Task {
                    await container.vocabularyRepository.remove(cardID: card.id)
                    await onChange()
                    ToastCenter.shared.show("تم حذف الكلمة", style: .info)
                    dismiss()
                }
            }
            Button(L("إلغاء"), role: .cancel) {}
        } message: {
            Text("سيُحذف \(card.word.english) من قاموسك.")
        }
    }
}
