import SwiftUI
import UIKit
import Vision

// MARK: - My cups

/// The person's cups and mugs with their sizes, so the app can say which
/// cup a drink fits and warn before one overflows.
struct CupsView: View {
    @Environment(AppModel.self) var model
    @State var name = ""
    @State var capacity = 200

    var body: some View {
        ProForm(title: L("screen.cups")) {
            Section {
                ForEach(model.data.life.pro.cups) { cup in
                    LabeledContent(cup.name, value: L("unit.ml", cup.capacityML))
                        .accessibilityAction(named: Text(L("action.delete"))) { delete(cup) }
                }
                .onDelete { offsets in model.updateData { $0.life.pro.cups.remove(atOffsets: offsets) } }
                if model.data.life.pro.cups.isEmpty { Text(L("cups.empty")).foregroundStyle(Theme.textSecondary) }
            } footer: { Text(L("cups.footer")) }
            Section(L("cups.add")) {
                TextField(L("cups.name"), text: $name)
                Stepper(value: $capacity, in: 30...600, step: 10) {
                    LabeledContent(L("cups.capacity"), value: L("unit.ml", capacity))
                }
                Button(L("action.save")) {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    model.updateData { $0.life.pro.cups.append(CupProfile(name: trimmed, capacityML: capacity)) }
                    Announcer.shared.announce(L("cups.saved", trimmed))
                    name = ""
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Section {
                NavigationLink { CupCheckView() } label: { Label(L("screen.cupCheck"), systemImage: "camera.viewfinder") }
            }
        }
    }

    private func delete(_ cup: CupProfile) {
        model.updateData { $0.life.pro.cups.removeAll { $0.id == cup.id } }
    }
}

/// Experimental: a photo of the drip tray area says whether a cup or mug
/// seems to be under the spout. On-device image classification; it can be
/// wrong, so it only ever advises.
struct CupCheckView: View {
    @State var picking = false
    @State var result: String?
    @State var checking = false

    var body: some View {
        ProForm(title: L("screen.cupCheck")) {
            Section {
                Text(L("cupCheck.intro"))
                Button { picking = true } label: { Label(L("cupCheck.take"), systemImage: "camera") }
                if checking { ProgressView() }
                if let result {
                    Text(result).font(.headline).accessibilityAddTraits(.updatesFrequently)
                }
            } footer: { Text(L("experimental.footer")) }
        }
        .sheet(isPresented: $picking) {
            ImagePicker { image in
                picking = false
                guard let image else { return }
                checking = true
                Task {
                    let found = await CupClassifier.cupLikelihood(in: image)
                    checking = false
                    result = found.map { $0 >= 0.3 ? L("cupCheck.yes") : L("cupCheck.no") } ?? L("cupCheck.unsure")
                    Announcer.shared.announce(result ?? "", priority: .high)
                }
            }
            .ignoresSafeArea()
        }
    }
}

enum CupClassifier {
    static let cupWords = ["cup", "mug", "coffee_mug", "teacup", "espresso", "glass", "tumbler", "saucer", "beaker", "coffee"]

    /// The highest confidence among cup-like labels, or nil if it failed.
    static func cupLikelihood(in image: UIImage) async -> Double? {
        guard let cgImage = image.cgImage else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNClassifyImageRequest()
                do {
                    try VNImageRequestHandler(cgImage: cgImage, orientation: .up).perform([request])
                    let labels = request.results ?? []
                    let best = labels.filter { label in cupWords.contains { label.identifier.lowercased().contains($0) } }
                        .map { Double($0.confidence) }.max() ?? 0
                    continuation.resume(returning: best)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - Tea timer

/// After hot water: steep the tea, with a spoken count and a sound at the end.
struct TeaTimerView: View {
    enum Tea: String, CaseIterable, Identifiable {
        case green, black, herbal, white, rooibos
        var id: String { rawValue }
        var title: String { L("tea.\(rawValue)") }
        /// Minutes to steep and the water temperature advice.
        var minutes: Int {
            switch self {
            case .green: return 2
            case .white: return 3
            case .black: return 4
            case .herbal, .rooibos: return 6
            }
        }
    }

    @State var tea: Tea = .black
    @State var remaining: Int?
    @State var task: Task<Void, Never>?

    var body: some View {
        ProForm(title: L("screen.teaTimer")) {
            Section {
                Picker(L("tea.kind"), selection: $tea) { ForEach(Tea.allCases) { Text($0.title).tag($0) } }
                Text(L("tea.advice.\(tea.rawValue)")).font(.footnote)
            }
            Section {
                if let remaining {
                    Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                        .font(.largeTitle.monospacedDigit().weight(.bold))
                        .accessibilityAddTraits(.updatesFrequently)
                    Button(L("tea.stop"), role: .destructive) { stop() }
                } else {
                    Button(L("tea.start", tea.minutes)) { start() }.buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        let total = tea.minutes * 60
        remaining = total
        Announcer.shared.announce(L("tea.started", tea.minutes))
        NotificationManager.shared.scheduleTimer(id: "tea", title: L("tea.done.title"), body: L("tea.done.body", tea.title), seconds: total)
        task = Task { @MainActor in
            for left in stride(from: total - 1, through: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                remaining = left
                if left > 0, left % 60 == 0 { Announcer.shared.announce(L("tea.minutesLeft", left / 60)) }
            }
            remaining = nil
            Announcer.shared.success()
            Announcer.shared.announce(L("tea.done.body", tea.title), priority: .high)
            Tones.shared.cue(.ready)
        }
    }

    private func stop() {
        task?.cancel()
        task = nil
        remaining = nil
        NotificationManager.shared.cancelTimer(id: "tea")
    }
}

// MARK: - Favorites: tags, duplicates, versions, milk and additions

struct FavoritesOrganizerView: View {
    @Environment(AppModel.self) var model
    @State var tagFilter: String?

    private var allTags: [String] {
        Array(Set(model.data.life.pro.favoriteTags.values.flatMap { $0 })).sorted()
    }

    var body: some View {
        let favorites = model.activeProfile.favorites.filter { recipe in
            guard let tagFilter else { return true }
            return model.data.life.pro.favoriteTags[recipe.id]?.contains(tagFilter) == true
        }
        ProForm(title: L("screen.organizer")) {
            if !allTags.isEmpty {
                Section(L("organizer.filter")) {
                    Picker(L("organizer.tag"), selection: $tagFilter) {
                        Text(L("organizer.allTags")).tag(String?.none)
                        ForEach(allTags, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                }
            }
            Section {
                ForEach(favorites) { recipe in
                    NavigationLink { FavoriteDetailsEditor(recipeID: recipe.id) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(recipe.displayName).font(.headline)
                            let tags = model.data.life.pro.favoriteTags[recipe.id] ?? []
                            if !tags.isEmpty { Text(tags.joined(separator: L("list.separator"))).font(.footnote).foregroundStyle(Theme.textSecondary) }
                        }
                    }
                    .accessibilityAction(named: Text(L("organizer.duplicate"))) { duplicate(recipe) }
                    .swipeActions(edge: .leading) { Button(L("organizer.duplicate")) { duplicate(recipe) } }
                }
                if favorites.isEmpty { Text(L("home.favorites.empty")).foregroundStyle(Theme.textSecondary) }
            } footer: { Text(L("organizer.footer")) }
        }
    }

    private func duplicate(_ recipe: Recipe) {
        FavoriteTools.duplicate(recipe, model: model)
    }
}

enum FavoriteTools {
    @MainActor
    static func duplicate(_ recipe: Recipe, model: AppModel) {
        var copy = recipe
        copy.id = UUID()
        copy.customName = L("organizer.copyName", recipe.displayName)
        model.updateData { data in
            _ = data.saveFavorite(copy)
            data.life.pro.favoriteTags[copy.id] = data.life.pro.favoriteTags[recipe.id]
            data.life.pro.milkTypes[copy.id] = data.life.pro.milkTypes[recipe.id]
            data.life.pro.additions[copy.id] = data.life.pro.additions[recipe.id]
        }
        Announcer.shared.announce(L("organizer.duplicated", copy.displayName))
    }
}

/// Tags, milk, "add after brewing" note and earlier versions of one favorite.
struct FavoriteDetailsEditor: View {
    @Environment(AppModel.self) var model
    let recipeID: UUID
    @State var newTag = ""
    @State var addition = ""

    private var recipe: Recipe? { model.activeProfile.favorites.first { $0.id == recipeID } }

    var body: some View {
        ProForm(title: recipe?.displayName ?? "") {
            if let recipe {
                Section(L("organizer.tags")) {
                    let tags = model.data.life.pro.favoriteTags[recipeID] ?? []
                    ForEach(tags, id: \.self) { tag in
                        Text(tag).accessibilityAction(named: Text(L("action.delete"))) { removeTag(tag) }
                    }
                    .onDelete { offsets in
                        model.updateData { $0.life.pro.favoriteTags[recipeID]?.remove(atOffsets: offsets) }
                    }
                    HStack {
                        TextField(L("organizer.newTag"), text: $newTag).onSubmit(addTag)
                        Button(L("action.add"), action: addTag).disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if recipe.spec.usesMilk {
                    Section {
                        Picker(L("milk.title"), selection: Binding(
                            get: { model.data.life.pro.milkTypes[recipeID] ?? model.data.life.pro.milk(for: recipe, profileID: model.activeProfile.id) },
                            set: { value in model.updateData { $0.life.pro.milkTypes[recipeID] = value } })) {
                            ForEach(MilkType.allCases) { Text($0.title).tag($0) }
                        }
                        let milk = model.data.life.pro.milk(for: recipe, profileID: model.activeProfile.id)
                        if let tip = milk.foamTip { Text(tip).font(.footnote) }
                        LabeledContent(L("nutrition.calories"), value: L("nutrition.kcal", Nutrition.calories(for: recipe, milk: milk)))
                    }
                }
                Section {
                    TextField(L("additions.placeholder"), text: $addition, axis: .vertical)
                    Button(L("action.save")) {
                        model.updateData { $0.life.pro.additions[recipeID] = addition.trimmingCharacters(in: .whitespacesAndNewlines) }
                        Announcer.shared.announce(L("announce.saved"))
                    }
                } header: { Text(L("additions.title")) } footer: { Text(L("additions.footer")) }
                Section {
                    let versions = model.data.life.pro.recipeVersions[recipeID] ?? []
                    if versions.isEmpty { Text(L("versions.none")).foregroundStyle(Theme.textSecondary) }
                    ForEach(versions) { version in
                        Button {
                            restore(version, current: recipe)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(version.savedAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                                Text(version.recipe.spokenSummary).font(.footnote).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .accessibilityHint(L("versions.restore.hint"))
                    }
                } header: { Text(L("versions.title")) } footer: { Text(L("versions.footer")) }
                Section {
                    Button(L("organizer.duplicate")) { FavoriteTools.duplicate(recipe, model: model) }
                }
            }
        }
        .onAppear { addition = model.data.life.pro.additions[recipeID] ?? "" }
    }

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty else { return }
        model.updateData { data in
            var tags = data.life.pro.favoriteTags[recipeID] ?? []
            if !tags.contains(tag) { tags.append(tag) }
            data.life.pro.favoriteTags[recipeID] = tags
        }
        newTag = ""
        Announcer.shared.announce(L("organizer.tagAdded", tag))
    }

    private func removeTag(_ tag: String) {
        model.updateData { $0.life.pro.favoriteTags[recipeID]?.removeAll { $0 == tag } }
    }

    /// Undo: the chosen version comes back, and the current one is kept as a version.
    private func restore(_ version: RecipeVersion, current: Recipe) {
        var restored = version.recipe
        restored.id = recipeID
        model.updateData { data in
            data.life.pro.rememberVersion(of: current)
            _ = data.saveFavorite(restored)
        }
        Announcer.shared.announce(L("versions.restored", restored.displayName))
    }
}

// MARK: - Combos

struct CombosView: View {
    @Environment(AppModel.self) var model
    @State var editing: DrinkCombo?

    var body: some View {
        ProForm(title: L("screen.combos")) {
            Section {
                ForEach(model.data.life.pro.combos) { combo in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(combo.name).font(.headline)
                        Text(combo.steps.map(\.displayName).joined(separator: " → ")).font(.footnote).foregroundStyle(Theme.textSecondary)
                        Button(L("combo.run")) { Task { await model.runCombo(combo) } }
                            .buttonStyle(PillButtonStyle())
                            .disabled(model.session?.isRunning == true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAction(named: Text(L("combo.run"))) { Task { await model.runCombo(combo) } }
                    .accessibilityAction(named: Text(L("action.edit"))) { editing = combo }
                    .swipeActions { Button(L("action.edit")) { editing = combo } }
                }
                .onDelete { offsets in model.updateData { $0.life.pro.combos.remove(atOffsets: offsets) } }
                if model.data.life.pro.combos.isEmpty { Text(L("combo.empty")).foregroundStyle(Theme.textSecondary) }
            } footer: { Text(L("combo.footer")) }
            Section {
                Button { editing = DrinkCombo(name: "", steps: [Recipe.standard(.espresso), Recipe.standard(.hotWater)]) } label: {
                    Label(L("combo.add"), systemImage: "plus")
                }
            }
        }
        .sheet(item: $editing) { combo in
            ComboEditor(combo: combo) { saved in
                model.updateData { data in
                    if let index = data.life.pro.combos.firstIndex(where: { $0.id == saved.id }) { data.life.pro.combos[index] = saved }
                    else { data.life.pro.combos.append(saved) }
                }
            }
        }
    }
}

struct ComboEditor: View {
    @Environment(\.dismiss) var dismiss
    @State var combo: DrinkCombo
    let onSave: (DrinkCombo) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("combo.name"), text: $combo.name)
                ForEach(Array(combo.steps.enumerated()), id: \.offset) { index, _ in
                    Section(L("combo.step", index + 1)) {
                        RecipePicker(recipe: Binding(
                            get: { combo.steps[safe: index] ?? Recipe.standard(.espresso) },
                            set: { if combo.steps.indices.contains(index) { combo.steps[index] = $0 } }))
                        if combo.steps.count > 2 {
                            Button(L("action.delete"), role: .destructive) { combo.steps.remove(at: index) }
                        }
                    }
                }
                if combo.steps.count < 4 {
                    Button { combo.steps.append(Recipe.standard(.hotWater)) } label: { Label(L("combo.addStep"), systemImage: "plus") }
                }
            }
            .navigationTitle(L("combo.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("action.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("action.save")) {
                        if combo.name.trimmingCharacters(in: .whitespaces).isEmpty {
                            combo.name = combo.steps.map(\.displayName).joined(separator: " + ")
                        }
                        onSave(combo)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - The usual, this time only

/// "Stronger", "bigger"… applied to the usual drink once, without saving.
struct OneTimeTweakRow: View {
    let usual: Recipe
    @Binding var pendingBrew: Recipe?

    var body: some View {
        let tweaks = OneTimeTweak.allCases.filter { $0.applies(to: usual) }
        if !tweaks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("tweak.title")).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tweaks) { tweak in
                            Button(tweak.title) { pendingBrew = tweak.applied(to: usual) }
                                .buttonStyle(PillButtonStyle())
                                .accessibilityLabel(L("tweak.label", tweak.title, usual.displayName))
                        }
                    }
                }
            }
        }
    }
}
