import Foundation

/// Small challenges worked out from the history on the phone.
enum Goal: String, CaseIterable, Identifiable {
    case world5, streak7, coldBrew, signature3, milkArtist, mildWeek, recipeMaker

    var id: String { rawValue }
    var title: String { L("goal.\(rawValue).title") }
    var detail: String { L("goal.\(rawValue).detail") }

    var target: Int {
        switch self {
        case .world5: return 5
        case .streak7: return 7
        case .coldBrew: return 1
        case .signature3: return 3
        case .milkArtist: return 6
        case .mildWeek: return 7
        case .recipeMaker: return 3
        }
    }

    /// Progress toward the target (capped at the target).
    func progress(history: [BrewRecord], favorites: [Recipe], life: CoffeeLife, now: Date = Date(),
                  calendar: Calendar = .current) -> Int {
        let done = history.filter(\.completed)
        let value: Int
        switch self {
        case .world5:
            let world = Set(DrinkCollection.world.beverages())
            value = Set(done.map(\.recipe.beverage).filter { world.contains($0) }).count
        case .streak7:
            value = Self.streak(done, now: now, calendar: calendar)
        case .coldBrew:
            value = done.contains { $0.recipe.spec.supportsColdIntensity } ? 1 : 0
        case .signature3:
            value = life.madeSignatures.count
        case .milkArtist:
            value = Set(done.map(\.recipe.beverage).filter { $0.spec.usesMilk }).count
        case .mildWeek:
            // Days in the last week without an extra-strong or extra shot.
            let week = (0..<7).compactMap { calendar.date(byAdding: .day, value: -$0, to: now) }
            value = week.filter { day in
                let cups = done.filter { calendar.isDate($0.date, inSameDayAs: day) }
                return !cups.isEmpty && !cups.contains { $0.recipe.aroma == .extraStrong || $0.recipe.extraShot }
            }.count
        case .recipeMaker:
            value = favorites.filter { !$0.customName.isEmpty }.count
        }
        return min(value, target)
    }

    /// Consecutive days, ending today or yesterday, with at least one cup.
    static func streak(_ records: [BrewRecord], now: Date, calendar: Calendar) -> Int {
        let days = Set(records.map { calendar.startOfDay(for: $0.date) })
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        while days.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }
}

/// The week in numbers: cups, favourite drink, usual time, caffeine.
struct WeeklySummary: Equatable {
    var cups: Int
    var previousCups: Int
    var topDrink: BeverageID?
    var usualHour: Int?
    var averageCaffeine: Int
    var newDrinks: Int

    static func make(history: [BrewRecord], now: Date = Date(), calendar: Calendar = .current) -> WeeklySummary {
        let done = history.filter(\.completed)
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        let week = done.filter { $0.date >= weekAgo && $0.date <= now }
        let before = done.filter { $0.date >= twoWeeksAgo && $0.date < weekAgo }
        var counts: [BeverageID: Int] = [:]
        for record in week { counts[record.recipe.beverage, default: 0] += 1 }
        let top = counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key.rawValue > $1.key.rawValue) }?.key
        var hours: [Int: Int] = [:]
        for record in week { hours[calendar.component(.hour, from: record.date), default: 0] += 1 }
        let usual = hours.max { $0.value < $1.value }?.key
        let caffeine = week.reduce(0) { $0 + CaffeineEstimator.milligrams(for: $1.recipe) }
        let earlier = Set(done.filter { $0.date < weekAgo }.map(\.recipe.beverage))
        let fresh = Set(week.map(\.recipe.beverage)).subtracting(earlier).count
        return WeeklySummary(cups: week.count, previousCups: before.count, topDrink: top, usualHour: usual,
                             averageCaffeine: caffeine / 7, newDrinks: earlier.isEmpty ? 0 : fresh)
    }

    var sentence: String {
        guard cups > 0 else { return L("weekly.none") }
        var parts = [L("weekly.cups", cups)]
        if previousCups > 0 {
            parts.append(cups >= previousCups ? L("weekly.more", cups - previousCups) : L("weekly.fewer", previousCups - cups))
        }
        if let topDrink { parts.append(L("weekly.top", topDrink.name)) }
        if let usualHour { parts.append(L("weekly.hour", usualHour)) }
        parts.append(L("weekly.caffeine", averageCaffeine))
        if newDrinks > 0 { parts.append(L("weekly.new", newDrinks)) }
        return parts.joined(separator: L("sentence.separator"))
    }
}
