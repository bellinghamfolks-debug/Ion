import SwiftUI

/// "Ready to brew": the machine's state, your usual drink in one tap, the
/// last order again, and the morning routine.
struct ReadyCard: View {
    @Environment(AppModel.self) var model
    @Binding var path: NavigationPath
    @Binding var pendingBrew: Recipe?

    var body: some View {
        let usual = model.usualRecipe
        VStack(alignment: .leading, spacing: 14) {
            MachineStatusCard()
            if let status = model.routineStatus {
                Label(status, systemImage: "sunrise.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            Button { pendingBrew = usual } label: {
                Label(L("ready.usual", usual.displayName), systemImage: "cup.and.saucer.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityHint(usual.spokenSummary)
            if let last = model.lastRecipe, last.beverage != usual.beverage || last.customName != usual.customName {
                Button { pendingBrew = last } label: {
                    Label(L("ready.last", last.displayName), systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityHint(last.spokenSummary)
            }
            if model.connection.isConnected, model.snapshot.power == .off {
                Button { Task { await model.runRoutine(usual) } } label: {
                    Label(L("routine.start", usual.displayName), systemImage: "sunrise")
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityHint(L("routine.hint"))
            }
            if model.data.life.carafeCleanPending {
                HStack(spacing: 12) {
                    Image(systemName: "drop.triangle")
                        .foregroundStyle(Theme.warning)
                        .accessibilityHidden(true)
                    Text(L("carafe.pending"))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(L("carafe.cleaned")) { model.markCarafeCleaned() }
                        .buttonStyle(PillButtonStyle())
                }
                .accessibilityElement(children: .combine)
                .accessibilityAction(named: Text(L("carafe.cleaned"))) { model.markCarafeCleaned() }
            }
            if model.data.life.beanSettleCups > 0 {
                Label(L("bean.settle.tip", model.data.life.beanSettleCups), systemImage: "leaf.arrow.triangle.circlepath")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 10) {
                Button(L("schedule.title")) { path.append(HomeRoute.schedules) }
                    .buttonStyle(PillButtonStyle())
                if !model.data.life.household.isEmpty {
                    Button(L("queue.title")) { path.append(HomeRoute.queue) }
                        .buttonStyle(PillButtonStyle())
                }
            }
        }
    }
}

/// Today's estimated caffeine against the person's own limit.
struct CaffeineChip: View {
    @Environment(AppModel.self) var model
    let open: () -> Void

    var body: some View {
        let today = model.caffeineToday
        let limit = max(1, model.settings.caffeineLimitMg)
        let fraction = min(1, Double(today) / Double(limit))
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(L("caffeine.title"), systemImage: "bolt.heart")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(L("caffeine.value", today, limit))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(today > limit ? Theme.danger : Theme.accent)
                }
                ProgressView(value: fraction)
                    .tint(today > limit ? Theme.danger : Theme.accent)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("caffeine.title"))
        .accessibilityValue(L("caffeine.spoken", today, limit))
        .accessibilityHint(L("caffeine.hint"))
        .accessibilityAddTraits(.isButton)
    }
}

/// One suggestion for today, the same all day.
struct DrinkOfTheDayCard: View {
    @Environment(AppModel.self) var model
    @Binding var pendingBrew: Recipe?

    var body: some View {
        let beverage = Suggestions.drinkOfTheDay(history: model.activeProfile.history)
        let recipe = model.data.recipe(for: beverage)
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: L("today.title"))
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(beverage.name)
                        .font(.display(.title2, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(beverage.summary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    NavigationLink(value: DrinkRoute.beverage(beverage)) {
                        Text(L("today.open"))
                    }
                    .buttonStyle(TextLinkButtonStyle())
                }
                Spacer(minLength: 0)
                DrinkIllustration(beverage: beverage, showsSteam: false)
                    .frame(width: 96)
                    .accessibilityHidden(true)
            }
            Button { pendingBrew = recipe } label: { Label(L("action.brewNow"), systemImage: "cup.and.saucer.fill") }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel(L("today.brew", beverage.name))
        }
        .padding(18)
        .card()
    }
}

/// The household's usual drinks, one tap each.
struct FamilySection: View {
    @Environment(AppModel.self) var model
    @Binding var path: NavigationPath
    @Binding var pendingBrew: Recipe?

    var body: some View {
        let members = model.data.life.household
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: L("family.title"), linkTitle: L("action.edit")) { path.append(HomeRoute.household) }
            if members.isEmpty {
                Button { path.append(HomeRoute.household) } label: {
                    NavigationRowCard(title: L("family.empty.title"), subtitle: L("family.empty.body"), symbol: "person.2")
                }
                .buttonStyle(.plain)
            } else {
                ForEach(members) { member in
                    Button { pendingBrew = member.recipe } label: {
                        RecipeRow(recipe: member.recipe)
                            .overlay(alignment: .topTrailing) {
                                Text(member.name)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Capsule().fill(Theme.surfaceRaised))
                                    .padding(8)
                                    .accessibilityHidden(true)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("family.member", member.name, member.recipe.displayName))
                    .accessibilityHint(L("home.favorite.hint"))
                }
            }
        }
    }
}

/// Recipes for the season (Ramadan, winter, summer), when one applies.
struct SeasonalSection: View {
    @Binding var path: NavigationPath

