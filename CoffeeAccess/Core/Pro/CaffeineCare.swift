import Foundation

extension CaffeineEstimator {
    /// Decaffeinated beans still carry about 3% of the caffeine.
    static let decafFactor = 0.03
    /// Caffeine's half-life in a healthy adult is about five hours.
    static let halfLifeHours = 5.0

    static func milligrams(for record: BrewRecord, decafBeans: Set<UUID>) -> Int {
        let mg = milligrams(for: record.recipe)
        guard let bean = record.beanID, decafBeans.contains(bean) else { return mg }
        return Int((Double(mg) * decafFactor).rounded())
    }

    /// Today's caffeine, leaving out spilled cups and counting decaf as decaf.
    static func total(on day: Date, in history: [BrewRecord], spilled: Set<UUID>, decafBeans: Set<UUID>,
                      calendar: Calendar = .current) -> Int {
        history.filter { $0.completed && !spilled.contains($0.id) && calendar.isDate($0.date, inSameDayAs: day) }
            .reduce(0) { $0 + milligrams(for: $1, decafBeans: decafBeans) }
    }

    /// Caffeine still in the body now, from the last day's cups.
    static func remaining(at now: Date = Date(), history: [BrewRecord], spilled: Set<UUID> = [], decafBeans: Set<UUID> = []) -> Int {
        let dayAgo = now.addingTimeInterval(-36 * 3600)
        let total = history.filter { $0.completed && !spilled.contains($0.id) && $0.date >= dayAgo && $0.date <= now }
            .reduce(0.0) { sum, record in
                let hours = now.timeIntervalSince(record.date) / 3600
                return sum + Double(milligrams(for: record, decafBeans: decafBeans)) * pow(0.5, hours / halfLifeHours)
            }
        return Int(total.rounded())
    }

    /// When the caffeine left will drop under `threshold` mg (nil if already under).
    static func time(below threshold: Int, from now: Date = Date(), history: [BrewRecord], spilled: Set<UUID> = [],
                     decafBeans: Set<UUID> = []) -> Date? {
        let current = remaining(at: now, history: history, spilled: spilled, decafBeans: decafBeans)
        guard current > threshold, threshold > 0 else { return nil }
        let hours = halfLifeHours * log2(Double(current) / Double(threshold))
        return now.addingTimeInterval(hours * 3600)
    }

    /// Cups by hour of day over the last month, for the hourly chart.
    static func byHour(_ history: [BrewRecord], now: Date = Date(), calendar: Calendar = .current) -> [Int] {
        let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        var hours = Array(repeating: 0, count: 24)
        for record in history where record.completed && record.date >= start {
            hours[calendar.component(.hour, from: record.date)] += 1
        }
        return hours
    }
}

/// Daily limits from health authorities, to pick instead of typing a number.
enum CaffeineLimitPreset: Int, CaseIterable, Identifiable {
    case adult = 400
    case pregnancy = 200
    case teen = 100

    var id: Int { rawValue }
    var title: String { L("limit.\(String(describing: self)).title") }
    var source: String { L("limit.\(String(describing: self)).source") }
}

/// Ramadan: coffee moves to the evening, so the "too late" note is off and
/// suhoor advice is shown instead.
enum RamadanMode {
    static func isActive(setting: Int, date: Date = Date()) -> Bool {
        switch setting {
        case 1: return true
        case 2: return false
        default: return Season.current(on: date).contains(.ramadan)
        }
    }
}

/// The month in numbers: cups, caffeine, beans, spending and savings.
struct MonthlyReport: Equatable {
    var cups: Int
    var topDrink: BeverageID?
    var averageCaffeine: Int
    var beansGrams: Int
    var homeCost: Double?
    var savings: Double?
    var energyKWh: Double
    var careDone: Int
    var alarms: Int

    static func make(data: AppData, cafePrice: Double, now: Date = Date(), calendar: Calendar = .current) -> MonthlyReport {
        let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let history = data.profiles.flatMap(\.history).filter { $0.completed && $0.date >= start }
        let pro = data.life.pro
        let spilled = Set(pro.spilled)
        let drunk = history.filter { !spilled.contains($0.id) }
        let decaf = Set(data.beanProfiles.filter(\.decaf).map(\.id))
        let counts = Dictionary(grouping: drunk, by: \.recipe.beverage).mapValues(\.count)
        let top = counts.max { $0.value == $1.value ? $0.key.rawValue > $1.key.rawValue : $0.value < $1.value }?.key
        let days = max(1, Set(drunk.map { calendar.startOfDay(for: $0.date) }).count)
        let caffeine = drunk.reduce(0) { $0 + CaffeineEstimator.milligrams(for: $1, decafBeans: decaf) }
        let grams = history.reduce(0.0) { $0 + BeanStock.grams(for: $1.recipe) * Double($1.recipe.cupCount) }
        var cost: Double?
        for record in history {
            let bean = data.beanProfiles.first { $0.id == record.beanID } ?? data.activeBean
            if let cup = CostPerCup.total(for: record.recipe, bean: bean, milkPricePerLitre: pro.milkPricePerLitre) {
                cost = (cost ?? 0) + cup
            }
        }
        let cupCount = history.reduce(0) { $0 + $1.recipe.cupCount }
        let savings = cost.map { Double(cupCount) * cafePrice - $0 }
        return MonthlyReport(
            cups: cupCount, topDrink: top, averageCaffeine: caffeine / days, beansGrams: Int(grams.rounded()),
            homeCost: cost, savings: savings, energyKWh: EnergyEstimate.month(history: history, now: now, calendar: calendar),
            careDone: data.life.maintenanceLog.filter { $0.date >= start }.count,
            alarms: pro.alarmHistory.filter { $0.date >= start }.count)
    }
}

/// The history as a spreadsheet (CSV), for the person's own records.
enum HistoryExport {
    static func csv(data: AppData) -> String {
        let format = ISO8601DateFormatter()
        let spilled = Set(data.life.pro.spilled)
        let decaf = Set(data.beanProfiles.filter(\.decaf).map(\.id))
        var rows = ["date,profile,drink,coffee_ml,water_ml,milk_seconds,strength,cups,completed,spilled,caffeine_mg,bean,liked,note"]
        for profile in data.profiles {
            for record in profile.history {
                let recipe = record.recipe
                let bean = data.beanProfiles.first { $0.id == record.beanID }?.name ?? ""
                let rating = data.life.ratings[record.id]
                let fields: [String] = [
                    format.string(from: record.date), profile.name, recipe.displayName,
                    recipe.coffeeML.map(String.init) ?? "", recipe.waterML.map(String.init) ?? "",
                    recipe.milkSeconds.map(String.init) ?? "", recipe.aroma.map { "\($0.rawValue)" } ?? "",
                    "\(recipe.cupCount)", record.completed ? "1" : "0", spilled.contains(record.id) ? "1" : "0",
                    "\(spilled.contains(record.id) ? 0 : CaffeineEstimator.milligrams(for: record, decafBeans: decaf))",
                    bean, rating?.liked.map { $0 ? "1" : "0" } ?? "", rating?.note ?? "",
                ]
                rows.append(fields.map(escape).joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n")
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
