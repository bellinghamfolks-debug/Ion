import Foundation

/// Recipes from around the world that need one or two things the machine
/// cannot add: the machine makes its part, and the app reads the steps
/// before and after. Some belong to a season and appear on the home screen
/// only then.
enum SignatureRecipeID: String, CaseIterable, Identifiable, Codable {
    case affogato, espressoTonic, spanishLatte, cardamomLatte, mocha, vietnameseIced
    case shakerato, cafeBombon, honeyCinnamonLatte, saffronCappuccino, icedDateLatte, orangeEspresso

    var id: String { rawValue }
    var title: String { L("signature.\(rawValue).title") }
    var summary: String { L("signature.\(rawValue).summary") }
    var spec: SignatureSpec { SignatureSpec.table(self) }

    var ingredients: [String] { (1...max(1, spec.ingredients)).map { L("signature.\(rawValue).ingredient.\($0)") } }
    var beforeSteps: [String] { spec.before == 0 ? [] : (1...spec.before).map { L("signature.\(rawValue).before.\($0)") } }
    var afterSteps: [String] { spec.after == 0 ? [] : (1...spec.after).map { L("signature.\(rawValue).after.\($0)") } }

    /// The machine part of the recipe.
    var recipe: Recipe {
        var recipe = Recipe.standard(spec.base)
        if let aroma = spec.aroma, recipe.spec.hasAroma { recipe.aroma = aroma }
        recipe.customName = title
        return recipe.normalized()
    }
}

enum Season: String, CaseIterable {
    case winter, summer, ramadan

    /// Seasons in effect on a date. Ramadan follows the Umm al-Qura calendar.
    static func current(on date: Date = Date()) -> Set<Season> {
        var seasons: Set<Season> = []
        let month = Calendar(identifier: .gregorian).component(.month, from: date)
        if [11, 12, 1, 2].contains(month) { seasons.insert(.winter) }
        if [6, 7, 8].contains(month) { seasons.insert(.summer) }
        if Calendar(identifier: .islamicUmmAlQura).component(.month, from: date) == 9 { seasons.insert(.ramadan) }
        return seasons
    }

    var title: String { L("season.\(rawValue)") }
}

struct SignatureSpec {
    let base: BeverageID
    let aroma: Aroma?
    /// Counts of the texts in the strings table (checked by the validator).
    let ingredients: Int
    let before: Int
    let after: Int
    let seasons: Set<Season>

    // swiftlint:disable:next cyclomatic_complexity
    static func table(_ id: SignatureRecipeID) -> SignatureSpec {
        switch id {
        case .affogato: return SignatureSpec(base: .espresso, aroma: .strong, ingredients: 2, before: 2, after: 1, seasons: [.summer])
        case .espressoTonic: return SignatureSpec(base: .espresso, aroma: .normal, ingredients: 3, before: 2, after: 2, seasons: [.summer])
        case .spanishLatte: return SignatureSpec(base: .caffeLatte, aroma: .strong, ingredients: 1, before: 1, after: 1, seasons: [])
        case .cardamomLatte: return SignatureSpec(base: .caffeLatte, aroma: .normal, ingredients: 2, before: 1, after: 1, seasons: [.winter, .ramadan])
        case .mocha: return SignatureSpec(base: .cappuccino, aroma: .strong, ingredients: 2, before: 1, after: 2, seasons: [.winter])
        case .vietnameseIced: return SignatureSpec(base: .icedCoffee, aroma: .extraStrong, ingredients: 2, before: 2, after: 1, seasons: [.summer])
        case .shakerato: return SignatureSpec(base: .espressoDouble, aroma: .strong, ingredients: 3, before: 1, after: 3, seasons: [.summer])
        case .cafeBombon: return SignatureSpec(base: .espresso, aroma: .strong, ingredients: 1, before: 2, after: 1, seasons: [])
        case .honeyCinnamonLatte: return SignatureSpec(base: .caffeLatte, aroma: .mild, ingredients: 2, before: 1, after: 2, seasons: [.winter])
        case .saffronCappuccino: return SignatureSpec(base: .cappuccino, aroma: .mild, ingredients: 2, before: 2, after: 1, seasons: [.ramadan, .winter])
        case .icedDateLatte: return SignatureSpec(base: .icedCaffeLatte, aroma: .normal, ingredients: 2, before: 2, after: 1, seasons: [.ramadan, .summer])
        case .orangeEspresso: return SignatureSpec(base: .icedEspresso, aroma: .normal, ingredients: 2, before: 2, after: 1, seasons: [.summer])
        }
    }

    static func seasonal(on date: Date = Date()) -> [SignatureRecipeID] {
        let now = Season.current(on: date)
        return SignatureRecipeID.allCases.filter { !$0.spec.seasons.isDisjoint(with: now) }
    }
}
