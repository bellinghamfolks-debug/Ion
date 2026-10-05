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
        List {
            Section {
                Text(summarySentence)
                    .font(.body)
            }

            Section(L("stats.week")) {
                let days = stats.lastDays(7)
                Chart(days) { day in
                    BarMark(
                        x: .value(L("stats.axis.day"), day.date, unit: .day),
                        y: .value(L("stats.axis.drinks"), day.count)
                    )
                    .foregroundStyle(Theme.accent)
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

            Section(L("stats.byCategory")) {
                let categories = stats.byCategory()
                if categories.isEmpty {
                    Text(L("stats.empty")).foregroundStyle(Theme.textSecondary)
                }
                ForEach(categories) { entry in
                    LabeledContent(entry.category.title, value: L("stats.cups", entry.count))
                }
            }

            Section(L("stats.byDrink")) {
                let drinks = stats.byDrink()
                if drinks.isEmpty {
                    Text(L("stats.empty")).foregroundStyle(Theme.textSecondary)
                }
                ForEach(Array(drinks.prefix(15))) { entry in
                    LabeledContent(entry.beverage.name, value: L("stats.cups", entry.count))
                }
            }

            machineSection

            Section(L("stats.recent")) {
                ForEach(model.activeProfile.history.prefix(20)) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.recipe.displayName).font(.headline)
                        Text("\(record.date.formatted(date: .abbreviated, time: .shortened)) · \(record.completed ? L("stats.completed") : L("stats.notCompleted"))")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle(L("machine.statistics"))
        .refreshable { await model.refreshCounters() }
        .task { await model.refreshCounters() }
    }

    private var summarySentence: String {
        let average = stats.weeklyAverage()
        let favorite = stats.byDrink().first?.beverage.name ?? "—"
        return L("stats.summary", stats.total, String(format: "%.1f", average), favorite)
    }

    @ViewBuilder
    private var machineSection: some View {
        let counters = model.counters
        Section {
            if counters.isEmpty {
                Text(model.connection.isConnected ? L("stats.machine.loading") : L("stats.machine.offline"))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                if let value = counters.totalCoffee { LabeledContent(L("counter.coffee"), value: "\(value)") }
                if let value = counters.milkDrinks { LabeledContent(L("counter.milk"), value: "\(value)") }
                if let value = counters.coldMilk { LabeledContent(L("counter.coldMilk"), value: "\(value)") }
                if let value = counters.tea { LabeledContent(L("counter.tea"), value: "\(value)") }
                if let value = counters.waterLitres { LabeledContent(L("counter.water"), value: L("unit.litres", value)) }
                if let value = counters.descaleCount { LabeledContent(L("counter.descale"), value: "\(value)") }
                if let value = counters.filterReplacements { LabeledContent(L("counter.filter"), value: "\(value)") }
                if let value = counters.milkCleanings { LabeledContent(L("counter.milkClean"), value: "\(value)") }
            }
        } header: {
            Text(L("stats.machine"))
        } footer: {
            if let date = model.countersUpdatedAt {
                Text(L("stats.machine.updated", date.formatted(date: .omitted, time: .shortened)))
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
