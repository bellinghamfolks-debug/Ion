import Foundation

/// When descaling, a new filter and the weekly brewing-unit rinse are next
/// due, from water hardness, how much the machine is used and the care log.
/// Every date is an estimate; the machine's own alerts always win.
struct CareForecast: Equatable {
    struct Item: Equatable, Identifiable {
        var task: CareTask
        var due: Date
        var daysLeft: Int
        var id: CareTask { task }
        var isSoon: Bool { daysLeft <= 7 }
    }

    var items: [Item]
    /// Cups per day over the last four weeks.
    var cupsPerDay: Double

    /// Litres of water between descalings, by hardness 1…4 (no filter).
    static let descaleLitres: [Int: Double] = [1: 160, 2: 120, 3: 80, 4: 50]
    static let filterDays = 60
    static let filterLitres = 50.0
    static let brewingUnitDays = 7

    static func make(history: [BrewRecord], log: CoffeeLife, hardness: Int, usesFilter: Bool,
                     now: Date = Date(), calendar: Calendar = .current) -> CareForecast {
        let monthAgo = calendar.date(byAdding: .day, value: -28, to: now) ?? now
        let recent = history.filter { $0.completed && $0.date >= monthAgo }
        let cupsPerDay = max(0.5, Double(recent.count) / 28)
        let litresPerCup = recent.isEmpty ? 0.2 : recent.reduce(0.0) { $0 + Self.litres($1.recipe) } / Double(recent.count)
        let litresPerDay = cupsPerDay * litresPerCup

        func litresSince(_ date: Date?) -> Double {
            guard let date else { return 0 }
            return history.filter { $0.completed && $0.date >= date }.reduce(0.0) { $0 + Self.litres($1.recipe) }
        }

        var items: [Item] = []
        // Descaling: by water through the machine since the last descaling.
        let interval = (descaleLitres[max(1, min(4, hardness))] ?? 80) * (usesFilter ? 2 : 1)
        let lastDescale = log.lastDone(.descaling)
        let usedSinceDescale = lastDescale == nil ? interval * 0.5 : litresSince(lastDescale)
        let descaleDays = Int(max(0, interval - usedSinceDescale) / max(litresPerDay, 0.05))
        items.append(item(.descaling, inDays: descaleDays, now: now, calendar: calendar))

        if usesFilter {
            let lastFilter = log.lastDone(.waterFilter)
            let ageDays = lastFilter.map { calendar.dateComponents([.day], from: $0, to: now).day ?? 0 } ?? filterDays / 2
            let byTime = filterDays - ageDays
            let byWater = Int(max(0, filterLitres - litresSince(lastFilter)) / max(litresPerDay, 0.05))
            items.append(item(.waterFilter, inDays: max(0, min(byTime, byWater)), now: now, calendar: calendar))
        }

        let lastUnit = log.lastDone(.brewingUnit)
        let unitAge = lastUnit.map { calendar.dateComponents([.day], from: $0, to: now).day ?? 0 } ?? brewingUnitDays
        items.append(item(.brewingUnit, inDays: max(0, brewingUnitDays - unitAge), now: now, calendar: calendar))

        return CareForecast(items: items.sorted { $0.daysLeft < $1.daysLeft }, cupsPerDay: cupsPerDay)
    }

    /// Water used by one drink, including the rinse.
    static func litres(_ recipe: Recipe) -> Double {
        Double((recipe.coffeeML ?? 0) + (recipe.waterML ?? 0) + 30) / 1000
    }

    private static func item(_ task: CareTask, inDays days: Int, now: Date, calendar: Calendar) -> Item {
        let capped = min(days, 365)
        return Item(task: task, due: calendar.date(byAdding: .day, value: capped, to: now) ?? now, daysLeft: capped)
    }
}

/// A shopping list built from the forecast and the bean stock.
enum ShoppingList {
    struct Entry: Equatable, Identifiable {
        var id: String
        var title: String
        var reason: String
    }

    static func entries(forecast: CareForecast, beans: [BeanProfile], profiles: [UserProfile]) -> [Entry] {
        var list: [Entry] = []
        for item in forecast.items where item.daysLeft <= 21 {
            switch item.task {
            case .descaling:
                list.append(Entry(id: "descaler", title: L("shopping.descaler"), reason: L("shopping.dueIn", item.daysLeft)))
            case .waterFilter:
                list.append(Entry(id: "filter", title: L("shopping.filter"), reason: L("shopping.dueIn", item.daysLeft)))
            default: break
            }
        }
        for bean in beans {
            if let stock = BeanStock.estimate(for: bean, profiles: profiles), stock.isLow {
                list.append(Entry(id: "beans-\(bean.id)", title: L("shopping.beans", bean.name),
                                  reason: L("shopping.cupsLeft", stock.cupsLeft)))
            }
        }
        return list
    }

    static func text(_ entries: [Entry]) -> String {
        ([L("shopping.title")] + entries.map { "• \($0.title) — \($0.reason)" }).joined(separator: "\n")
    }
}
