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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(collection.beverages()) { beverage in
                        let route: DrinkRoute = collection == .toGo ? .toGo(beverage) : .beverage(beverage)
                        let recipe = model.initialRecipe(for: route)
                        NavigationLink(value: route) {
                            DrinkCard(recipe: recipe, isPersonal: model.activeProfile.personalDefaults[beverage] != nil)
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

/// A tile that opens a collection.
struct CollectionTile: View {
    let collection: DrinkCollection

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: collection.symbol)
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .frame(width: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(L("collection.count", collection.beverages().count))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(collection.title)
        .accessibilityValue(collection.summary)
        .accessibilityAddTraits(.isButton)
    }
}
