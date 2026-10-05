import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) var model
    @Binding var selectedTab: AppTab
    @State var path = NavigationPath()
    @State var pendingBrew: Recipe?
    @State var pickingBase = false

    private var profile: UserProfile { model.activeProfile }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    MachineStatusCard()
                    if model.data.guestMode { guestBanner }
                    if !model.data.guestMode { favoritesSection }
                    collectionsSection
                    if !model.data.guestMode { frequentSection }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle(model.data.guestMode ? L("guest.title") : greeting)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ProfileMenu() }
            }
            .navigationDestination(for: MaintenanceGuideID.self) { GuideView(guide: $0) }
            .navigationDestination(for: DrinkCollection.self) { CollectionView(collection: $0) }
            .navigationDestination(for: DrinkRoute.self) { route in
                DrinkDetailView(route: route, initial: model.initialRecipe(for: route))
            }
            .brewConfirmation(recipe: $pendingBrew)
            .sheet(isPresented: $pickingBase) {
                BasePickerView { beverage in
                    pickingBase = false
                    path.append(DrinkRoute.newRecipe(beverage))
                }
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let key = hour < 12 ? "home.greeting.morning" : (hour < 18 ? "home.greeting.afternoon" : "home.greeting.evening")
        return L(key, profile.name)
    }

    private var guestBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("guest.banner"), systemImage: "person.crop.circle.badge.questionmark")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Button(L("guest.exit")) { model.setGuestMode(false) }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(16)
        .card(raised: true)
    }

    @ViewBuilder
    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: L("home.favorites"))
            if profile.favorites.isEmpty {
                Text(L("home.favorites.empty"))
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                ForEach(profile.favorites) { recipe in
                    Button { pendingBrew = recipe } label: { RecipeRow(recipe: recipe) }
                        .buttonStyle(.plain)
                        .accessibilityHint(L("home.favorite.hint"))
                        .accessibilityAction(named: Text(L("action.edit"))) { path.append(DrinkRoute.favorite(recipe)) }
                        .accessibilityAction(named: Text(L("action.moveUp"))) { move(recipe, by: -1) }
                        .accessibilityAction(named: Text(L("action.moveDown"))) { move(recipe, by: 1) }
                        .accessibilityAction(named: Text(L("action.delete"))) { deleteFavorite(recipe) }
                        .contextMenu {
                            Button(L("action.brewNow"), systemImage: "cup.and.saucer.fill") { pendingBrew = recipe }
                            Button(L("action.edit"), systemImage: "slider.horizontal.3") { path.append(DrinkRoute.favorite(recipe)) }
                            Button(L("action.moveUp"), systemImage: "arrow.up") { move(recipe, by: -1) }
                            Button(L("action.moveDown"), systemImage: "arrow.down") { move(recipe, by: 1) }
                            Button(L("action.delete"), systemImage: "trash", role: .destructive) { deleteFavorite(recipe) }
                        }
                }
            }
            Button {
                pickingBase = true
            } label: {
                Label(L("recipe.new.button"), systemImage: "plus.circle.fill")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: L("home.collections"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(DrinkCollection.allCases) { collection in
                    NavigationLink(value: collection) { CollectionTile(collection: collection) }
                        .buttonStyle(.plain)
                }
            }
            Button(L("home.allDrinks")) { selectedTab = .drinks }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    @ViewBuilder
    private var frequentSection: some View {
        let frequent = model.data.frequentRecipes()
        if !frequent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: L("home.frequent"))
                ForEach(frequent) { recipe in
                    Button { pendingBrew = recipe } label: { RecipeRow(recipe: recipe) }
                        .buttonStyle(.plain)
                        .accessibilityHint(L("home.favorite.hint"))
                }
            }
        }
    }

    private func move(_ recipe: Recipe, by offset: Int) {
        guard let index = profile.favorites.firstIndex(where: { $0.id == recipe.id }) else { return }
        let target = index + offset
        guard profile.favorites.indices.contains(target) else { return }
        model.updateData { $0.moveFavorite(from: IndexSet(integer: index), to: offset > 0 ? target + 1 : target) }
        Announcer.shared.announce(L("announce.moved", recipe.displayName, target + 1))
    }

    private func deleteFavorite(_ recipe: Recipe) {
        model.updateData { $0.removeFavorite(id: recipe.id) }
        Announcer.shared.announce(L("announce.favoriteDeleted", recipe.displayName))
    }
}

