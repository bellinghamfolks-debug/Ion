import Foundation

/// "Know your drink": where it comes from, how much coffee to milk, and the
/// cup it belongs in. Ratios are worked out from the recipe itself.
enum DrinkKnowledge {
    static func origin(_ beverage: BeverageID) -> String { L("drink.\(beverage.rawValue).origin") }

    static func vessel(_ beverage: BeverageID) -> String { L("vessel.\(beverage.spec.vessel.rawValue)") }

    /// "1 coffee : 3 milk", or nil for drinks without both.
    static func ratio(_ recipe: Recipe) -> String? {
        let coffee = (recipe.coffeeML ?? 0)
        let milk = recipe.approximateMilkML
        guard coffee > 0, milk > 0 else { return nil }
        if milk >= coffee {
            return L("knowledge.ratio.milk", max(1, Int((Double(milk) / Double(coffee)).rounded())))
        }
        return L("knowledge.ratio.coffee", max(1, Int((Double(coffee) / Double(milk)).rounded())))
    }

    /// One sentence saying how the two differ most.
    static func comparison(_ a: Recipe, _ b: Recipe) -> String {
        let volume = a.approximateVolumeML - b.approximateVolumeML
        let caffeine = CaffeineEstimator.milligrams(for: a) - CaffeineEstimator.milligrams(for: b)
        var parts: [String] = []
        if abs(volume) >= 30 {
            parts.append(L("knowledge.bigger", volume > 0 ? a.displayName : b.displayName, abs(volume)))
        }
        if abs(caffeine) >= 20 {
            parts.append(L("knowledge.moreCaffeine", caffeine > 0 ? a.displayName : b.displayName, abs(caffeine)))
        }
        if a.spec.usesMilk != b.spec.usesMilk {
            parts.append(L("knowledge.milkOnly", a.spec.usesMilk ? a.displayName : b.displayName))
        }
        return parts.isEmpty ? L("knowledge.similar") : parts.joined(separator: L("sentence.separator"))
    }
}
