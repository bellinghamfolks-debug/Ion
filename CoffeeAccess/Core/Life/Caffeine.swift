import Foundation

/// Approximate caffeine in a cup, from the recipe. Real values vary a lot
/// with beans and grind; the app always calls this an estimate.
enum CaffeineEstimator {
    /// Milligrams per millilitre of extracted coffee, by how it is made.
    static let espressoPerML = 2.0      // ~80 mg in a 40 ml espresso
    static let longCoffeePerML = 0.6    // ~110 mg in a 180 ml coffee
    static let coldBrewPerML = 0.9      // slow extraction, stronger per ml
    static let extraShotMg = 60
    static let espressoCap = 180        // a single grind never extracts more

    static func milligrams(for recipe: Recipe) -> Int {
        let spec = recipe.spec
        if spec.isTea {
            switch recipe.beverage {
            case .greenTea: return 30
            case .blackTea: return 45
            default: return 0
            }
        }
        guard let coffee = recipe.coffeeML, spec.layers.contains(where: { $0 == .espresso || $0 == .coffee }) else { return 0 }
        let isColdBrew = spec.supportsColdIntensity
        var mg: Double
        if isColdBrew {
            mg = Double(coffee) * coldBrewPerML * (recipe.coldIntensity == .intense ? 1.3 : 1)
        } else if spec.layers.contains(.espresso) {
            mg = min(Double(coffee) * espressoPerML, Double(espressoCap))
        } else {
            mg = Double(coffee) * longCoffeePerML
        }
        // Each strength step changes the dose by about 10%.
        if let aroma = recipe.aroma { mg *= 1 + Double(aroma.rawValue - Aroma.normal.rawValue) * 0.1 }
        if recipe.extraShot { mg += Double(extraShotMg) }
        return max(0, Int(mg.rounded()))
    }

    static func total(on day: Date, in history: [BrewRecord], calendar: Calendar = .current) -> Int {
        history.filter { $0.completed && calendar.isDate($0.date, inSameDayAs: day) }
            .reduce(0) { $0 + milligrams(for: $1.recipe) }
    }

    /// True when brewing this now would pass the "no coffee after" hour.
    static func isLate(_ recipe: Recipe, cutoffHour: Int, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard cutoffHour >= 0, milligrams(for: recipe) > 0 else { return false }
        return calendar.component(.hour, from: now) >= cutoffHour
    }

    /// A short, honest sentence for the confirmation and the home chip.
    static func warning(for recipe: Recipe, today: Int, limit: Int, cutoffHour: Int, now: Date = Date()) -> String? {
        let cup = milligrams(for: recipe)
        guard cup > 0 else { return nil }
        if isLate(recipe, cutoffHour: cutoffHour, now: now) { return L("caffeine.late", cutoffHour) }
        if today + cup > limit { return L("caffeine.overLimit", today + cup, limit) }
        return nil
    }
}
