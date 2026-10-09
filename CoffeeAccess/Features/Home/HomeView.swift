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
                VStack(alignment: .leading, spacing: 26) {
                    header
                    if model.data.guestMode { guestBanner }
                    ForEach(model.data.life.visibleHomeSections) { section in
                        sectionView(section)
                    }
                    Button { path.append(HomeRoute.layout) } label: {
                        Label(L("homeLayout.open"), systemImage: "rectangle.3.group")
                    }
                    .buttonStyle(TextLinkButtonStyle())
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(TimeOfDayBackground(enabled: model.settings.timeOfDayTheme))
            // Two-finger double-tap anywhere on Home: the usual drink (asks first when confirmations are on).
            .accessibilityAction(.magicTap) {
                if model.settings.magicTapUsual, model.session?.isRunning != true { pendingBrew = model.usualRecipe }
            }
            .navigationTitle(L("tab.home"))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MaintenanceGuideID.self) { GuideView(guide: $0) }
            .navigationDestination(for: DrinkCollection.self) { CollectionView(collection: $0) }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .journey: CoffeeJourneyView()
                case .search: DrinkSearchView()
                case .layout: HomeLayoutView()
                case .caffeine: CaffeineView()
                case .signatures: SignatureListView()
                case .signature(let id): SignatureRecipeView(recipeID: id)
                case .household: HouseholdView()
                case .schedules: ScheduleListView()
                case .queue: FamilyQueueView()
                case .compare: CompareDrinksView()
                case .goals: GoalsView()
                case .weekly: WeeklySummaryView()
                case .journal: TastingJournalView()
                case .globalSearch: GlobalSearchView()
                case .pro(let screen): ProScreenView(screen: screen)
                }
            }
            .navigationDestination(for: DrinkRoute.self) { route in
                DrinkDetailView(route: route, initial: model.initialRecipe(for: route))
            }
            .brewConfirmation(recipe: $pendingBrew)
            .onAppear(perform: takeScheduled)
            .onChange(of: model.pendingScheduledRecipe) { _, _ in takeScheduled() }
            .sheet(isPresented: $pickingBase) {
                BasePickerView { beverage in
                    pickingBase = false
                    path.append(DrinkRoute.newRecipe(beverage))
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.data.guestMode ? L("guest.title") : greeting)
                .font(.display(.largeTitle))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 10) {
                ProfileMenu()
                Spacer(minLength: 0)
                Button { path.append(HomeRoute.search) } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.surface))
                }
                .accessibilityLabel(L("search.open"))
                .accessibilityHint(L("search.open.hint"))
                .accessibilityInputLabels([L("search.open"), L("voice.search")])
                Button { path.append(HomeRoute.globalSearch) } label: {
                    Image(systemName: "text.magnifyingglass")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.surface))
                }
                .accessibilityLabel(L("globalSearch.title"))
                .accessibilityHint(L("globalSearch.hint"))
                HelpButton(topic: .home)
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.surface))
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func sectionView(_ section: HomeSection) -> some View {
        let guest = model.data.guestMode
        switch section {
        case .ready: ReadyCard(path: $path, pendingBrew: $pendingBrew)
        case .caffeine: if !guest { CaffeineChip { path.append(HomeRoute.caffeine) } }
        case .today: DrinkOfTheDayCard(pendingBrew: $pendingBrew)
        case .family: if !guest { FamilySection(path: $path, pendingBrew: $pendingBrew) }
        case .favorites: if !guest { favoritesSection }
        case .journey: if !guest { journeySection }
        case .moment: momentSection
        case .seasonal: SeasonalSection(path: $path)
        case .recommended: if !guest { RecommendedSection(pendingBrew: $pendingBrew) }
        case .signature: SignatureSection(path: $path)
        case .collections: collectionsSection
        case .frequent: if !guest { frequentSection }
        }
    }

    private func takeScheduled() {
        guard let recipe = model.pendingScheduledRecipe else { return }
        model.pendingScheduledRecipe = nil
        pendingBrew = recipe
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
        .card()
    }

    // MARK: My coffee journey

    private var journeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: L("journey.title"), linkTitle: L("action.viewAll")) { path.append(HomeRoute.journey) }
            Button { path.append(HomeRoute.journey) } label: {
                MilestoneCard(stats: DrinkStatistics(history: profile.history))
            }
            .buttonStyle(.plain)
            .accessibilityHint(L("journey.open.hint"))
        }
    }

    // MARK: Right now

    private var moment: Moment { Moment(hour: Calendar.current.component(.hour, from: Date())) }

    private var momentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { path.append(DrinkCollection.suggested) } label: {
                InfoChip(text: moment.title, symbol: moment.symbol)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("home.moment.label", moment.title))
            .accessibilityHint(L("home.moment.hint"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    Text(moment.pitch)
                        .font(.display(.title3, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(18)
                        .frame(width: 170, height: 228, alignment: .bottomLeading)
                        .card(raised: true)
                    ForEach(DrinkCollection.suggested.beverages().prefix(5), id: \.self) { beverage in
                        let recipe = model.data.recipe(for: beverage)
                        NavigationLink(value: DrinkRoute.beverage(beverage)) {
                            DrinkCard(recipe: recipe, isFavorite: isFavorite(beverage))
                                .frame(width: 170)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(L("drinks.card.hint"))
                        .accessibilityAction(named: Text(L("action.brewNow"))) { pendingBrew = recipe }
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollClipDisabled()
        }
    }

    private func isFavorite(_ beverage: BeverageID) -> Bool {
        profile.favorites.contains { $0.beverage == beverage && $0.customName.isEmpty }
    }

    // MARK: Favorites

    @ViewBuilder
    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: L("home.favorites"))
            if profile.favorites.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "heart")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text(L("home.favorites.empty"))
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(18)
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
                        .accessibilityAction(named: Text(L("organizer.duplicate"))) { FavoriteTools.duplicate(recipe, model: model) }
                        .contextMenu {
                            Button(L("action.brewNow"), systemImage: "cup.and.saucer.fill") { pendingBrew = recipe }
                            Button(L("action.edit"), systemImage: "slider.horizontal.3") { path.append(DrinkRoute.favorite(recipe)) }
                            Button(L("organizer.duplicate"), systemImage: "plus.square.on.square") { FavoriteTools.duplicate(recipe, model: model) }
                            Button(L("action.moveUp"), systemImage: "arrow.up") { move(recipe, by: -1) }
                            Button(L("action.moveDown"), systemImage: "arrow.down") { move(recipe, by: 1) }
                            Button(L("action.delete"), systemImage: "trash", role: .destructive) { deleteFavorite(recipe) }
                        }
                }
            }
            Button {
                pickingBase = true
            } label: {
                Label(L("recipe.new.button"), systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            HStack(spacing: 10) {
                Button(L("screen.organizer")) { path.append(HomeRoute.pro(.organizer)) }.buttonStyle(PillButtonStyle())
                Button(L("screen.combos")) { path.append(HomeRoute.pro(.combos)) }.buttonStyle(PillButtonStyle())
            }
        }
    }

    // MARK: Collections

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: L("home.collections"), linkTitle: L("home.allDrinks")) { selectedTab = .drinks }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(DrinkCollection.allCases) { collection in
                    NavigationLink(value: collection) { CollectionTile(collection: collection) }
                        .buttonStyle(.plain)
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

enum HomeRoute: Hashable {
    case journey, search, layout, caffeine, signatures, household, schedules, queue, compare, goals, weekly, journal
    case globalSearch
    case signature(SignatureRecipeID)
    case pro(ProScreen)
}

/// The time of day, for the chip on the home screen and its drink row.
enum Moment: String, CaseIterable {
    case morning, lunchtime, afternoon, evening

    init(hour: Int) {
        switch hour {
        case 5..<11: self = .morning
        case 11..<15: self = .lunchtime
        case 15..<18: self = .afternoon
        default: self = .evening
        }
    }

    var title: String { L("moment.\(rawValue).title") }
    var pitch: String { L("moment.\(rawValue).pitch") }
    var symbol: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .lunchtime: return "sun.max.fill"
        case .afternoon: return "cup.and.saucer.fill"
        case .evening: return "moon.stars.fill"
        }
    }
}

