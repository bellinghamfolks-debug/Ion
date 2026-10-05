import SwiftUI

/// The machine's drink filters, matching the official app's filter chips.
enum DrinkFilter: String, CaseIterable, Identifiable {
    case all, favorites, custom, hot, cold, coldBrew, milkBased, coffeeBased
    var id: String { rawValue }
    var title: String { L("filter.\(rawValue)") }
}

/// The full menu, grouped by kind, with filter chips. Section titles are
/// VoiceOver headings so the rotor jumps between Coffee, With milk, Cold…
struct DrinksView: View {
    @Environment(AppModel.self) var model
    @State var query = ""
    @State var filter: DrinkFilter = .all
    @State var pendingBrew: Recipe?

    private var profile: UserProfile { model.activeProfile }

    private func matchesSearch(_ beverage: BeverageID) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        return beverage.name.localizedCaseInsensitiveContains(trimmed)
            || beverage.summary.localizedCaseInsensitiveContains(trimmed)
    }

    private func matchesFilter(_ beverage: BeverageID) -> Bool {
        let spec = beverage.spec
        switch filter {
        case .all: return true
        case .favorites: return profile.favorites.contains { $0.beverage == beverage }
        case .custom: return false   // custom drinks are listed separately below
        case .hot: return !spec.isCold
        case .cold: return spec.isCold
        case .coldBrew: return beverage.rawValue.lowercased().contains("coldbrew")
        case .milkBased: return spec.usesMilk
        case .coffeeBased: return spec.coffee != nil && !spec.usesMilk
        }
    }

    private func matches(_ beverage: BeverageID) -> Bool { matchesSearch(beverage) && matchesFilter(beverage) }

    private var customFavorites: [Recipe] {
        profile.favorites.filter { !$0.customName.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    filterChips
                    if filter == .custom || filter == .favorites {
                        customSection
                    }
                    if filter != .custom {
                        ForEach(BeverageCategory.allCases) { category in
                            let drinks = BeverageCatalog.beverages(in: category).filter(matches)
                            if !drinks.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    SectionTitle(text: category.title)
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                                        ForEach(drinks) { beverage in
                                            card(for: beverage)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if isEmptyResult {
                        Text(L("drinks.noResults"))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle(L("tab.drinks"))
            .searchable(text: $query, prompt: L("drinks.search"))
            .navigationDestination(for: DrinkRoute.self) { DrinkDetailView(route: $0, initial: model.initialRecipe(for: $0)) }
            .brewConfirmation(recipe: $pendingBrew)
        }
    }

    private var isEmptyResult: Bool {
        if filter == .custom { return customFavorites.isEmpty }
        return BeverageID.allCases.filter(matches).isEmpty && !(filter == .favorites && !customFavorites.isEmpty)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DrinkFilter.allCases) { option in
                    Button {
                        filter = option
                        Announcer.shared.announce(L("filter.selected", option.title))
                    } label: {
                        Text(option.title)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 40)
                            .background(Capsule().fill(option == filter ? Theme.accent : Theme.surfaceRaised))
                            .foregroundStyle(option == filter ? Theme.onAccent : Theme.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(option == filter ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityLabel(L("filter.title"))
    }

    @ViewBuilder
    private var customSection: some View {
        if !customFavorites.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: L("drinks.custom"))
                ForEach(customFavorites) { recipe in
                    Button { pendingBrew = recipe } label: { RecipeRow(recipe: recipe) }
                        .buttonStyle(.plain)
                        .accessibilityHint(L("home.favorite.hint"))
                }
            }
        }
    }

    private func card(for beverage: BeverageID) -> some View {
        let recipe = model.data.recipe(for: beverage)
        let isFavorite = profile.favorites.contains { $0.beverage == beverage && $0.customName.isEmpty }
        return NavigationLink(value: DrinkRoute.beverage(beverage)) {
            DrinkCard(recipe: recipe, isPersonal: profile.personalDefaults[beverage] != nil)
        }
        .buttonStyle(.plain)
        .accessibilityHint(L("drinks.card.hint"))
        .accessibilityAction(named: Text(L("action.brewNow"))) { pendingBrew = recipe }
        .accessibilityAction(named: Text(isFavorite ? L("action.alreadyFavorite") : L("action.addFavorite"))) {
            addFavorite(recipe)
        }
        .contextMenu {
            Button(L("action.brewNow"), systemImage: "cup.and.saucer.fill") { pendingBrew = recipe }
            Button(L("action.addFavorite"), systemImage: "star") { addFavorite(recipe) }
        }
    }

    private func addFavorite(_ recipe: Recipe) {
        var copy = recipe
        copy.id = UUID()
        var saved = false
        model.updateData { saved = $0.saveFavorite(copy) }
        Announcer.shared.announce(saved ? L("announce.favoriteSaved", recipe.displayName) : L("announce.favoriteExists"))
    }
}
