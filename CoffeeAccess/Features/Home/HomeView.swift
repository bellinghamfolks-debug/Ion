import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) var model
    @Binding var selectedTab: AppTab
    @State var path = NavigationPath()
    @State var pendingBrew: Recipe?

    private var profile: UserProfile { model.activeProfile }
    private var quickDrinks: [BeverageID] { [.espresso, .coffee, .cappuccino, .latteMacchiato, .americano, .flatWhite] }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    MachineStatusCard()
                    favoritesSection
                    frequentSection
                    quickSection
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle(greeting)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ProfileMenu() }
            }
            .navigationDestination(for: MaintenanceGuideID.self) { GuideView(guide: $0) }
            .navigationDestination(for: DrinkRoute.self) { route in
                DrinkDetailView(route: route, initial: model.initialRecipe(for: route))
            }
            .brewConfirmation(recipe: $pendingBrew)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let key = hour < 12 ? "home.greeting.morning" : (hour < 18 ? "home.greeting.afternoon" : "home.greeting.evening")
        return L(key, profile.name)
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
                        .accessibilityAction(named: Text(L("action.delete"))) { deleteFavorite(recipe) }
                        .contextMenu {
                            Button(L("action.brewNow"), systemImage: "cup.and.saucer.fill") { pendingBrew = recipe }
                            Button(L("action.edit"), systemImage: "slider.horizontal.3") { path.append(DrinkRoute.favorite(recipe)) }
                            Button(L("action.delete"), systemImage: "trash", role: .destructive) { deleteFavorite(recipe) }
                        }
                }
            }
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

    private var quickSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: L("home.quick"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(quickDrinks) { beverage in
                    NavigationLink(value: DrinkRoute.beverage(beverage)) {
                        DrinkCard(recipe: profile.recipe(for: beverage), isPersonal: profile.personalDefaults[beverage] != nil)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button(L("home.allDrinks")) { selectedTab = .drinks }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func deleteFavorite(_ recipe: Recipe) {
        model.updateData { $0.removeFavorite(id: recipe.id) }
        Announcer.shared.announce(L("announce.favoriteDeleted", recipe.displayName))
    }
}

/// Switches between the four profiles from the navigation bar.
struct ProfileMenu: View {
    @Environment(AppModel.self) var model

    var body: some View {
        Menu {
            ForEach(model.data.profiles) { profile in
                Button {
                    model.selectProfile(profile.id)
                } label: {
                    if profile.id == model.data.activeProfileID {
                        Label(profile.name, systemImage: "checkmark")
                    } else {
                        Text(profile.name)
                    }
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
        .accessibilityValue(model.activeProfile.name)
    }
}

/// Where a drink screen comes from: the menu (standard or personal default)
/// or an existing favorite being edited.
enum DrinkRoute: Hashable {
    case beverage(BeverageID)
    case favorite(Recipe)
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