/// "Congratulations! You've brewed your 100th drink!" — the latest round
/// number reached, with the drink that reached it.
struct MilestoneCard: View {
    let stats: DrinkStatistics

    var body: some View {
        Group {
            if let milestone = stats.milestone() {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("journey.congrats"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text(L("journey.milestone", milestone.count))
                        .font(.display(.title, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Image(systemName: "trophy")
                                .font(.title2)
                                .foregroundStyle(Theme.accent)
                                .accessibilityHidden(true)
                            Text(L("journey.milestone.was", milestone.count))
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                            Text(milestone.record.recipe.displayName)
                                .font(.display(.title3, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        Spacer(minLength: 0)
                        DrinkIllustration(beverage: milestone.record.recipe.beverage, showsSteam: false)
                            .frame(width: 120)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("journey.milestone", milestone.count))
                .accessibilityValue(L("journey.milestone.spoken", milestone.count, milestone.record.recipe.displayName))
            } else {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("journey.start.title"))
                            .font(.display(.title2, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(L("journey.start.body"))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    DrinkIllustration(beverage: .cappuccino, showsSteam: false)
                        .frame(width: 96)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
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
            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.profileColors[model.activeProfile.colorIndex % Theme.profileColors.count])
                    .frame(width: 32, height: 32)
                    .overlay(Text(String(model.activeProfile.name.prefix(1))).font(.subheadline.bold()).foregroundStyle(.white))
                Text(model.data.guestMode ? L("guest.title") : model.activeProfile.name)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.leading, 6)
            .padding(.trailing, 16)
            .frame(minHeight: 44)
            .background(Capsule().fill(Theme.surface))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
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

    /// The recipe, then what to do before it starts, then a caffeine note.
    private func confirmationMessage(_ item: Recipe) -> String {
        var parts = [model.settings.brailleBrief ? item.brief : item.spokenSummary]
        let checklist = model.preBrewChecklist(for: item) + model.proChecklist(for: item)
        if !checklist.isEmpty { parts.append(L("prebrew.title") + " " + checklist.joined(separator: L("sentence.separator"))) }
        if let warning = model.caffeineWarning(for: item) { parts.append(warning) }
        if let reason = model.brewBlockReason(item) { parts.append(reason) }
        return parts.joined(separator: "\n\n")
    }

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
                if model.settings.cupPrewarm, !item.spec.isCold, item.beverage != .hotWater {
                    Button(L("prewarm.button")) {
                        recipe = nil
                        Task { await model.brewWithPrewarm(item) }
                    }
                }
                if model.caffeineWarning(for: item) != nil, let lighter = Lighter.alternative(to: item) {
                    Button(L("lighter.button")) {
                        recipe = nil
                        Task { await model.brew(lighter) }
                    }
                }
                Button(L("action.cancel"), role: .cancel) { recipe = nil }
            } message: { item in
                Text(confirmationMessage(item))
            }
            .onChange(of: recipe) { _, new in
                guard let new, !model.settings.confirmBeforeBrewing else { return }
                recipe = nil
                Task { await model.brew(new) }
            }
    }
}
