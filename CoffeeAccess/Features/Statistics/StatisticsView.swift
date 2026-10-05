import Accessibility
import Charts
import SwiftUI

/// Pure summaries of the drink history, unit tested.
struct DrinkStatistics {
    struct Day: Identifiable, Equatable {
        let date: Date
        let count: Int
        var id: Date { date }
    }

    let records: [BrewRecord]

    init(history: [BrewRecord]) {
        records = history.filter(\.completed)
    }

    var total: Int { records.count }

    func lastDays(_ days: Int, now: Date = Date(), calendar: Calendar = .current) -> [Day] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let count = records.filter { calendar.isDate($0.date, inSameDayAs: day) }.count
            return Day(date: day, count: count)
        }
    }

    struct CategoryCount: Identifiable, Equatable {
        let category: BeverageCategory
        let count: Int
        var id: BeverageCategory { category }
    }

    struct DrinkCount: Identifiable, Equatable {
        let beverage: BeverageID
        let count: Int
        var id: BeverageID { beverage }
    }

    func byCategory() -> [CategoryCount] {
        BeverageCategory.allCases.map { category in
            CategoryCount(category: category, count: records.filter { $0.recipe.spec.category == category }.count)
        }.filter { $0.count > 0 }
    }

    func byDrink() -> [DrinkCount] {
        Dictionary(grouping: records, by: { $0.recipe.beverage })
            .map { DrinkCount(beverage: $0.key, count: $0.value.count) }
            .sorted { $0.count == $1.count ? $0.beverage.rawValue < $1.beverage.rawValue : $0.count > $1.count }
    }

    /// Drinks brewed in the 7 days ending `now`, and in the 7 days before.
    func weekTotals(now: Date = Date(), calendar: Calendar = .current) -> (this: Int, previous: Int) {
        let start = calendar.startOfDay(for: now)
        guard let thisStart = calendar.date(byAdding: .day, value: -6, to: start),
              let previousStart = calendar.date(byAdding: .day, value: -13, to: start) else { return (0, 0) }
        let this = records.filter { $0.date >= thisStart }.count
        let previous = records.filter { $0.date >= previousStart && $0.date < thisStart }.count
        return (this, previous)
    }

    /// The most-brewed drinks of the last 7 days, most first.
    func topThisWeek(_ limit: Int = 3, now: Date = Date(), calendar: Calendar = .current) -> [DrinkCount] {
        guard let since = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) else { return [] }
        return DrinkStatistics(history: records.filter { $0.date >= since }).byDrink().prefix(limit).map { $0 }
    }

    static let milestones = [1, 5, 10, 25, 50, 100, 150, 200, 250, 365, 500, 750, 1000]

    /// The latest round number reached ("your 100th drink") and the drink
    /// that reached it.
    func milestone() -> (count: Int, record: BrewRecord)? {
        guard let reached = Self.milestones.last(where: { $0 <= total }) else { return nil }
        let ordered = records.sorted { $0.date < $1.date }
        return (reached, ordered[reached - 1])
    }

    /// Average drinks per day over the last week, for the summary sentence.
    func weeklyAverage(now: Date = Date()) -> Double {
        let week = lastDays(7, now: now)
        return Double(week.reduce(0) { $0 + $1.count }) / 7
    }
}

struct StatisticsView: View {
    @Environment(AppModel.self) var model

    private var stats: DrinkStatistics { DrinkStatistics(history: model.activeProfile.history) }

    var body: some View {
        let week = stats.weekTotals()
        let top = stats.topThisWeek()
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                weekCard(total: week.this, top: top.first)
                if let first = top.first, week.this > 0 {
                    mostBrewedCard(first, total: week.this)
                }
                if !top.isEmpty {
                    topThreeCard(top, total: week.this)
                }
                chartCard
                listCard(title: L("stats.byCategory"), rows: stats.byCategory().map { ($0.category.title, L("stats.cups", $0.count)) })
                listCard(title: L("stats.byDrink"), rows: stats.byDrink().prefix(15).map { ($0.beverage.name, L("stats.cups", $0.count)) })
                machineCard
                recentCard
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle(L("machine.statistics"))
        .refreshable { await model.refreshCounters() }
        .task { await model.refreshCounters() }
    }

    // MARK: This week

