import Foundation

/// A numbered drinks menu to send guests (WhatsApp or any app), and their
/// replies ("1, 3, 3" or "١ و٣") read back into the order queue.
enum GuestMenu {
    static func choices(favorites: [Recipe], data: AppData) -> [Recipe] {
        var list: [Recipe] = []
        for favorite in favorites.prefix(4) where !list.contains(where: { $0.beverage == favorite.beverage && $0.customName == favorite.customName }) {
            list.append(favorite)
        }
        let popular: [BeverageID] = [.espresso, .cappuccino, .caffeLatte, .flatWhite, .americano, .latteMacchiato, .icedCaffeLatte, .hotMilk, .herbalTea]
        for beverage in popular where list.count < 9 && !list.contains(where: { $0.beverage == beverage && $0.customName.isEmpty }) {
            list.append(data.recipe(for: beverage))
        }
        return list
    }

    static func text(_ choices: [Recipe], host: String) -> String {
        var lines = [L("guestMenu.header", host), ""]
        for (index, recipe) in choices.enumerated() { lines.append("\(index + 1). \(recipe.displayName)") }
        lines.append("")
        lines.append(L("guestMenu.footer"))
        return lines.joined(separator: "\n")
    }

    /// Every number in a reply, Arabic or Western digits, as menu indexes.
    static func parse(_ reply: String, count: Int) -> [Int] {
        var numbers: [Int] = []
        var current = ""
        func flush() {
            if let value = Int(current), value >= 1, value <= count { numbers.append(value - 1) }
            current = ""
        }
        for character in reply {
            if let digit = character.wholeNumberValue, character.isNumber {
                current.append(String(digit))
            } else {
                flush()
            }
        }
        flush()
        return numbers
    }
}

/// What a gathering needs: beans, milk, water, time and refills.
struct HostingPlan: Equatable {
    var cups: Int
    var beansGrams: Int
    var milkML: Int
    var waterML: Int
    var minutes: Int
    var tankRefills: Int
    var groundsEmpties: Int

    /// The Eletta's tank holds about 2 litres; about 1.9 are usable.
    static let tankML = 1_900
    /// The grounds container holds about 14 portions.
    static let groundsPortions = 14

    static func make(_ recipes: [Recipe], learned: [String: Double] = [:]) -> HostingPlan {
        let cups = recipes.reduce(0) { $0 + $1.cupCount }
        let beans = recipes.reduce(0.0) { $0 + BeanStock.grams(for: $1) * Double($1.cupCount) }
        let milk = recipes.reduce(0) { $0 + $1.approximateMilkML * $1.cupCount }
        let water = recipes.reduce(0) { $0 + QueuePlanner.water(for: $1) }
        let seconds = recipes.reduce(0.0) { $0 + LearnedDuration.expected(for: $1, learned: learned) + QueuePlanner.handlingSeconds }
        let portions = recipes.filter { $0.coffeeML != nil }.reduce(0) { $0 + $1.cupCount }
        return HostingPlan(cups: cups, beansGrams: Int(beans.rounded()), milkML: milk, waterML: water,
                           minutes: Int((seconds / 60).rounded(.up)), tankRefills: max(0, (water - 1) / tankML),
                           groundsEmpties: max(0, (portions - 1) / groundsPortions))
    }

    var sentence: String {
        var parts = [L("hosting.summary", cups, beansGrams, minutes)]
        if milkML > 0 { parts.append(L("hosting.milk", milkML)) }
        parts.append(tankRefills == 0 ? L("hosting.tankOK") : L("hosting.tankRefills", tankRefills))
        if groundsEmpties > 0 { parts.append(L("hosting.grounds", groundsEmpties)) }
        return parts.joined(separator: L("sentence.separator"))
    }
}

/// The order and timing of a queue of drinks.
enum QueuePlanner {
    /// Swapping cups and the carafe between drinks.
    static let handlingSeconds = 15.0

    static func water(for recipe: Recipe) -> Int {
        ((recipe.coffeeML ?? 0) + (recipe.waterML ?? 0) + 20) * recipe.cupCount
    }

    /// Black hot drinks first, then hot milk drinks, then cold milk drinks:
    /// the carafe is fitted once and hot milk is not followed by cold rinsing.
    static func rank(_ recipe: Recipe) -> Int {
        let spec = recipe.spec
        if !spec.usesMilk { return spec.isCold ? 1 : 0 }
        return spec.isCold ? 3 : 2
    }

    static func ordered<T>(_ items: [T], recipe: (T) -> Recipe) -> [T] {
        items.enumerated().sorted { a, b in
            let ra = rank(recipe(a.element)), rb = rank(recipe(b.element))
            return ra == rb ? a.offset < b.offset : ra < rb
        }.map(\.element)
    }

    /// Seconds until each drink is ready, if each starts right after the last.
    static func waits(_ recipes: [Recipe], learned: [String: Double]) -> [Int] {
        var total = 0.0
        return recipes.map { recipe in
            total += LearnedDuration.expected(for: recipe, learned: learned) + handlingSeconds
            return Int(total)
        }
    }

    /// The drink before which the tank needs refilling, if any (1-based).
    static func refillBefore(_ recipes: [Recipe], tankML: Int = HostingPlan.tankML) -> Int? {
        var used = 0
        for (index, recipe) in recipes.enumerated() {
            used += water(for: recipe)
            if used > tankML { return index + 1 }
        }
        return nil
    }
}

extension OfficeTally {
    var totalCups: Int { people.reduce(0) { $0 + $1.cups } }

    func owed(by person: OfficePerson) -> Double { Double(person.cups) * pricePerCup }

    func text() -> String {
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(AppLanguage.current.locale)
        var lines = [since.map { L("office.share.header", $0.formatted(style)) } ?? L("office.share.headerAll")]
        for person in people.sorted(by: { $0.cups > $1.cups }) {
            lines.append(L("office.share.line", person.name, person.cups, CostPerCup.text(owed(by: person))))
        }
        lines.append(L("office.share.total", totalCups, CostPerCup.text(Double(totalCups) * pricePerCup)))
        return lines.joined(separator: "\n")
    }
}
