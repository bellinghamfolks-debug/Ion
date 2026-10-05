import SwiftUI

/// The full menu, grouped by kind. Section titles are VoiceOver headings so
/// the rotor jumps between Coffee, With milk, Cold and Other.
struct DrinksView: View {
    @Environment(AppModel.self) var model
    @State var query = ""
    @State var pendingBrew: Recipe?

    private var profile: UserProfile { model.activeProfile }

    private func matches(_ beverage: BeverageID) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        return beverage.name.localizedCaseInsensitiveContains(trimmed)
            || beverage.summary.localizedCaseInsensitiveContains(trimmed)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
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
                    if BeverageID.allCases.filter(matches).isEmpty {
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

    private func card(for beverage: BeverageID) -> some View {
        let recipe = profile.recipe(for: beverage)
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