/// Picks the drink a new personal recipe starts from.
struct BasePickerView: View {
    let onPick: (BeverageID) -> Void
    @Environment(\.dismiss) var dismiss

    init(onPick: @escaping (BeverageID) -> Void) {
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(BeverageCategory.allCases) { category in
                    Section(category.title) {
                        ForEach(BeverageCatalog.beverages(in: category)) { beverage in
                            Button {
                                onPick(beverage)
                            } label: {
                                HStack(spacing: 12) {
                                    DrinkIllustration(beverage: beverage, showsSteam: false).frame(width: 40, height: 40)
                                    Text(beverage.name).foregroundStyle(Theme.textPrimary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(L("recipe.new.pickBase"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("action.cancel")) { dismiss() } }
            }
        }
    }
}

/// Switches between the four profiles from the navigation bar.
struct ProfileMenu: View {
    @Environment(AppModel.self) var model

    var body: some View {
        Menu {
            ForEach(model.data.profiles) { profile in
                Button {
                    if model.data.guestMode { model.setGuestMode(false) }
                    model.selectProfile(profile.id)
                } label: {
                    if profile.id == model.data.activeProfileID && !model.data.guestMode {
                        Label(profile.name, systemImage: "checkmark")
                    } else {
                        Text(profile.name)
                    }
                }
            }
            Divider()
            Button {
                model.setGuestMode(!model.data.guestMode)
            } label: {
                if model.data.guestMode {
                    Label(L("guest.title"), systemImage: "checkmark")
                } else {
                    Text(L("guest.title"))
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.profileColors[model.activeProfile.colorIndex % Theme.profileColors.count])
                    .frame(width: 26, height: 26)
                    .overlay(Text(String(model.activeProfile.name.prefix(1))).font(.caption.bold()).foregroundStyle(.white))
                Image(systemName: "chevron.down").font(.caption)
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(L("profile.switch"))
        .accessibilityValue(model.data.guestMode ? L("guest.title") : model.activeProfile.name)
    }
}

/// Where a drink screen comes from: the menu (standard or personal default)
/// or an existing favorite being edited.
enum DrinkRoute: Hashable {
    case beverage(BeverageID)
    case toGo(BeverageID)
    case favorite(Recipe)
    /// Start a new personal recipe from this drink.
    case newRecipe(BeverageID)
}

extension View {
    /// Asks before brewing (when enabled) and reads the full recipe aloud.
    func brewConfirmation(recipe: Binding<Recipe?>) -> some View {
        modifier(BrewConfirmation(recipe: recipe))
    }
}

private struct BrewConfirmation: ViewModifier {
    @Environment(AppModel.self) var model
    @Binding var recipe: Recipe?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                recipe.map { L("brew.confirm.title", $0.displayName) } ?? "",
                isPresented: Binding(
                    get: { recipe != nil && model.settings.confirmBeforeBrewing },
                    set: { if !$0 { recipe = nil } }
                ),
                titleVisibility: .visible,
                presenting: recipe
            ) { item in
                Button(L("action.brewNow")) {
                    recipe = nil
                    Task { await model.brew(item) }
                }
                Button(L("action.cancel"), role: .cancel) { recipe = nil }
            } message: { item in
                Text(item.spokenSummary)
            }
            .onChange(of: recipe) { _, new in
                guard let new, !model.settings.confirmBeforeBrewing else { return }
                recipe = nil
                Task { await model.brew(new) }
            }
    }
}
