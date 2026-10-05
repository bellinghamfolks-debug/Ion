import SwiftUI

/// Machine health: descaling, water filter, brewing-unit cleaning and the
/// grounds container, each as a wear bar with advice and a link to its guide.
/// In demo mode the bars come from the demo machine; over Bluetooth the app
/// shows what the alarms reveal and says when a reading is not available.
struct HealthStatusView: View {
    @Environment(AppModel.self) var model

    private struct Item: Identifiable {
        let id: String
        let title: String
        let percent: Int?
        let advice: String
        let guide: MaintenanceGuideID
        /// true when 100% means "do it now" (wear); false for a fill gauge.
        let wear: Bool
    }

    private var overall: (text: String, tint: Color) {
        let worst = items.compactMap(\.percent).max() ?? 0
        if worst >= 100 { return (L("health.overall.critical"), Theme.danger) }
        if worst >= 80 { return (L("health.overall.warning"), Theme.warning) }
        return (L("health.overall.good"), Theme.success)
    }

    private var items: [Item] {
        let engine = model.demoLink?.engine
        let _ = model.demoRevision
        let descale: Int? = engine.map { engine in
            let used = (1 - Double(engine.drinksUntilDescale) / Double(DemoMachineEngine.drinksBetweenDescaling)) * 100
            return Int(min(100, max(0, used)))
        } ?? (model.snapshot.alarms.contains(.descaleNeeded) ? 100 : nil)
        let grounds: Int? = engine.map { Int(($0.groundsLevel * 100).rounded()) }
            ?? (model.snapshot.alarms.contains(.wasteContainerFull) ? 100 : nil)
        return [
            Item(id: "descale", title: L("guide.descaling.title"), percent: descale,
                 advice: L("health.descale.advice"), guide: .descaling, wear: true),
            Item(id: "filter", title: L("guide.waterFilter.title"),
                 percent: model.snapshot.alarms.contains(.replaceFilter) ? 100 : nil,
                 advice: L("health.filter.advice"), guide: .waterFilter, wear: true),
            Item(id: "unit", title: L("guide.brewingUnit.title"), percent: nil,
                 advice: L("health.unit.advice"), guide: .brewingUnit, wear: true),
            Item(id: "grounds", title: L("guide.emptyContainers.title"), percent: grounds,
                 advice: L("health.grounds.advice"), guide: .emptyContainers, wear: true),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard
                ForEach(items) { item in
                    card(item)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(L("health.title"))
        .navigationDestination(for: MaintenanceGuideID.self) { GuideView(guide: $0) }
    }

    private var summaryCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 30))
                .foregroundStyle(overall.tint)
                .accessibilityHidden(true)
            Text(overall.text)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card(raised: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("health.overall"))
        .accessibilityValue(overall.text)
    }

    private func card(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title).font(.headline).foregroundStyle(Theme.textPrimary)
            if let percent = item.percent {
                ProgressView(value: Double(percent) / 100)
                    .tint(percent >= 100 ? Theme.danger : (percent >= 80 ? Theme.warning : Theme.success))
                    .accessibilityHidden(true)
                Text(item.wear ? L("health.wear", percent) : L("unit.percent", percent))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text(L("health.noReading"))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(item.advice).font(.subheadline).foregroundStyle(Theme.textPrimary)
            NavigationLink(value: item.guide) { Text(L("action.openGuide", item.guide.title)) }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.percent.map { item.wear ? L("health.wear", $0) : L("unit.percent", $0) } ?? L("health.noReading"))
    }
}
