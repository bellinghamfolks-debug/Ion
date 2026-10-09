import Foundation

/// The machine's five menus.
enum BeverageCategory: String, CaseIterable, Codable, Identifiable {
    case hotCoffee, milk, coldCoffee, coldMilk, teaWater
    var id: String { rawValue }
}

/// Every drink on the Eletta Ultra menu. The raw value is a stable storage key.
enum BeverageID: String, CaseIterable, Codable, Identifiable {
    // Hot coffee
    case espresso, ristretto, espressoIntenso, espressoDouble, espressoLungo, doppioPlus
    case coffee, americano, filterCoffee, mildFilter, coffeePot, verlaengerter, redEye, blackEye
    // Milk
    case cappuccino, cappuccinoPlus, cappuccinoMix, latteMacchiato, caffeLatte, flatWhite
    case espressoMacchiato, cortado, hotMilk, babyccino, cafeAuLait, cafeConLeche, galao
    case milchkaffee, koffieVerkeerd
    // Cold coffee
    case coldBrew, coldBrewPot, coldBrewToMix, icedCoffee, icedEspresso, icedAmericano
    // Cold milk
    case coldBrewCappuccino, coldBrewLatte, icedCaffeLatte, icedCappuccino, icedCappuccinoMix
    case icedFlatWhite, icedLatteMacchiato, coldMilk
    // Tea and water
    case hotWater, greenTea, blackTea, herbalTea

    var id: String { rawValue }
    var spec: BeverageSpec { BeverageCatalog.spec(for: self) }
}

extension BeverageID: CodingKeyRepresentable {}

enum Aroma: Int, CaseIterable, Codable, Comparable {
    case extraMild = 1, mild, normal, strong, extraStrong
    static func < (a: Aroma, b: Aroma) -> Bool { a.rawValue < b.rawValue }
}

/// The Eletta Ultra offers three coffee temperatures.
enum BrewTemperature: Int, CaseIterable, Codable, Comparable {
    case low = 0, medium, high
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

    /// The same setting for a travel mug: twice the usual amount, up to `cap`.
    func toGo(cap: Int) -> QuantityRange {
        let newMax = Swift.max(max, Swift.min(max * 2, cap))
        let scaled = QuantityRange(min: min, max: newMax, step: step, standard: min)
        return QuantityRange(min: min, max: newMax, step: step, standard: scaled.clamp(standard * 2))
    }
}

/// How a drink looks in its glass, bottom layer first.
enum DrinkLayer: String, Hashable {
    case espresso, coffee, crema, milk, foam, water, tea, ice
}

enum Vessel: String, Hashable {
    case espressoCup, cup, tallGlass, mug, travelMug, teaCup, iceGlass, pot
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
    let supportsToGo: Bool
    let defaultAroma: Aroma
    let defaultTemperature: BrewTemperature

    var usesMilk: Bool { milk != nil }
    var isCold: Bool { category == .coldCoffee || category == .coldMilk }
    var isTea: Bool { id == .greenTea || id == .blackTea || id == .herbalTea }
    /// An extra 30 ml shot is offered on hot drinks that already pull coffee,
    /// except the pot and the already-double espressos.
    var supportsExtraShot: Bool {
        coffee != nil && !isCold && vessel != .pot && !isTea
            && id != .espressoDouble && id != .doppioPlus && id != .espresso && id != .ristretto
    }
    /// Cold-brew drinks offer an Original / Intense strength choice.
    var supportsColdIntensity: Bool { coffee != nil && (id == .coldBrew || id == .coldBrewPot || id == .coldBrewToMix || id == .coldBrewCappuccino || id == .coldBrewLatte) }
    /// Iced drinks served over ice offer an ice-amount choice.
    var supportsIce: Bool { layers.contains(.ice) }
    /// Two cups at once from the double spout.
    var supportsDouble: Bool { [.espresso, .ristretto, .espressoLungo, .coffee].contains(id) }

    func coffeeRange(toGo: Bool) -> QuantityRange? { toGo && supportsToGo ? coffee?.toGo(cap: 450) : coffee }
    func milkRange(toGo: Bool) -> QuantityRange? { toGo && supportsToGo ? milk?.toGo(cap: 180) : milk }
    func waterRange(toGo: Bool) -> QuantityRange? { toGo && supportsToGo ? water?.toGo(cap: 450) : water }
}