    private func weekCard(total: Int, top: DrinkStatistics.DrinkCount?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("stats.weekHeadline", total))
                .font(.display(.largeTitle))
                .foregroundStyle(Theme.accent)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(summarySentence)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            if let top {
                DrinkIllustration(beverage: top.beverage, showsSteam: false)
                    .frame(maxWidth: 200)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func mostBrewedCard(_ top: DrinkStatistics.DrinkCount, total: Int) -> some View {
        HStack(spacing: 18) {
            RingGauge(fraction: Double(top.count) / Double(max(total, 1)), lineWidth: 6) {
                Text("\(top.count)/\(total)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("stats.mostBrewed"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Text(top.beverage.name)
                    .font(.display(.title2, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("stats.mostBrewed"))
        .accessibilityValue(L("stats.mostBrewed.spoken", top.beverage.name, top.count, total))
    }

    private func topThreeCard(_ top: [DrinkStatistics.DrinkCount], total: Int) -> some View {
        let maxCount = max(top.map(\.count).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 16) {
            Text(L("stats.topThree"))
                .font(.display(.title2, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(top) { entry in
                    VStack(spacing: 8) {
                        DrinkIllustration(beverage: entry.beverage, showsSteam: false)
                            .frame(width: 64, height: 64)
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Theme.accent.opacity(0.35 + 0.65 * Double(entry.count) / Double(maxCount)))
                                .frame(width: proxy.size.width * (0.4 + 0.6 * Double(entry.count) / Double(maxCount)), height: 6)
                                .frame(maxWidth: .infinity)
                        }
                        .frame(height: 6)
                        Text(entry.beverage.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(entry.count)/\(total)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Theme.accent)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(entry.beverage.name)
                    .accessibilityValue(L("stats.cups", entry.count))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: Details

    private var chartCard: some View {
        let days = stats.lastDays(7)
        return VStack(alignment: .leading, spacing: 12) {
            Text(L("stats.week"))
                .font(.display(.title3, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Chart(days) { day in
                BarMark(
                    x: .value(L("stats.axis.day"), day.date, unit: .day),
                    y: .value(L("stats.axis.drinks"), day.count)
                )
                .foregroundStyle(Theme.accent)
                .cornerRadius(6)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            }
            .frame(height: 180)
            .accessibilityChartDescriptor(WeekChartDescriptor(days: days))
            .accessibilityLabel(L("stats.week"))
            .accessibilityValue(days.map { "\($0.date.formatted(.dateTime.weekday(.wide))): \($0.count)" }.joined(separator: L("list.separator")))
        }
        .padding(18)
        .card()
    }

    private func listCard(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.display(.title3, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 8)
            if rows.isEmpty {
                Text(L("stats.empty")).font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider().overlay(Theme.separator) }
                LabeledContent(row.0, value: row.1)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.vertical, 10)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var summarySentence: String {
        let average = stats.weeklyAverage()
        let favorite = stats.byDrink().first?.beverage.name ?? "—"
        return L("stats.summary", stats.total, String(format: "%.1f", average), favorite)
    }

    private var counterRows: [(String, String)] {
        let counters = model.counters
        var rows: [(String, String)] = []
        if let value = counters.totalCoffee { rows.append((L("counter.coffee"), "\(value)")) }
        if let value = counters.milkDrinks { rows.append((L("counter.milk"), "\(value)")) }
        if let value = counters.coldMilk { rows.append((L("counter.coldMilk"), "\(value)")) }
        if let value = counters.tea { rows.append((L("counter.tea"), "\(value)")) }
        if let value = counters.waterLitres { rows.append((L("counter.water"), L("unit.litres", value))) }
        if let value = counters.descaleCount { rows.append((L("counter.descale"), "\(value)")) }
        if let value = counters.filterReplacements { rows.append((L("counter.filter"), "\(value)")) }
        if let value = counters.milkCleanings { rows.append((L("counter.milkClean"), "\(value)")) }
        return rows
    }

    private var machineCard: some View {
        let counters = model.counters
        let rows = counterRows
        return         VStack(alignment: .leading, spacing: 8) {
            if counters.isEmpty {
                Text(L("stats.machine"))
                    .font(.display(.title3, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(model.connection.isConnected ? L("stats.machine.loading") : L("stats.machine.offline"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .card()
            } else {
                listCard(title: L("stats.machine"), rows: rows)
            }
            if let date = model.countersUpdatedAt {
                Text(L("stats.machine.updated", date.formatted(date: .omitted, time: .shortened)))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: L("stats.recent"))
            ForEach(model.activeProfile.history.prefix(20)) { record in
                HStack(spacing: 12) {
                    DrinkIllustration(beverage: record.recipe.beverage, showsSteam: false)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.recipe.displayName).font(.headline).foregroundStyle(Theme.textPrimary)
                        Text("\(record.date.formatted(date: .abbreviated, time: .shortened)) · \(record.completed ? L("stats.completed") : L("stats.notCompleted"))")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .card()
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Lets VoiceOver play the week as an audio graph.
struct WeekChartDescriptor: AXChartDescriptorRepresentable {
    let days: [DrinkStatistics.Day]

    func makeChartDescriptor() -> AXChartDescriptor {
        let labels = days.map { $0.date.formatted(.dateTime.weekday(.wide)) }
        let maxCount = Double(max(days.map(\.count).max() ?? 0, 1))
        let xAxis = AXCategoricalDataAxisDescriptor(title: L("stats.axis.day"), categoryOrder: labels)
        let yAxis = AXNumericDataAxisDescriptor(title: L("stats.axis.drinks"), range: 0...maxCount, gridlinePositions: []) { value in
            L("stats.cups", Int(value))
        }
        let series = AXDataSeriesDescriptor(
            name: L("stats.week"),
            isContinuous: false,
            dataPoints: zip(labels, days).map { AXDataPoint(x: $0.0, y: Double($0.1.count)) }
        )
        return AXChartDescriptor(title: L("stats.week"), summary: nil, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }
}
