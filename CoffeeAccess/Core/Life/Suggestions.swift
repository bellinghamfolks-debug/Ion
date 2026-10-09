import Foundation

/// "Drink of the day", "close to your taste" and "your usual": choices made
/// on the phone from the time, the season and what the person drinks.
enum Suggestions {
    /// One drink per day, stable for the whole day, matching the moment and
    /// the season, preferring drinks the person has not had lately.
    static func drinkOfTheDay(date: Date = Date(), history: [BrewRecord], calendar: Calendar = .current) -> BeverageID {
        let hour = calendar.component(.hour, from: date)
        let month = calendar.component(.month, from: date)
        // October–April is the cooler season: no iced drinks before noon.
        let coolSeason = !(5...9).contains(month)
        var pool = DrinkCollection.suggested.beverages(hour: hour)
        pool = pool.filter { coolSeason ? !$0.spec.isCold || hour >= 12 : true }
        if pool.isEmpty { pool = DrinkCollection.suggested.beverages(hour: hour) }
        let recent = Set(history.prefix(10).map(\.recipe.beverage))
        let fresh = pool.filter { !recent.contains($0) }
        let candidates = fresh.isEmpty ? pool : fresh
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return candidates[day % candidates.count]
    }

    /// The drink to offer on the "ready" card: the first favorite, else the
    /// most made, else a cappuccino.
    static func usual(for data: AppData) -> Recipe {
        if let favorite = data.activeProfile.favorites.first { return favorite }
        if let frequent = data.frequentRecipes(limit: 1).first { return frequent }
        return data.recipe(for: .cappuccino)
    }

    static func last(in history: [BrewRecord]) -> Recipe? {
        history.first { $0.completed }?.recipe
    }

    /// What the person tends to like, from favorites and completed cups.
    struct TasteVector: Equatable {
        var milk: Double = 0     // share of milk drinks
        var cold: Double = 0     // share of cold drinks
        var strength: Double = 3 // average strength 1…5
    }

    static func tasteVector(history: [BrewRecord], favorites: [Recipe]) -> TasteVector? {
        let recipes = favorites + history.filter(\.completed).prefix(60).map(\.recipe)
        guard !recipes.isEmpty else { return nil }
        let count = Double(recipes.count)
        let milk = Double(recipes.filter { $0.spec.usesMilk }.count) / count
        let cold = Double(recipes.filter { $0.spec.isCold }.count) / count
        let strengths = recipes.compactMap { $0.aroma?.rawValue }
        let strength = strengths.isEmpty ? 3 : Double(strengths.reduce(0, +)) / Double(strengths.count)
        return TasteVector(milk: milk, cold: cold, strength: strength)
    }

    /// Up to `limit` drinks the person has not tried, closest to their taste.
    static func closeToTaste(history: [BrewRecord], favorites: [Recipe], limit: Int = 3) -> [BeverageID] {
        guard let taste = tasteVector(history: history, favorites: favorites) else { return [] }
        let tried = Set(history.map(\.recipe.beverage) + favorites.map(\.beverage))
        func distance(_ beverage: BeverageID) -> Double {
            let spec = beverage.spec
            let milk = spec.usesMilk ? 1.0 : 0
            let cold = spec.isCold ? 1.0 : 0
            let strength = Double(spec.defaultAroma.rawValue)
            return abs(milk - taste.milk) * 2 + abs(cold - taste.cold) * 2 + abs(strength - taste.strength) / 2
        }
        return BeverageID.allCases
            .filter { !tried.contains($0) && $0 != .hotWater && !$0.spec.isTea }
            .sorted { distance($0) < distance($1) }
            .prefix(limit)
            .map { $0 }
    }
}