enum BeverageCatalog {
    static func spec(for id: BeverageID) -> BeverageSpec { table[id]! }

    static func beverages(in category: BeverageCategory) -> [BeverageID] {
        BeverageID.allCases.filter { $0.spec.category == category }
    }

    private static func q(_ min: Int, _ max: Int, _ step: Int, _ standard: Int) -> QuantityRange {
        QuantityRange(min: min, max: max, step: step, standard: standard)
    }

    private static func make(
        _ id: BeverageID, code: UInt8?, _ category: BeverageCategory, _ vessel: Vessel, _ layers: [DrinkLayer],
        coffee: QuantityRange? = nil, milk: QuantityRange? = nil, water: QuantityRange? = nil,
        aroma: Bool = true, temperature: Bool = true, milkFirst: Bool = false, toGo: Bool = false,
        defaultAroma: Aroma = .normal, defaultTemperature: BrewTemperature = .medium
    ) -> BeverageSpec {
        BeverageSpec(
            id: id, ecamCode: code, category: category, vessel: vessel, layers: layers,
            coffee: coffee, milk: milk, water: water, hasAroma: aroma, hasTemperature: temperature,
            supportsMilkFirst: milkFirst, supportsToGo: toGo, defaultAroma: defaultAroma, defaultTemperature: defaultTemperature
        )
    }

