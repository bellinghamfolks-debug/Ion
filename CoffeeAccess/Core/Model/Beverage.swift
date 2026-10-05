import Foundation

enum BeverageCategory: String, CaseIterable, Codable, Identifiable {
    case coffee, milk, cold, other
    var id: String { rawValue }
}

/// Every drink the app can prepare. The raw value is a stable storage key.
enum BeverageID: String, CaseIterable, Codable, Identifiable {
    case espresso, ristretto, espressoDouble, doppioPlus, coffee, longCoffee
    case americano, longBlack, travelMug
    case cappuccino, cappuccinoPlus, cappuccinoMix, latteMacchiato, caffeLatte
    case flatWhite, espressoMacchiato, cortado, hotMilk
    case overIce, icedCappuccino, icedLatteMacchiato, coldMilk
    case hotWater, tea

    var id: String { rawValue }
    var spec: BeverageSpec { BeverageCatalog.spec(for: self) }
}

extension BeverageID: CodingKeyRepresentable {}

enum Aroma: Int, CaseIterable, Codable, Comparable {
    case extraMild = 1, mild, normal, strong, extraStrong
    static func < (a: Aroma, b: Aroma) -> Bool { a.rawValue < b.rawValue }
}

enum BrewTemperature: Int, CaseIterable, Codable, Comparable {
    case low = 0, medium, high, veryHigh
    static func < (a: BrewTemperature, b: BrewTemperature) -> Bool { a.rawValue < b.rawValue }
}

/// A bounded, stepped numeric setting (millilitres or milk seconds).
struct QuantityRange: Hashable {
    let min: Int
    let max: Int
    let step: Int
    let standard: Int

    func clamp(_ value: Int) -> Int {
        let bounded = Swift.min(Swift.max(value, min), max)
        let offset = ((bounded - min) + step / 2) / step * step
        return Swift.min(min + offset, max)
    }

    func stepped(_ value: Int, by steps: Int) -> Int { clamp(value + steps * step) }

    /// Three quick picks — small, standard, large — inside the range.
    var presets: [Int] {
        let small = clamp(min + (standard - min) / 2)
        let large = clamp(standard + (max - standard) / 2)
        var values: [Int] = []
        for value in [small, standard, large] where !values.contains(value) { values.append(value) }
        return values
    }
}

/// How a drink looks in its glass, bottom layer first.
enum DrinkLayer: String, Hashable {
    case espresso, coffee, crema, milk, foam, water, tea, ice
}

enum Vessel: String, Hashable {
    case espressoCup, cup, tallGlass, mug, travelMug, teaCup, iceGlass
}

struct BeverageSpec: Hashable {
    let id: BeverageID
    /// Beverage code on the ECAM Bluetooth protocol, when one is known.
    let ecamCode: UInt8?
    let category: BeverageCategory
    let vessel: Vessel
    let layers: [DrinkLayer]
    let coffee: QuantityRange?
    let milk: QuantityRange?
    let water: QuantityRange?
    let hasAroma: Bool
    let hasTemperature: Bool
    let supportsMilkFirst: Bool
    let defaultAroma: Aroma
    let defaultTemperature: BrewTemperature

    var usesMilk: Bool { milk != nil }
    var isCold: Bool { category == .cold }
}

enum BeverageCatalog {
    static func spec(for id: BeverageID) -> BeverageSpec { table[id]! }

    static func beverages(in category: BeverageCategory) -> [BeverageID] {
        BeverageID.allCases.filter { $0.spec.category == category }
    }

    private static func make(
        _ id: BeverageID, code: UInt8?, _ category: BeverageCategory, _ vessel: Vessel, _ layers: [DrinkLayer],
        coffee: QuantityRange? = nil, milk: QuantityRange? = nil, water: QuantityRange? = nil,
        aroma: Bool = true, temperature: Bool = true, milkFirst: Bool = false,
        defaultAroma: Aroma = .normal, defaultTemperature: BrewTemperature = .high
    ) -> BeverageSpec {
        BeverageSpec(
            id: id, ecamCode: code, category: category, vessel: vessel, layers: layers,
            coffee: coffee, milk: milk, water: water, hasAroma: aroma, hasTemperature: temperature,
            supportsMilkFirst: milkFirst, defaultAroma: defaultAroma, defaultTemperature: defaultTemperature
        )
    }