    var body: some View {
        let seasons = Season.current()
        let recipes = SignatureSpec.seasonal()
        if !recipes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: L("seasonal.title", seasons.map(\.title).sorted().joined(separator: L("list.separator"))))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(recipes) { id in
                            Button { path.append(HomeRoute.signature(id)) } label: { SignatureTile(recipeID: id) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollClipDisabled()
            }
        }
    }
}

/// Drinks not tried yet that are closest to what the person likes.
struct RecommendedSection: View {
    @Environment(AppModel.self) var model
    @Binding var pendingBrew: Recipe?

    var body: some View {
        let picks = Suggestions.closeToTaste(history: model.activeProfile.history, favorites: model.activeProfile.favorites)
        if !picks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: L("recommended.title"))
                Text(L("recommended.body"))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                ForEach(picks, id: \.self) { beverage in
                    NavigationLink(value: DrinkRoute.beverage(beverage)) {
                        RecipeRow(recipe: model.data.recipe(for: beverage))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAction(named: Text(L("action.brewNow"))) { pendingBrew = model.data.recipe(for: beverage) }
                }
            }
        }
    }
}

/// Recipes from around the world, on the home screen.
struct SignatureSection: View {
    @Binding var path: NavigationPath

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: L("signature.section"), linkTitle: L("action.viewAll")) { path.append(HomeRoute.signatures) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(SignatureRecipeID.allCases.prefix(6)) { id in
                        Button { path.append(HomeRoute.signature(id)) } label: { SignatureTile(recipeID: id) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }
}

struct SignatureTile: View {
    let recipeID: SignatureRecipeID

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DrinkIllustration(beverage: recipeID.spec.base, showsSteam: false)
                .frame(height: 96)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            Text(recipeID.title)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
            Text(recipeID.summary)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(3)
        }
        .padding(14)
        .frame(width: 170, alignment: .topLeading)
        .frame(minHeight: 210, alignment: .top)
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// The home background: warmer in the morning, calmer at night. Purely
/// decorative; text colours stay the same so contrast is unchanged.
struct TimeOfDayBackground: View {
    var enabled: Bool
    @Environment(\.colorScheme) var scheme
    @Environment(\.colorSchemeContrast) var contrast

    var body: some View {
        ZStack {
            Theme.background
            if enabled && contrast != .increased {
                LinearGradient(colors: [tint.opacity(scheme == .dark ? 0.18 : 0.22), .clear],
                               startPoint: .top, endPoint: .center)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var tint: Color {
        switch Moment(hour: Calendar.current.component(.hour, from: Date())) {
        case .morning: return Color(hex: 0xF6C28B)
        case .lunchtime: return Color(hex: 0xF3D9A4)
        case .afternoon: return Color(hex: 0xD9A27A)
        case .evening: return Color(hex: 0x6F7FB8)
        }
    }
}