    // Ranges follow the machine's usual limits; a connected machine clamps
    // anything outside its own limits, so these are safe defaults. Codes are
    // only filled in where the ECAM protocol code is documented.
    private static let table: [BeverageID: BeverageSpec] = {
        let milkShort = q(3, 40, 1, 10)
        let milkCup = q(5, 90, 1, 20)
        let milkTall = q(5, 120, 1, 40)
        let specs: [BeverageSpec] = [
            // Hot coffee
            make(.espresso, code: 0x01, .hotCoffee, .espressoCup, [.espresso, .crema], coffee: q(20, 80, 5, 40)),
            make(.ristretto, code: 0x13, .hotCoffee, .espressoCup, [.espresso, .crema], coffee: q(15, 40, 5, 25), defaultAroma: .strong),
            make(.espressoIntenso, code: nil, .hotCoffee, .espressoCup, [.espresso, .crema], coffee: q(20, 80, 5, 35), defaultAroma: .extraStrong),
            make(.espressoDouble, code: 0x04, .hotCoffee, .espressoCup, [.espresso, .crema], coffee: q(40, 160, 5, 80)),
            make(.espressoLungo, code: 0x14, .hotCoffee, .cup, [.espresso, .crema], coffee: q(60, 150, 5, 100)),
            make(.doppioPlus, code: 0x05, .hotCoffee, .cup, [.espresso, .crema], coffee: q(80, 180, 5, 120), aroma: false, defaultAroma: .extraStrong),
            make(.coffee, code: 0x02, .hotCoffee, .cup, [.coffee, .crema], coffee: q(100, 240, 10, 180), toGo: true, defaultAroma: .mild),
            make(.americano, code: 0x06, .hotCoffee, .mug, [.water, .coffee, .crema], coffee: q(20, 180, 5, 40), water: q(50, 300, 10, 110), toGo: true),
            make(.filterCoffee, code: nil, .hotCoffee, .mug, [.coffee], coffee: q(100, 400, 10, 250), toGo: true),
            make(.mildFilter, code: nil, .hotCoffee, .mug, [.coffee], coffee: q(100, 400, 10, 250), toGo: true, defaultAroma: .mild),
            make(.coffeePot, code: 0x17, .hotCoffee, .pot, [.coffee], coffee: q(250, 1000, 50, 500)),
            make(.verlaengerter, code: nil, .hotCoffee, .cup, [.water, .espresso, .crema], coffee: q(30, 120, 5, 60), water: q(40, 200, 10, 90)),
            make(.redEye, code: nil, .hotCoffee, .mug, [.coffee, .espresso, .crema], coffee: q(150, 350, 10, 220), toGo: true, defaultAroma: .strong),
            make(.blackEye, code: nil, .hotCoffee, .mug, [.coffee, .espresso, .crema], coffee: q(170, 400, 10, 260), toGo: true, defaultAroma: .extraStrong),

            // Milk
            make(.cappuccino, code: 0x07, .milk, .cup, [.espresso, .milk, .foam], coffee: q(20, 180, 5, 60), milk: milkCup, milkFirst: true, toGo: true),
            make(.cappuccinoPlus, code: 0x0D, .milk, .cup, [.espresso, .milk, .foam], coffee: q(40, 180, 5, 120), milk: milkCup, milkFirst: true, defaultAroma: .strong),
            make(.cappuccinoMix, code: 0x0F, .milk, .cup, [.milk, .espresso, .foam], coffee: q(20, 180, 5, 60), milk: milkCup),
            make(.latteMacchiato, code: 0x08, .milk, .tallGlass, [.milk, .espresso, .foam], coffee: q(20, 180, 5, 60), milk: milkTall, milkFirst: true, toGo: true),
            make(.caffeLatte, code: 0x09, .milk, .tallGlass, [.espresso, .milk, .foam], coffee: q(20, 180, 5, 60), milk: q(5, 120, 1, 50), milkFirst: true, toGo: true),
            make(.flatWhite, code: 0x0A, .milk, .cup, [.espresso, .milk, .crema], coffee: q(20, 180, 5, 60), milk: q(5, 90, 1, 25), milkFirst: true, toGo: true),
            make(.espressoMacchiato, code: 0x0B, .milk, .espressoCup, [.espresso, .foam], coffee: q(20, 80, 5, 30), milk: q(3, 30, 1, 6), milkFirst: true),
            make(.cortado, code: 0x18, .milk, .espressoCup, [.espresso, .milk], coffee: q(20, 80, 5, 40), milk: milkShort),
            make(.hotMilk, code: 0x0C, .milk, .cup, [.milk, .foam], milk: q(5, 120, 1, 30), aroma: false, temperature: false, toGo: true),
            make(.babyccino, code: nil, .milk, .espressoCup, [.milk, .foam], milk: q(5, 60, 1, 15), aroma: false, temperature: false),
            make(.cafeAuLait, code: nil, .milk, .cup, [.coffee, .milk], coffee: q(60, 250, 10, 120), milk: q(5, 90, 1, 30), defaultAroma: .mild),
            make(.cafeConLeche, code: nil, .milk, .cup, [.espresso, .milk], coffee: q(20, 120, 5, 50), milk: q(5, 90, 1, 30)),
            make(.galao, code: nil, .milk, .tallGlass, [.espresso, .milk, .foam], coffee: q(20, 80, 5, 40), milk: q(5, 120, 1, 45), defaultAroma: .mild),
            make(.milchkaffee, code: nil, .milk, .mug, [.coffee, .milk, .foam], coffee: q(80, 250, 10, 150), milk: q(5, 90, 1, 30), toGo: true),
            make(.koffieVerkeerd, code: nil, .milk, .mug, [.milk, .coffee], coffee: q(40, 150, 5, 80), milk: q(5, 120, 1, 45), defaultAroma: .mild),

            // Cold coffee
            make(.coldBrew, code: nil, .coldCoffee, .iceGlass, [.ice, .coffee], coffee: q(60, 250, 10, 150), temperature: false, toGo: true),
            make(.coldBrewPot, code: nil, .coldCoffee, .pot, [.coffee], coffee: q(250, 1000, 50, 500), temperature: false),
            make(.coldBrewToMix, code: nil, .coldCoffee, .espressoCup, [.coffee], coffee: q(30, 120, 5, 60), temperature: false, defaultAroma: .strong),
            make(.icedCoffee, code: 0x1B, .coldCoffee, .iceGlass, [.ice, .coffee], coffee: q(60, 250, 10, 120), toGo: true, defaultAroma: .strong),
            make(.icedEspresso, code: nil, .coldCoffee, .iceGlass, [.ice, .espresso], coffee: q(20, 80, 5, 40), defaultAroma: .strong),
            make(.icedAmericano, code: nil, .coldCoffee, .iceGlass, [.ice, .water, .espresso], coffee: q(20, 180, 5, 40), water: q(50, 300, 10, 110), toGo: true),

            // Cold milk
            make(.coldBrewCappuccino, code: nil, .coldMilk, .iceGlass, [.ice, .coffee, .milk, .foam], coffee: q(60, 200, 10, 100), milk: q(5, 90, 1, 25), temperature: false),
            make(.coldBrewLatte, code: nil, .coldMilk, .iceGlass, [.ice, .coffee, .milk, .foam], coffee: q(60, 200, 10, 100), milk: milkTall, temperature: false, toGo: true),
            make(.icedCaffeLatte, code: nil, .coldMilk, .iceGlass, [.ice, .espresso, .milk, .foam], coffee: q(20, 180, 5, 60), milk: q(5, 120, 1, 50), temperature: false, toGo: true),
            make(.icedCappuccino, code: nil, .coldMilk, .iceGlass, [.ice, .espresso, .milk, .foam], coffee: q(20, 180, 5, 60), milk: q(5, 90, 1, 25), temperature: false, defaultAroma: .strong),
            make(.icedCappuccinoMix, code: nil, .coldMilk, .iceGlass, [.ice, .milk, .espresso, .foam], coffee: q(20, 180, 5, 60), milk: q(5, 90, 1, 25), temperature: false),
            make(.icedFlatWhite, code: nil, .coldMilk, .iceGlass, [.ice, .espresso, .milk], coffee: q(20, 180, 5, 60), milk: q(5, 90, 1, 25), temperature: false),
            make(.icedLatteMacchiato, code: nil, .coldMilk, .iceGlass, [.ice, .milk, .espresso, .foam], coffee: q(20, 180, 5, 60), milk: milkTall, temperature: false, toGo: true),
            make(.coldMilk, code: 0x0E, .coldMilk, .tallGlass, [.milk, .foam], milk: q(5, 120, 1, 30), aroma: false, temperature: false),

            // Tea and water (one machine programme, three temperatures)
            make(.hotWater, code: 0x10, .teaWater, .mug, [.water], water: q(20, 420, 10, 250), aroma: false, temperature: false, toGo: true),
            make(.greenTea, code: 0x16, .teaWater, .teaCup, [.tea], water: q(100, 420, 10, 250), aroma: false, toGo: true, defaultTemperature: .low),
            make(.blackTea, code: 0x16, .teaWater, .teaCup, [.tea], water: q(100, 420, 10, 250), aroma: false, toGo: true, defaultTemperature: .high),
            make(.herbalTea, code: 0x16, .teaWater, .teaCup, [.tea], water: q(100, 420, 10, 250), aroma: false, toGo: true, defaultTemperature: .high),
        ]
        return Dictionary(uniqueKeysWithValues: specs.map { ($0.id, $0) })
    }()
}

