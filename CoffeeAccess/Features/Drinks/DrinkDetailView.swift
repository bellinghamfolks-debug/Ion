import SwiftUI

/// Customize a drink, then brew it, save it as a favorite / personal recipe
/// or make it this profile's default. Every control is one adjustable
/// VoiceOver element and the summary sentence always says the full recipe.
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
    private var creatingRecipe: Bool { if case .newRecipe = route { return true } else { return false } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if creatingRecipe { nameField }
                controls
                beanTip
                summary
                actions
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(creatingRecipe ? L("recipe.new.title") : recipe.displayName)
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
            DrinkIllustration(beverage: recipe.beverage, fill: fillLevel, toGo: recipe.toGo)
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
            if model.data.guestMode {
                Label(L("guest.banner"), systemImage: "person.crop.circle.badge.questionmark")
                    .font(.footnote)
                    .foregroundStyle(Theme.accent)
            }
            if spec.ecamCode == nil, model.settings.linkKind == .bluetooth {
                Label(L("drink.bluetoothUnsupported"), systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("recipe.new.name")).font(.headline).foregroundStyle(Theme.textPrimary)
            TextField(L("favorite.name.placeholder"), text: $favoriteName)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
            Text(L("recipe.new.hint", recipe.beverage.name))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(16)
        .card()
    }

    /// The cup in the picture fills in proportion to the chosen volume.
    private var fillLevel: Double {
        let maxVolume = (recipe.coffeeRange?.max ?? 0) + (recipe.waterRange?.max ?? 0) + (recipe.milkRange?.max ?? 0) * 15 / 2
        guard maxVolume > 0 else { return 1 }
        return min(1, max(0.35, Double(recipe.approximateVolumeML) / Double(maxVolume) * 1.6))
    }

    @ViewBuilder
    private var controls: some View {
        if spec.supportsToGo {
            Toggle(isOn: Binding(get: { recipe.toGo }, set: { recipe = recipe.withToGo($0); Announcer.shared.tick() })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("param.toGo")).font(.headline)
                    Text(L("param.toGo.detail")).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            }
            .tint(Theme.accent)
            .padding(16)
            .card()
        }
        if let range = recipe.coffeeRange {
            QuantityControl(title: spec.vessel == .pot ? L("param.potSize") : L("param.coffee"), symbol: "cup.and.saucer",
                            value: binding(\.coffeeML, fallback: range.standard), range: range, unitKey: "unit.ml")
        }
        if let range = recipe.waterRange {
            QuantityControl(title: spec.isTea ? L("param.teaWater") : L("param.water"), symbol: "drop",
                            value: binding(\.waterML, fallback: range.standard), range: range, unitKey: "unit.ml")
        }
        if let range = recipe.milkRange {
            QuantityControl(title: spec.isCold ? L("param.coldMilk") : L("param.milk"), symbol: "carton",
                            value: binding(\.milkSeconds, fallback: range.standard), range: range, unitKey: "unit.seconds")
        }
        if spec.supportsColdIntensity {
            LevelControl(title: L("cold.intensity.title"), symbol: "drop.degreesign",
                         levels: ColdIntensity.allCases,
                         selection: Binding(get: { recipe.coldIntensity ?? .original }, set: { recipe.coldIntensity = $0 }),
                         name: \.title)
        }
        if spec.supportsIce {
            LevelControl(title: L("cold.ice.title"), symbol: "snowflake",
                         levels: IceLevel.allCases,
                         selection: Binding(get: { recipe.iceLevel ?? .ice }, set: { recipe.iceLevel = $0 }),
                         name: \.title)
        }
        if spec.hasAroma {
            LevelControl(title: L("param.aroma"), symbol: "leaf", levels: Aroma.allCases,
                         selection: Binding(get: { recipe.aroma ?? spec.defaultAroma }, set: { recipe.aroma = $0 }),
                         name: \.title)
        }
        if spec.hasTemperature {
            LevelControl(title: spec.isTea ? L("param.teaTemperature") : L("param.temperature"), symbol: "thermometer.medium",
                         levels: BrewTemperature.allCases,
                         selection: Binding(get: { recipe.temperature ?? spec.defaultTemperature }, set: { recipe.temperature = $0 }),
                         name: { spec.isTea ? $0.teaTitle : $0.title })
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
        if spec.supportsExtraShot {
            Toggle(isOn: $recipe.extraShot) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("param.extraShot")).font(.headline)
                    Text(L("param.extraShot.detail")).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            }
            .tint(Theme.accent)
            .padding(16)
            .card()
        }
        if let foam = recipe.idealFoamLevel {
            Label(L("foam.hint", foam.title), systemImage: "dial.medium")
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .card(raised: true)
                .accessibilityLabel(L("foam.hint", foam.title))
        }
    }

    @ViewBuilder
    private var beanTip: some View {
        if let bean = model.data.activeBean, recipe.coffeeML != nil {
            Label(L("bean.tip", bean.name, bean.recommendedGrind), systemImage: "leaf.circle")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 4)
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
                pendingBrew = creatingRecipe ? named(recipe) : recipe
            } label: {
                Label(L("action.brewNow"), systemImage: "cup.and.saucer.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.session?.isRunning == true)

            if creatingRecipe {
                Button(L("recipe.new.save")) { saveNewRecipe() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.data.guestMode)
            } else if editingFavorite {
                Button(L("favorite.saveChanges")) { saveChanges() }
                    .buttonStyle(SecondaryButtonStyle())
            } else if !model.data.guestMode {
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

    private func named(_ recipe: Recipe) -> Recipe {
        var copy = recipe
        copy.customName = favoriteName
        return copy
    }

    private func saveFavorite() {
        var favorite = named(recipe)
        favorite.id = UUID()
        var saved = false
        model.updateData { saved = $0.saveFavorite(favorite) }
        Announcer.shared.announce(saved ? L("announce.favoriteSaved", favorite.normalized().displayName) : L("announce.favoriteExists"))
    }

    private func saveNewRecipe() {
        guard !favoriteName.trimmingCharacters(in: .whitespaces).isEmpty else {
            Announcer.shared.announce(L("recipe.new.needsName"), priority: .high)
            return
        }
        saveFavorite()
        dismiss()
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
        var standard = Recipe.standard(recipe.beverage, toGo: recipe.toGo)
        standard.id = recipe.id
        standard.customName = recipe.customName
        recipe = standard
        if !editingFavorite && !creatingRecipe { model.updateData { $0.resetPersonalDefault(recipe.beverage) } }
        Announcer.shared.announce(L("announce.resetDone"))
    }
}
