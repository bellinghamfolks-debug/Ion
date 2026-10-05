import SwiftUI

/// One part of the machine's health: descaling, water filter, brewing unit
/// or grounds container.
struct HealthItem: Identifiable {
    enum Level { case good, soon, now, unknown }

    let id: String
    let title: String
    /// Wear in percent; 100 means "do it now". nil when not readable.
    let percent: Int?
    let advice: String
    let guide: MaintenanceGuideID

    var level: Level {
        guard let percent else { return .unknown }
        if percent >= 100 { return .now }
        if percent >= 80 { return .soon }
        return .good
    }

    var dotColor: Color {
        switch level {
        case .good: return Theme.healthGood
        case .soon: return Theme.healthWarn
        case .now: return Theme.healthBad
        case .unknown: return Theme.separator
        }
    }

    var spokenState: String {
        switch level {
        case .good: return L("health.state.good")
        case .soon: return L("health.state.soon")
        case .now: return L("health.state.now")
        case .unknown: return L("health.noReading")
        }
    }
}

/// The overall state and the per-part items, shared by My Machine and the
/// Health Status page. In demo mode the numbers come from the demo machine;
/// over Bluetooth the alarms reveal what is due.
struct MachineHealth {
    let items: [HealthItem]

    @MainActor
    init(model: AppModel) {
        let engine = model.demoLink?.engine
        let _ = model.demoRevision
        let descale: Int? = engine.map { engine in
            let used = (1 - Double(engine.drinksUntilDescale) / Double(DemoMachineEngine.drinksBetweenDescaling)) * 100
            return Int(min(100, max(0, used)))
        } ?? (model.snapshot.alarms.contains(.descaleNeeded) ? 100 : nil)
        let grounds: Int? = engine.map { Int(($0.groundsLevel * 100).rounded()) }
            ?? (model.snapshot.alarms.contains(.wasteContainerFull) ? 100 : nil)
        let filter: Int? = model.snapshot.alarms.contains(.replaceFilter) ? 100 : (engine == nil ? nil : 35)
        let unit: Int? = engine == nil ? nil : 20
        items = [
            HealthItem(id: "descale", title: L("guide.descaling.title"), percent: descale,
                       advice: L("health.descale.advice"), guide: .descaling),
            HealthItem(id: "filter", title: L("guide.waterFilter.title"), percent: filter,
                       advice: L("health.filter.advice"), guide: .waterFilter),
            HealthItem(id: "unit", title: L("guide.brewingUnit.title"), percent: unit,
                       advice: L("health.unit.advice"), guide: .brewingUnit),
            HealthItem(id: "grounds", title: L("guide.emptyContainers.title"), percent: grounds,
                       advice: L("health.grounds.advice"), guide: .emptyContainers),
        ]
    }

    private var worst: Int { items.compactMap(\.percent).max() ?? 0 }

    var overallText: String {
        if worst >= 100 { return L("health.overall.critical") }
        if worst >= 80 { return L("health.overall.warning") }
        return L("health.overall.good")
    }

    /// Bars lit on the overview card: 3 healthy, 2 soon, 1 now.
    var segments: (filled: Int, tint: Color) {
        if worst >= 100 { return (1, Theme.healthBad) }
        if worst >= 80 { return (2, Theme.healthWarn) }
        return (3, Theme.healthGood)
    }
}

/// The machine picture on a soft sky-blue circle, with its name.
struct MachineHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("machine.model"))
                .font(.display(.largeTitle))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(L("machine.modelCode"))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            MachineIllustration()
                .frame(maxWidth: 220)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .background(
                    Circle()
                        .fill(Theme.sky)
                        .frame(width: 300, height: 300)
                        .offset(y: -10)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// "Machine overall health" on navy, with three bars.
struct HealthOverviewCard: View {
    let health: MachineHealth

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("health.overall"))
                    .font(.headline)
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHidden(true)
            }
            Text(health.overallText)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            SegmentBar(filled: health.segments.filled, total: 3, tint: health.segments.tint,
                       track: Theme.onInk.opacity(0.22))
                .padding(.top, 6)
        }
        .foregroundStyle(Theme.onInk)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Theme.ink))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("health.overall"))
        .accessibilityValue(health.overallText)
        .accessibilityAddTraits(.isButton)
    }
}

/// "Take a closer look": one small tile per part with a coloured dot.
struct HealthTile: View {
    let item: HealthItem

    var body: some View {
        HStack(spacing: 10) {
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Circle()
                .fill(item.dotColor)
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.spokenState)
        .accessibilityAddTraits(.isButton)
    }
}

/// Health Status: the overview, then each part with its wear, advice and
/// guide.
struct HealthStatusView: View {
    @Environment(AppModel.self) var model

    var body: some View {
        let health = MachineHealth(model: model)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MachineHero()
                HealthOverviewCard(health: health)
                    .accessibilityRemoveTraits(.isButton)
                SectionTitle(text: L("health.closerLook"))
                ForEach(health.items) { item in
                    card(item)
                }
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle(L("health.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: MaintenanceGuideID.self) { GuideView(guide: $0) }
    }

    private func card(_ item: HealthItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(item.title).font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                Circle().fill(item.dotColor).frame(width: 12, height: 12).accessibilityHidden(true)
            }
            if let percent = item.percent {
                ProgressView(value: Double(min(percent, 100)) / 100)
                    .tint(item.dotColor)
                    .accessibilityHidden(true)
                Text(L("health.wear", percent))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text(L("health.noReading"))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(item.advice).font(.subheadline).foregroundStyle(Theme.textPrimary)
            NavigationLink(value: item.guide) { Text(L("action.openGuide", item.guide.title)) }
                .buttonStyle(TextLinkButtonStyle())
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.percent.map { L("health.wear", $0) } ?? L("health.noReading"))
    }
}