/// Seven collections, like the machine's "Collections" menu: drinks grouped
/// by mood and moment rather than by kind.
enum DrinkCollection: String, CaseIterable, Identifiable {
    case suggested, intense, smooth, milky, refreshing, world, toGo

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .suggested: return "sparkles"
        case .intense: return "bolt.fill"
        case .smooth: return "leaf.fill"
        case .milky: return "cloud.fill"
        case .refreshing: return "snowflake"
        case .world: return "globe.europe.africa.fill"
        case .toGo: return "takeoutbag.and.cup.and.straw.fill"
        }
    }

    /// Drinks in this collection. "Suggested" depends on the time of day.
    func beverages(hour: Int = Calendar.current.component(.hour, from: Date())) -> [BeverageID] {
        switch self {
        case .suggested:
            switch hour {
            case 5..<11: return [.espresso, .cappuccino, .coffee, .flatWhite, .latteMacchiato, .doppioPlus]
            case 11..<17: return [.icedCoffee, .coldBrew, .icedLatteMacchiato, .americano, .cortado, .espressoMacchiato]
            default: return [.herbalTea, .hotMilk, .cafeAuLait, .mildFilter, .greenTea, .babyccino]
            }
        case .intense:
            return [.ristretto, .espressoIntenso, .doppioPlus, .espressoDouble, .redEye, .blackEye, .cappuccinoPlus, .coldBrewToMix]
        case .smooth:
            return [.coffee, .espressoLungo, .americano, .mildFilter, .filterCoffee, .verlaengerter, .coffeePot]
        case .milky:
            return [.cappuccino, .caffeLatte, .latteMacchiato, .flatWhite, .cappuccinoMix, .cortado, .espressoMacchiato, .hotMilk, .babyccino]
        case .refreshing:
            return BeverageID.allCases.filter { $0.spec.isCold }
        case .world:
            return [.cafeConLeche, .galao, .milchkaffee, .koffieVerkeerd, .verlaengerter, .cafeAuLait, .cortado, .flatWhite, .redEye, .ristretto]
        case .toGo:
            return BeverageID.allCases.filter { $0.spec.supportsToGo }
        }
    }
}
