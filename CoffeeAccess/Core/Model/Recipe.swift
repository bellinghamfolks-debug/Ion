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
    /// Two cups at once from the double spout ("2x"), where the drink allows it.
    var double: Bool?

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
            toGo: toGo,
            coldIntensity: spec.supportsColdIntensity ? .original : nil,
            iceLevel: spec.supportsIce ? .ice : nil
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
        copy.double = spec.supportsDouble && double == true && !copy.toGo ? true : nil
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

    /// On these machines a second of frothed milk is roughly 7-8 ml in the cup.
    var approximateMilkML: Int { (milkSeconds ?? 0) * 15 / 2 }

    /// Approximate total volume in the cup, for the illustration and summary.
    var approximateVolumeML: Int {
        (coffeeML ?? 0) + (waterML ?? 0) + approximateMilkML
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

/// The character of the cup a bean gives, for the coffee profile page.
enum TasteFlavour: String, CaseIterable {
    case fruity, balanced, chocolatey, bold
}

struct TasteProfile: Equatable {
    let flavour: TasteFlavour
    /// 1 (flat) … 10 (bright).
    let acidity: Int
    /// 1 (light, tea-like) … 10 (heavy, syrupy).
    let body: Int
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
    /// Steps finer (−) or coarser (+) than the starting point, from tasting.
    var grindOffset: Int = 0
    /// A temperature chosen while tasting, instead of the roast's default.
    var temperatureOverride: BrewTemperature?
    /// Bag weight in grams when it was opened, for the stock estimate.
    var bagGrams: Int?
    var openedAt: Date?
    var origin: String = ""
    var roaster: String = ""
    /// Tasting notes kept with the beans.
    var notes: String = ""
    // Version 3
    var roastDate: Date?
    /// Price paid for the bag, in the person's currency.
    var price: Double?
    var decaf = false
    /// 1…5 stars for the bag.
    var rating: Int?
    var buyAgain = false
    var barcode: String = ""
    /// Grind settings tried with these beans and how the cup was rated.
    var grindNotes: [GrindNote] = []

    static let maxCount = 6

    /// The grind to set, including what tasting taught.
    var recommendedGrind: Int { max(1, min(13, baseGrind + grindOffset)) }

    /// Grinder setting 1 (finest) … 13 (coarsest). Darker, oilier beans and
    /// robusta grind coarser to avoid over-extraction and grinder clogging.
    var baseGrind: Int {
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
    var recommendedTemperature: BrewTemperature { temperatureOverride ?? roastTemperature }

    var roastTemperature: BrewTemperature {
        switch roast {
        case .light: return .high
        case .medium: return .medium
        case .dark: return .low
        }
    }

    /// Light roasts and arabica are brighter and lighter; dark roasts and
    /// robusta are heavier, lower in acidity and more chocolatey.
    var taste: TasteProfile {
        var acidity: Int
        var body: Int
        let flavour: TasteFlavour
        switch roast {
        case .light:
            acidity = 8; body = 4
            flavour = kind == .robusta ? .balanced : .fruity
        case .medium:
            acidity = 5; body = 6
            flavour = kind == .robusta ? .chocolatey : .balanced
        case .dark:
            acidity = 3; body = 8
            flavour = kind == .robusta ? .bold : .chocolatey
        }
        switch kind {
        case .arabica: acidity += 1; body -= 1
        case .blend: break
        case .robusta: acidity -= 2; body += 2
        }
        return TasteProfile(flavour: flavour, acidity: max(1, min(10, acidity)), body: max(1, min(10, body)))
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

extension BeanProfile {
    /// Bean profiles saved before version 2 have none of the newer fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        roast = (try? c.decodeIfPresent(Roast.self, forKey: .roast)) ?? .medium
        kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .blend
        strengthBias = (try? c.decodeIfPresent(Int.self, forKey: .strengthBias)) ?? 0
        grindOffset = (try? c.decodeIfPresent(Int.self, forKey: .grindOffset)) ?? 0
        temperatureOverride = try? c.decodeIfPresent(BrewTemperature.self, forKey: .temperatureOverride)
        bagGrams = try? c.decodeIfPresent(Int.self, forKey: .bagGrams)
        openedAt = try? c.decodeIfPresent(Date.self, forKey: .openedAt)
        origin = (try? c.decodeIfPresent(String.self, forKey: .origin)) ?? ""
        roaster = (try? c.decodeIfPresent(String.self, forKey: .roaster)) ?? ""
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
        roastDate = try? c.decodeIfPresent(Date.self, forKey: .roastDate)
        price = try? c.decodeIfPresent(Double.self, forKey: .price)
        decaf = (try? c.decodeIfPresent(Bool.self, forKey: .decaf)) ?? false
        rating = try? c.decodeIfPresent(Int.self, forKey: .rating)
        buyAgain = (try? c.decodeIfPresent(Bool.self, forKey: .buyAgain)) ?? false
        barcode = (try? c.decodeIfPresent(String.self, forKey: .barcode)) ?? ""
        grindNotes = (try? c.decodeIfPresent([GrindNote].self, forKey: .grindNotes)) ?? []
    }
}

/// One grind setting tried with a bag, and how the cup turned out.
struct GrindNote: Codable, Hashable {
    var grind: Int
    /// 1…5.
    var rating: Int
    var date = Date()
}
