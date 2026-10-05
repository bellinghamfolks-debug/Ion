import SwiftUI

/// One of the seven collections: drinks grouped by mood or moment.
struct CollectionView: View {
    @Environment(AppModel.self) var model
    let collection: DrinkCollection
    @State var pendingBrew: Recipe?

    init(collection: DrinkCollection) {
        self.collection = collection
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(collection.summary)
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: 12)], spacing: 12) {
                    ForEach(collection.beverages()) { beverage in
                        let route: DrinkRoute = collection == .toGo ? .toGo(beverage) : .beverage(beverage)
                        let recipe = model.initialRecipe(for: route)
                        NavigationLink(value: route) {
                            DrinkCard(recipe: recipe, isPersonal: model.activeProfile.personalDefaults[beverage] != nil,
                                      isFavorite: model.activeProfile.favorites.contains { $0.beverage == beverage && $0.customName.isEmpty })
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(L("drinks.card.hint"))
                        .accessibilityAction(named: Text(L("action.brewNow"))) { pendingBrew = recipe }
                    }
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(collection.title)
        .brewConfirmation(recipe: $pendingBrew)
    }
}

/// A tile that opens a collection: a glass from it, the name and the count.
struct CollectionTile: View {
    let collection: DrinkCollection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: collection.symbol)
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.surfaceRaised))
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                if let first = collection.beverages().first {
                    DrinkIllustration(beverage: first, showsSteam: false, toGo: collection == .toGo)
                        .frame(width: 64, height: 64)
                }
            }
            Text(collection.title)
                .font(.display(.headline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("collection.count", collection.beverages().count))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(collection.title)
        .accessibilityValue(collection.summary)
        .accessibilityAddTraits(.isButton)
    }
}
