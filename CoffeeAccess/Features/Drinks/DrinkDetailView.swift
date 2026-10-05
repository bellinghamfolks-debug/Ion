import SwiftUI

/// Customize a drink, then brew it, save it as a favorite or make it this
/// profile's default. Every control is one adjustable VoiceOver element and
/// the summary sentence always says the full recipe.
struct DrinkDetailView: View {
    @Environment(AppModel.self) var model
    @Environment(\.dismiss) var dismiss
    let route: DrinkRoute

    @State var recipe: Recipe
    @State var pendingBrew: Recipe?
    @State var namingFavorite = false
    @State var favoriteName = ""
    @State var confirmReset = false

    init(route: DrinkRoute, initial: Recipe) {
        self.route = route
        _recipe = State(initialValue: initial)
    }

    private var spec: BeverageSpec { recipe.spec }
    private var editingFavorite: Bool { if case .favorite = route { return true } else { return false } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                controls
                summary
                actions
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(recipe.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .brewConfirmation(recipe: $pendingBrew)
        .alert(L("favorite.name.title"), isPresented: $namingFavorite) {
            TextField(L("favorite.name.placeholder"), text: $favoriteName)
            Button(L("action.save")) { saveFavorite() }
            Button(L("action.cancel"), role: .cancel) {}
        } message: {
            Text(L("favorite.name.message"))
        }
        .confirmationDialog(L("drink.reset.title"), isPresented: $confirmReset, titleVisibility: .visible) {
            Button(L("drink.reset.confirm"), role: .destructive) { resetToStandard() }
            Button(L("action.cancel"), role: .cancel) {}
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            DrinkIllustration(beverage: recipe.beverage, fill: fillLevel)
                .frame(maxWidth: 220)
                .frame(maxWidth: .infinity)
            Text(recipe.displayName)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            Text(recipe.beverage.summary)
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if spec.ecamCode == nil, model.settings.linkKind == .bluetooth {
                Label(L("drink.bluetoothUnsupported"), systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
            }
        }
    }

    /// The cup in the picture fills in proportion to the chosen volume.
    private var fillLevel: Double {
        let maxVolume = (spec.coffee?.max ?? 0) + (spec.water?.max ?? 0) + (spec.milk?.max ?? 0) * 15 / 2
        guard maxVolume > 0 else { return 1 }
        return min(1, max(0.35, Double(recipe.approximateVolumeML) / Double(maxVolume) * 1.6))
    }

    @ViewBuilder
    private var controls: some View {
        if let range = spec.coffee {
            QuantityControl(title: L("param.coffee"), symbol: "cup.and.saucer", value: binding(\.coffeeML, fallback: range.standard),
                            range: range, unitKey: "unit.ml")
        }
        if let range = spec.water {
            QuantityControl(title: L("param.water"), symbol: "drop", value: binding(\.waterML, fallback: range.standard),
                            range: range, unitKey: "unit.ml")
        }
        if let range = spec.milk {
            QuantityControl(title: L("param.milk"), symbol: "carton", value: binding(\.milkSeconds, fallback: range.standard),
                            range: range, unitKey: "unit.seconds")
        }
        if spec.hasAroma {
            LevelControl(title: L("param.aroma"), symbol: "leaf", levels: Aroma.allCases,
                         selection: Binding(get: { recipe.aroma ?? spec.defaultAroma }, set: { recipe.aroma = $0 }),
                         name: \.title)
        }
        if spec.hasTemperature {
            LevelControl(title: L("param.temperature"), symbol: "thermometer.medium", levels: BrewTemperature.allCases,
                         selection: Binding(get: { recipe.temperature ?? spec.defaultTemperature }, set: { recipe.temperature = $0 }),
                         name: \.title)
        }
        if spec.supportsMilkFirst {
            Toggle(isOn: $recipe.milkFirst) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("param.milkFirst")).font(.headline)
                    Text(L("param.milkFirst.detail")).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            }
            .tint(Theme.accent)
            .padding(16)
            .card()
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("drink.summary.title"))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(recipe.spokenSummary)
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
            Text(L("drink.summary.time", recipe.estimatedSeconds))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(raised: true)
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                pendingBrew = recipe
            } label: {
                Label(L("action.brewNow"), systemImage: "cup.and.saucer.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.session?.isRunning == true)

            if editingFavorite {
                Button(L("favorite.saveChanges")) { saveChanges() }
                    .buttonStyle(SecondaryButtonStyle())
            } else {
                Button(L("action.addFavorite")) {
                    favoriteName = ""
                    namingFavorite = true
                }
                .buttonStyle(SecondaryButtonStyle())
                Button(L("drink.makeDefault")) { makeDefault() }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityHint(L("drink.makeDefault.hint", model.activeProfile.name))
            }
            if !recipe.isStandard {
                Button(L("drink.reset")) { confirmReset = true }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.top, 6)
    }

    private func binding(_ keyPath: WritableKeyPath<Recipe, Int?>, fallback: Int) -> Binding<Int> {
        Binding(get: { recipe[keyPath: keyPath] ?? fallback }, set: { recipe[keyPath: keyPath] = $0 })
    }

    private func saveFavorite() {
        var favorite = recipe
        favorite.id = UUID()
        favorite.customName = favoriteName
        var saved = false
        model.updateData { saved = $0.saveFavorite(favorite) }
        Announcer.shared.announce(saved ? L("announce.favoriteSaved", favorite.normalized().displayName) : L("announce.favoriteExists"))
    }

    private func saveChanges() {
        model.updateData { _ = $0.saveFavorite(recipe) }
        Announcer.shared.announce(L("announce.favoriteUpdated", recipe.displayName))
        dismiss()
    }

    private func makeDefault() {
        model.updateData { $0.setPersonalDefault(recipe) }
        Announcer.shared.announce(L("announce.defaultSaved", recipe.beverage.name, model.activeProfile.name))
    }

    private func resetToStandard() {
        var standard = Recipe.standard(recipe.beverage)
        standard.id = recipe.id
        standard.customName = recipe.customName
        recipe = standard
        if !editingFavorite { model.updateData { $0.resetPersonalDefault(recipe.beverage) } }
        Announcer.shared.announce(L("announce.resetDone"))
    }
}
