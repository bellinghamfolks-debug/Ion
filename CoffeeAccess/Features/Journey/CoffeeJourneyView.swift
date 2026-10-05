import SwiftUI

/// "My Coffee Journey": friendly achievements drawn from the active profile's
/// own history — most-brewed drink, hot vs cold balance, custom-drink skill —
/// over a chosen period. All computed on device from what you brewed.
struct CoffeeJourneyView: View {
    @Environment(AppModel.self) var model

    enum Period: String, CaseIterable, Identifiable {
        case week, month, year, all
        var id: String { rawValue }
        var title: String { L("journey.period.\(rawValue)") }
        var days: Int? {
            switch self {
            case .week: return 7
            case .month: return 30
            case .year: return 365
            case .all: return nil
            }
        }
    }

    @State var period: Period = .week

    private var records: [BrewRecord] {
        let completed = model.activeProfile.history.filter(\.completed)
        guard let days = period.days, let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return completed }
        return completed.filter { $0.date >= since }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L("journey.subtitle"))
                    .font(.body).foregroundStyle(Theme.textSecondary)
                Picker(L("journey.period"), selection: $period) {
                    ForEach(Period.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if records.isEmpty {
                    Text(L("journey.empty"))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16).card()
                } else {
                    totalCard
                    mostBrewedCard
                    balanceCard
                    skillCard
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(L("journey.title"))
    }

    private func card(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Theme.accent).frame(width: 40).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline).foregroundStyle(Theme.textSecondary)
                Text(value).font(.headline).foregroundStyle(Theme.textPrimary)
            }
            Spacer(minLength: 0)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
        .accessibilityElement(children: .combine)
    }

    private var totalCard: some View {
        card(title: L("journey.total.title"), value: L("journey.total.value", records.count), symbol: "cup.and.saucer.fill")
    }

    private var mostBrewedCard: some View {
        let counts = Dictionary(grouping: records, by: { $0.recipe.beverage }).mapValues(\.count)
        let top = counts.sorted { $0.value > $1.value }.first
        return card(title: L("journey.most.title"),
                    value: top.map { "\($0.key.name) · \(L("stats.cups", $0.value))" } ?? "—",
                    symbol: "star.fill")
    }

    private var balanceCard: some View {
        let hot = records.filter { !$0.recipe.spec.isCold }.count
        let cold = records.count - hot
        let value = hot >= cold ? L("journey.balance.hot", hot) : L("journey.balance.cold", cold)
        return card(title: L("journey.balance.title"), value: value, symbol: hot >= cold ? "flame.fill" : "snowflake")
    }

    private var skillCard: some View {
        let custom = records.filter { !$0.recipe.customName.isEmpty }.count
        let value = custom > 0 ? L("journey.skill.alchemist", custom) : L("journey.skill.explorer")
        return card(title: L("journey.skill.title"), value: value, symbol: "wand.and.stars")
    }
}
