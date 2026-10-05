import Foundation

/// A drink with the learner's chosen settings. Settings that a beverage does
/// not have stay `nil`, so a recipe never carries a meaningless value.
struct Recipe: Codable, Hashable, Identifiable {
    var id = UUID()
    var beverage: BeverageID
    /// A personal name ("My morning coffee"); empty for the standard drink.
    var customName: String = ""
    var coffeeML: Int?
    var milkSeconds: Int?
    var waterML: Int?
    var aroma: Aroma?
    var temperature: BrewTemperature?
    var milkFirst: Bool = false

    var spec: BeverageSpec { beverage.spec }

    static func standard(_ beverage: BeverageID) -> Recipe {
        let spec = beverage.spec
        return Recipe(
            beverage: beverage,
            coffeeML: spec.coffee?.standard,
            milkSeconds: spec.milk?.standard,
            waterML: spec.water?.standard,
            aroma: spec.hasAroma ? spec.defaultAroma : nil,
            temperature: spec.hasTemperature ? spec.defaultTemperature : nil,
            milkFirst: false
        )
    }

    /// Brings every setting back inside the beverage's limits and drops
    /// settings the beverage does not support (e.g. after a catalog change).
    func normalized() -> Recipe {
        let spec = beverage.spec
        var copy = self
        copy.coffeeML = spec.coffee.map { $0.clamp(coffeeML ?? $0.standard) }
        copy.milkSeconds = spec.milk.map { $0.clamp(milkSeconds ?? $0.standard) }
        copy.waterML = spec.water.map { $0.clamp(waterML ?? $0.standard) }
        copy.aroma = spec.hasAroma ? (aroma ?? spec.defaultAroma) : nil
        copy.temperature = spec.hasTemperature ? (temperature ?? spec.defaultTemperature) : nil
        copy.milkFirst = spec.supportsMilkFirst && milkFirst
        copy.customName = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    /// True when the settings match the standard drink (ignores id and name).
    var isStandard: Bool {
        var standard = Recipe.standard(beverage)
        standard.id = id
        standard.customName = customName
        return standard == normalized()
    }

    /// Approximate total volume in the cup, for the illustration and summary.
    var approximateVolumeML: Int {
        // On these machines a second of frothed milk is roughly 7-8 ml in the cup.
        (coffeeML ?? 0) + (waterML ?? 0) + (milkSeconds ?? 0) * 15 / 2
    }

    /// Rough preparation time in seconds, used for progress when the machine
    /// does not report its own percentage.
    var estimatedSeconds: Int {
        let grind = coffeeML == nil ? 0 : 12
        let coffee = (coffeeML ?? 0) / 3
        let water = (waterML ?? 0) / 8
        let milk = milkSeconds ?? 0
        return max(8, grind + coffee + water + milk)
    }
}
