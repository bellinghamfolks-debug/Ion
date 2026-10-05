import Foundation

/// Milk froth dial positions, matching the machine's small/medium/large foam.
enum FoamLevel: String, CaseIterable, Codable {
    case small, medium, large
    var title: String { L("foam.\(rawValue)") }
}

/// Cold-brew strength choice, as the machine's pre-brew sheet offers it.
enum ColdIntensity: String, CaseIterable, Codable {
    case original, intense
    var title: String { L("cold.intensity.\(rawValue)") }
}

/// How much ice, as the machine's pre-brew sheet offers it.
enum IceLevel: String, CaseIterable, Codable {
    case ice, extraIce
    var title: String { L("cold.ice.\(rawValue)") }
    var cubes: Int { self == .extraIce ? 6 : 4 }
}

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
    /// Travel-mug size: larger amounts, for drinks that support it.
    var toGo: Bool = false
    /// An extra 30 ml coffee shot added to the drink, as on the machine.
    var extraShot: Bool = false
    /// Cold-brew strength, for cold-brew drinks only.
    var coldIntensity: ColdIntensity?
    /// Ice amount, for iced drinks only.
    var iceLevel: IceLevel?

    var spec: BeverageSpec { beverage.spec }
    var coffeeRange: QuantityRange? { spec.coffeeRange(toGo: toGo) }
    var milkRange: QuantityRange? { spec.milkRange(toGo: toGo) }
    var waterRange: QuantityRange? { spec.waterRange(toGo: toGo) }

    static func standard(_ beverage: BeverageID, toGo: Bool = false) -> Recipe {
        let spec = beverage.spec
        let toGo = toGo && spec.supportsToGo
        return Recipe(
            beverage: beverage,
            coffeeML: spec.coffeeRange(toGo: toGo)?.standard,
            milkSeconds: spec.milkRange(toGo: toGo)?.standard,
            waterML: spec.waterRange(toGo: toGo)?.standard,
            aroma: spec.hasAroma ? spec.defaultAroma : nil,
            temperature: spec.hasTemperature ? spec.defaultTemperature : nil,
            milkFirst: false,
            toGo: toGo
        )
    }

    /// Brings every setting back inside the beverage's limits and drops
    /// settings the beverage does not support (e.g. after a catalog change).
    func normalized() -> Recipe {
        let spec = beverage.spec
        var copy = self
        copy.toGo = spec.supportsToGo && toGo
        copy.coffeeML = copy.coffeeRange.map { $0.clamp(coffeeML ?? $0.standard) }
        copy.milkSeconds = copy.milkRange.map { $0.clamp(milkSeconds ?? $0.standard) }
        copy.waterML = copy.waterRange.map { $0.clamp(waterML ?? $0.standard) }
        copy.aroma = spec.hasAroma ? (aroma ?? spec.defaultAroma) : nil
        copy.temperature = spec.hasTemperature ? (temperature ?? spec.defaultTemperature) : nil
        copy.milkFirst = spec.supportsMilkFirst && milkFirst
        copy.extraShot = spec.supportsExtraShot && extraShot
        copy.coldIntensity = spec.supportsColdIntensity ? (coldIntensity ?? .original) : nil
        copy.iceLevel = spec.supportsIce ? (iceLevel ?? .ice) : nil
        copy.customName = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    /// The milk froth dial position to suggest, so the cup matches the recipe.
    /// Advisory only — the dial is turned by hand on the machine.
    var idealFoamLevel: FoamLevel? {
        guard let milk = milkSeconds, spec.usesMilk else { return nil }
        let range = milkRange ?? spec.milk
        let span = (range?.max ?? 120) - (range?.min ?? 0)
        guard span > 0 else { return .medium }
        let fraction = Double(milk - (range?.min ?? 0)) / Double(span)
        return fraction < 0.34 ? .small : (fraction < 0.67 ? .medium : .large)
    }

    /// Switches between cup and travel-mug size, scaling the amounts.
    func withToGo(_ enabled: Bool) -> Recipe {
        guard spec.supportsToGo, enabled != toGo else { return self }
        var copy = self
        copy.toGo = enabled
        let factor = enabled ? 2.0 : 0.5
        if let coffee = coffeeML { copy.coffeeML = Int(Double(coffee) * factor) }
        if let milk = milkSeconds { copy.milkSeconds = Int(Double(milk) * factor) }
        if let water = waterML { copy.waterML = Int(Double(water) * factor) }
        return copy.normalized()
    }

    /// True when the settings match the standard drink (ignores id and name).
    var isStandard: Bool {
        var standard = Recipe.standard(beverage, toGo: toGo)
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
        let perML = spec.isCold && spec.layers.contains(.coffee) ? 2 : 3   // cold extraction is slower
        let coffee = (coffeeML ?? 0) / (spec.vessel == .pot ? 6 : perML)
        let water = (waterML ?? 0) / 8
        let milk = milkSeconds ?? 0
        let shot = extraShot ? 14 : 0
        return max(8, grind + coffee + water + milk + shot)
    }
}

/// Bean Adapt: a profile per bag of beans. The machine's grinder is set by
/// hand, so the app recommends a grind setting and adjusts the default
/// strength and temperature of every drink for the beans in the hopper.
struct BeanProfile: Codable, Hashable, Identifiable {
    enum Roast: String, Codable, CaseIterable { case light, medium, dark }
    enum Kind: String, Codable, CaseIterable { case arabica, blend, robusta }

    var id = UUID()
    var name: String
    var roast: Roast = .medium
    var kind: Kind = .blend
    /// −1 milder, 0 as recommended, +1 stronger.
    var strengthBias: Int = 0

    static let maxCount = 6

    /// Grinder setting 1 (finest) … 13 (coarsest). Darker, oilier beans and
    /// robusta grind coarser to avoid over-extraction and grinder clogging.
    var recommendedGrind: Int {
        var setting: Int
        switch roast {
        case .light: setting = 4
        case .medium: setting = 6
        case .dark: setting = 8
        }
        if kind == .robusta { setting += 1 }
        if kind == .arabica && roast == .light { setting -= 1 }
        return max(1, min(13, setting))
    }

    /// Light roasts extract best hotter, dark roasts cooler.
    var recommendedTemperature: BrewTemperature {
        switch roast {
        case .light: return .high
        case .medium: return .medium
        case .dark: return .low
        }
    }

    func adjust(_ recipe: Recipe) -> Recipe {
        var copy = recipe
        let spec = recipe.spec
        if spec.hasTemperature, recipe.temperature == spec.defaultTemperature, !spec.isTea {
            copy.temperature = recommendedTemperature
        }
        if spec.hasAroma, let aroma = recipe.aroma, strengthBias != 0 {
            copy.aroma = Aroma(rawValue: max(1, min(5, aroma.rawValue + strengthBias))) ?? aroma
        }
        return copy
    }
}
