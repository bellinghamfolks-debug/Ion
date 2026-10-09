import Foundation

/// How fresh the beans are: best from about a week to a month after
/// roasting, and within about a month of opening the bag.
enum Freshness: String, Equatable {
    case resting, peak, good, fading, stale, unknown

    var title: String { L("freshness.\(rawValue)") }
    var detail: String { L("freshness.\(rawValue).detail") }

    static func state(of bean: BeanProfile, now: Date = Date(), calendar: Calendar = .current) -> Freshness {
        func days(since date: Date) -> Int { calendar.dateComponents([.day], from: date, to: now).day ?? 0 }
        let sinceRoast = bean.roastDate.map(days(since:))
        let sinceOpen = bean.openedAt.map(days(since:))
        if let sinceOpen, sinceOpen > 45 { return .stale }
        if let sinceRoast {
            switch sinceRoast {
            case ..<4: return .resting
            case 4...30: return (sinceOpen ?? 0) > 28 ? .fading : .peak
            case 31...60: return .good
            case 61...90: return .fading
            default: return .stale
            }
        }
        if let sinceOpen { return sinceOpen <= 21 ? .good : .fading }
        return .unknown
    }
}

/// What a cup costs at home, from the bag price and the milk.
enum CostPerCup {
    static func beans(for recipe: Recipe, bean: BeanProfile?) -> Double? {
        guard let bean, let price = bean.price, let grams = bean.bagGrams, grams > 0 else { return nil }
        return price / Double(grams) * BeanStock.grams(for: recipe) * Double(recipe.cupCount)
    }

    static func milk(for recipe: Recipe, pricePerLitre: Double) -> Double {
        Double(recipe.approximateMilkML * recipe.cupCount) / 1000 * pricePerLitre
    }

    static func total(for recipe: Recipe, bean: BeanProfile?, milkPricePerLitre: Double) -> Double? {
        guard let beans = beans(for: recipe, bean: bean) else { return nil }
        return beans + milk(for: recipe, pricePerLitre: milkPricePerLitre)
    }

    static func text(_ amount: Double) -> String {
        amount.formatted(.number.precision(.fractionLength(2)).locale(AppLanguage.current.locale))
    }
}

/// The grinder dial is turned by hand, and only while the grinder runs.
/// The coach says the setting to use when the bag's recommendation changed.
enum GrindCoach {
    static func pendingSetting(for bean: BeanProfile?, lastSet: [UUID: Int]) -> Int? {
        guard let bean else { return nil }
        let wanted = bean.recommendedGrind
        return lastSet[bean.id] == wanted ? nil : wanted
    }

    /// The setting the tasting notes liked best, if there are enough of them.
    static func bestFromNotes(_ notes: [GrindNote]) -> Int? {
        let grouped = Dictionary(grouping: notes, by: \.grind)
        let scored = grouped.mapValues { Double($0.map(\.rating).reduce(0, +)) / Double($0.count) }
        guard notes.count >= 2, let best = scored.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }) else { return nil }
        return best.key
    }
}

/// Two bags side by side.
struct BeanComparisonRow: Identifiable, Equatable {
    var id: String { title }
    var title: String
    var first: String
    var second: String
}

enum BeanComparison {
    static func rows(_ a: BeanProfile, _ b: BeanProfile, profiles: [UserProfile], milkPrice: Double) -> [BeanComparisonRow] {
        func cups(_ bean: BeanProfile) -> String {
            "\(profiles.flatMap(\.history).filter { $0.completed && $0.beanID == bean.id }.count)"
        }
        func cost(_ bean: BeanProfile) -> String {
            CostPerCup.beans(for: Recipe.standard(.espresso), bean: bean).map(CostPerCup.text) ?? "—"
        }
        func stars(_ bean: BeanProfile) -> String { bean.rating.map { L("stars.value", $0) } ?? "—" }
        return [
            BeanComparisonRow(title: L("beans.roast"), first: a.roast.title, second: b.roast.title),
            BeanComparisonRow(title: L("beans.kind"), first: a.kind.title, second: b.kind.title),
            BeanComparisonRow(title: L("beans.grind"), first: "\(a.recommendedGrind)", second: "\(b.recommendedGrind)"),
            BeanComparisonRow(title: L("freshness.title"), first: Freshness.state(of: a).title, second: Freshness.state(of: b).title),
            BeanComparisonRow(title: L("beans.rating"), first: stars(a), second: stars(b)),
            BeanComparisonRow(title: L("cost.espresso"), first: cost(a), second: cost(b)),
            BeanComparisonRow(title: L("compareBeans.cups"), first: cups(a), second: cups(b)),
            BeanComparisonRow(title: L("beans.decaf"), first: a.decaf ? L("action.yes") : L("action.no"), second: b.decaf ? L("action.yes") : L("action.no")),
        ]
    }
}

/// A bag recognised from its barcode, from bags bought before.
enum BarcodeLookup {
    static func match(_ code: String, beans: [BeanProfile]) -> BeanProfile? {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return beans.first { $0.barcode == trimmed }
    }
}
