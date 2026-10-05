import SwiftUI

/// A drink tile for the menu grid. Reads as one element: name, then the
/// short description; custom actions brew straight away or add a favorite.
struct DrinkCard: View {
    let recipe: Recipe
    var isPersonal = false

    @Environment(\.dynamicTypeSize) var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                HStack(spacing: 14) {
                    DrinkIllustration(beverage: recipe.beverage, showsSteam: false, toGo: recipe.toGo)
                        .frame(width: 72, height: 72)
                    text
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 10) {
                    DrinkIllustration(beverage: recipe.beverage, showsSteam: false, toGo: recipe.toGo)
                        .frame(height: 110)
                    text
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: typeSize.isAccessibilitySize ? 0 : 200)
        .card()
        .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recipe.displayName)
        .accessibilityValue(isPersonal ? L("drink.personalized", recipe.shortDetails) : recipe.beverage.summary)
        .accessibilityAddTraits(.isButton)
    }

    private var text: some View {
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .center, spacing: 4) {
            Text(recipe.displayName)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .center)
            Text(recipe.shortDetails)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            if isPersonal {
                Text(L("drink.personalBadge"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}

/// A favorite in a list: illustration, name and settings in one line.
struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 14) {
            DrinkIllustration(beverage: recipe.beverage, showsSteam: false, toGo: recipe.toGo)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.displayName)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                if !recipe.customName.isEmpty {
                    Text(recipe.beverage.name)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(recipe.shortDetails)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward")
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recipe.displayName)
        .accessibilityValue(recipe.spokenSummary)
        .accessibilityAddTraits(.isButton)
    }
}

/// Machine status at a glance, with the one action that matters now.
struct MachineStatusCard: View {
    @Environment(AppModel.self) var model
    var showsActions = true

    private var snapshot: MachineSnapshot { model.snapshot }

    private var tint: Color {
        if !model.connection.isConnected { return Theme.textSecondary }
        if !snapshot.blockingAlarms.isEmpty { return Theme.danger }
        if !snapshot.alarms.isEmpty { return Theme.warning }
        return snapshot.power == .ready ? Theme.success : Theme.accent
    }

    private var symbol: String {
        if !model.connection.isConnected { return "antenna.radiowaves.left.and.right.slash" }
        if !snapshot.blockingAlarms.isEmpty { return "exclamationmark.triangle.fill" }
        switch snapshot.power {
        case .ready: return "checkmark.circle.fill"
        case .off: return "power.circle"
        case .turningOn: return "flame.fill"
        case .busy: return "cup.and.saucer.fill"
        default: return "gearshape.fill"
        }
    }

    private var headline: String {
        model.connection.isConnected ? snapshot.headline : model.connection.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L("status.machine"))
            .accessibilityValue("\(headline). \(subtitle)")

            if showsActions {
                actions
            }
        }
        .padding(16)
        .card(raised: true)
    }

    private var subtitle: String {
        guard model.connection.isConnected else { return model.settings.linkKind.title }
        let others = snapshot.alarms.filter { $0.title != headline }.map(\.title)
        if !others.isEmpty { return others.joined(separator: L("list.separator")) }
        return model.connection.title
    }

    @ViewBuilder
    private var actions: some View {
        if !model.connection.isConnected {
            Button(L("action.connect")) { model.reconnect() }
                .buttonStyle(PrimaryButtonStyle())
        } else if snapshot.power == .off {
            Button(L("action.turnOn")) { Task { await model.powerOn() } }
                .buttonStyle(PrimaryButtonStyle())
        } else if let alarm = snapshot.alarms.first, let guide = alarm.maintenanceGuide {
            NavigationLink(value: guide) {
                Text(L("action.howToFix", alarm.title))
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
}