    // Ranges follow the machine's usual limits; a connected machine clamps
    // anything outside its own limits, so these are safe defaults.
    private static let table: [BeverageID: BeverageSpec] = {
        let specs: [BeverageSpec] = [
            make(.espresso, code: 0x01, .coffee, .espressoCup, [.espresso, .crema],
                 coffee: QuantityRange(min: 20, max: 80, step: 5, standard: 40)),
            make(.ristretto, code: 0x13, .coffee, .espressoCup, [.espresso, .crema],
                 coffee: QuantityRange(min: 15, max: 40, step: 5, standard: 25), defaultAroma: .strong),
            make(.espressoDouble, code: 0x04, .coffee, .espressoCup, [.espresso, .crema],
                 coffee: QuantityRange(min: 40, max: 160, step: 5, standard: 80)),
            make(.doppioPlus, code: 0x05, .coffee, .cup, [.espresso, .crema],
                 coffee: QuantityRange(min: 80, max: 180, step: 5, standard: 120), aroma: false, defaultAroma: .extraStrong),
            make(.coffee, code: 0x02, .coffee, .cup, [.coffee, .crema],
                 coffee: QuantityRange(min: 100, max: 240, step: 10, standard: 180), defaultAroma: .mild),
            make(.longCoffee, code: 0x03, .coffee, .mug, [.coffee, .crema],
                 coffee: QuantityRange(min: 115, max: 250, step: 5, standard: 160)),
            make(.americano, code: 0x06, .coffee, .mug, [.water, .coffee, .crema],
                 coffee: QuantityRange(min: 20, max: 180, step: 5, standard: 40),
                 water: QuantityRange(min: 50, max: 300, step: 10, standard: 110)),
            make(.longBlack, code: 0x19, .coffee, .mug, [.water, .espresso, .crema],
                 coffee: QuantityRange(min: 40, max: 180, step: 5, standard: 80),
                 water: QuantityRange(min: 50, max: 300, step: 10, standard: 120)),
            make(.travelMug, code: 0x1A, .coffee, .travelMug, [.coffee, .crema],
                 coffee: QuantityRange(min: 150, max: 400, step: 10, standard: 300), defaultAroma: .strong),

            make(.cappuccino, code: 0x07, .milk, .cup, [.espresso, .milk, .foam],
                 coffee: QuantityRange(min: 20, max: 180, step: 5, standard: 60),
                 milk: QuantityRange(min: 5, max: 90, step: 1, standard: 20), milkFirst: true),
            make(.cappuccinoPlus, code: 0x0D, .milk, .cup, [.espresso, .milk, .foam],
                 coffee: QuantityRange(min: 40, max: 180, step: 5, standard: 120),
                 milk: QuantityRange(min: 5, max: 90, step: 1, standard: 20), milkFirst: true, defaultAroma: .strong),
            make(.cappuccinoMix, code: 0x0F, .milk, .cup, [.milk, .espresso, .foam],
                 coffee: QuantityRange(min: 20, max: 180, step: 5, standard: 60),
                 milk: QuantityRange(min: 5, max: 90, step: 1, standard: 20)),
            make(.latteMacchiato, code: 0x08, .milk, .tallGlass, [.milk, .espresso, .foam],
                 coffee: QuantityRange(min: 20, max: 180, step: 5, standard: 60),
                 milk: QuantityRange(min: 5, max: 120, step: 1, standard: 40), milkFirst: true),
            make(.caffeLatte, code: 0x09, .milk, .tallGlass, [.espresso, .milk, .foam],
                 coffee: QuantityRange(min: 20, max: 180, step: 5, standard: 60),
                 milk: QuantityRange(min: 5, max: 120, step: 1, standard: 50), milkFirst: true),
            make(.flatWhite, code: 0x0A, .milk, .cup, [.espresso, .milk, .crema],
                 coffee: QuantityRange(min: 20, max: 180, step: 5, standard: 60),
                 milk: QuantityRange(min: 5, max: 90, step: 1, standard: 25), milkFirst: true),
            make(.espressoMacchiato, code: 0x0B, .milk, .espressoCup, [.espresso, .foam],
                 coffee: QuantityRange(min: 20, max: 80, step: 5, standard: 30),
                 milk: QuantityRange(min: 3, max: 30, step: 1, standard: 6), milkFirst: true),
            make(.cortado, code: 0x18, .milk, .espressoCup, [.espresso, .milk],
                 coffee: QuantityRange(min: 20, max: 80, step: 5, standard: 40),
                 milk: QuantityRange(min: 3, max: 40, step: 1, standard: 10)),
            make(.hotMilk, code: 0x0C, .milk, .cup, [.milk, .foam],
                 milk: QuantityRange(min: 5, max: 120, step: 1, standard: 30), aroma: false, temperature: false),

            make(.overIce, code: 0x1B, .cold, .iceGlass, [.ice, .coffee],
                 coffee: QuantityRange(min: 60, max: 250, step: 10, standard: 120), defaultAroma: .strong),
            make(.icedCappuccino, code: nil, .cold, .iceGlass, [.ice, .espresso, .milk, .foam],
                 coffee: QuantityRange(min: 20, max: 180, step: 5, standard: 60),
                 milk: QuantityRange(min: 5, max: 90, step: 1, standard: 25), temperature: false, defaultAroma: .strong),
            make(.icedLatteMacchiato, code: nil, .cold, .iceGlass, [.ice, .milk, .espresso, .foam],
                 coffee: QuantityRange(min: 20, max: 180, step: 5, standard: 60),
                 milk: QuantityRange(min: 5, max: 120, step: 1, standard: 40), temperature: false),
            make(.coldMilk, code: 0x0E, .cold, .tallGlass, [.milk, .foam],
                 milk: QuantityRange(min: 5, max: 120, step: 1, standard: 30), aroma: false, temperature: false),

            make(.hotWater, code: 0x10, .other, .mug, [.water],
                 water: QuantityRange(min: 20, max: 420, step: 10, standard: 250), aroma: false, temperature: false),
            make(.tea, code: 0x16, .other, .teaCup, [.tea],
                 water: QuantityRange(min: 20, max: 420, step: 10, standard: 250), aroma: false),
        ]
        return Dictionary(uniqueKeysWithValues: specs.map { ($0.id, $0) })
    }()
}
