import Foundation

extension Recipe {
    /// Short wording for braille displays and brief speech:
    /// "Cappuccino, strong, 60 ml".
    var brief: String {
        var parts = [displayName]
        if let aroma { parts.append(aroma.title) }
        if let coffee = coffeeML { parts.append(L("unit.ml", coffee)) } else if let water = waterML { parts.append(L("unit.ml", water)) }
        if double == true { parts.append(L("double.short")) }
        if toGo { parts.append(L("summary.toGo")) }
        return parts.joined(separator: L("list.separator"))
    }

    /// Cups made at once: two from the double spout.
    var cupCount: Int { double == true ? 2 : 1 }
}

/// Will the drink fit the cup? Uses the person's own cups and their sizes.
enum CupFit {
    enum Verdict: Equatable {
        case fits(CupProfile)
        case tight(CupProfile)
        case overflows(CupProfile, suggestion: CupProfile?)
    }

    /// Volume in the cup: a double drink fills each of the two cups with half.
    static func volume(of recipe: Recipe) -> Int {
        recipe.double == true ? recipe.approximateVolumeML / 2 : recipe.approximateVolumeML
    }

    static func verdict(for recipe: Recipe, cup: CupProfile, cups: [CupProfile]) -> Verdict {
        let volume = volume(of: recipe)
        if volume > cup.capacityML {
            let better = cups.filter { $0.capacityML >= volume }.min { $0.capacityML < $1.capacityML }
            return .overflows(cup, suggestion: better)
        }
        if Double(volume) > Double(cup.capacityML) * 0.9 { return .tight(cup) }
        return .fits(cup)
    }

    /// The smallest cup the drink fits in, which is usually the one to use.
    static func bestCup(for recipe: Recipe, in cups: [CupProfile]) -> CupProfile? {
        let volume = volume(of: recipe)
        return cups.filter { $0.capacityML >= volume }.min { $0.capacityML < $1.capacityML }
    }

    static func sentence(for recipe: Recipe, cups: [CupProfile]) -> String? {
        guard !cups.isEmpty else { return nil }
        let volume = volume(of: recipe)
        if let best = bestCup(for: recipe, in: cups) {
            return L("cups.useThis", best.name, volume)
        }
        let largest = cups.max { $0.capacityML < $1.capacityML }
        return largest.map { L("cups.tooBig", volume, $0.name, $0.capacityML) }
    }
}

/// How long a drink really takes on this machine, learnt from finished cups,
/// so progress and "ready in" are right for this person's machine.
enum LearnedDuration {
    /// Same drink and roughly the same amount share what was learnt.
    static func key(for recipe: Recipe) -> String {
        let amount = (recipe.coffeeML ?? recipe.waterML ?? 0) / 20
        let milk = (recipe.milkSeconds ?? 0) / 10
        return "\(recipe.beverage.rawValue)-\(amount)-\(milk)-\(recipe.double == true ? 2 : 1)"
    }

    /// Moving average: the newest cup counts for a third.
    static func update(_ old: Double?, with seconds: Double) -> Double {
        guard seconds > 3, seconds < 900 else { return old ?? seconds }
        guard let old else { return seconds }
        return old * 2 / 3 + seconds / 3
    }

    static func expected(for recipe: Recipe, learned: [String: Double]) -> Double {
        learned[key(for: recipe)] ?? Double(recipe.estimatedSeconds)
    }
}

/// A milder version of a drink, offered when caffeine is high or it is late.
enum Lighter {
    static func alternative(to recipe: Recipe) -> Recipe? {
        var copy = recipe
        var changed = false
        if let aroma = recipe.aroma, aroma.rawValue > Aroma.extraMild.rawValue {
            copy.aroma = Aroma(rawValue: max(1, aroma.rawValue - 2))
            changed = true
        }
        if copy.extraShot { copy.extraShot = false; changed = true }
        if copy.double == true { copy.double = nil; changed = true }
        if let range = recipe.coffeeRange, let coffee = recipe.coffeeML, coffee > range.min, recipe.spec.layers.contains(.coffee) {
            copy.coffeeML = range.clamp(coffee * 2 / 3)
            changed = true
        }
        guard changed else { return nil }
        copy.id = UUID()
        copy.customName = L("lighter.name", recipe.displayName)
        return copy.normalized()
    }
}

/// "This time only" changes to the usual drink.
enum OneTimeTweak: String, CaseIterable, Identifiable {
    case stronger, milder, bigger, hotter
    var id: String { rawValue }
    var title: String { L("tweak.\(rawValue)") }

    func applied(to recipe: Recipe) -> Recipe {
        var copy = recipe
        switch self {
        case .stronger:
            if let aroma = recipe.aroma { copy.aroma = Aroma(rawValue: min(5, aroma.rawValue + 1)) }
        case .milder:
            if let aroma = recipe.aroma { copy.aroma = Aroma(rawValue: max(1, aroma.rawValue - 1)) }
        case .bigger:
            if let range = recipe.coffeeRange, let coffee = recipe.coffeeML { copy.coffeeML = range.stepped(coffee, by: 2) }
            if let range = recipe.waterRange, let water = recipe.waterML { copy.waterML = range.stepped(water, by: 2) }
            if let range = recipe.milkRange, let milk = recipe.milkSeconds { copy.milkSeconds = range.stepped(milk, by: 2) }
        case .hotter:
            if recipe.spec.hasTemperature { copy.temperature = .high }
        }
        copy.id = UUID()
        return copy.normalized()
    }

    func applies(to recipe: Recipe) -> Bool {
        switch self {
        case .stronger: return (recipe.aroma?.rawValue ?? 5) < 5
        case .milder: return (recipe.aroma?.rawValue ?? 1) > 1
        case .bigger: return recipe.coffeeRange != nil || recipe.waterRange != nil || recipe.milkRange != nil
        case .hotter: return recipe.spec.hasTemperature && recipe.temperature != .high
        }
    }
}

/// Approximate energy in a cup: almost all of it comes from the milk.
enum Nutrition {
    static func calories(for recipe: Recipe, milk: MilkType = .whole) -> Int {
        let milkML = Double(recipe.approximateMilkML)
        var kcal = milkML * milk.kcalPer100ml / 100
        if recipe.coffeeML != nil { kcal += 2 }
        if recipe.double == true { kcal *= 2 }
        return Int(kcal.rounded())
    }
}

/// "Make my coffee for now": a drink that suits the time of day.
enum DrinkForNow {
    static func recipe(for data: AppData, hour: Int, cutoffHour: Int) -> Recipe {
        let usual = Suggestions.usual(for: data)
        let late = cutoffHour >= 0 && hour >= cutoffHour
        if late {
            if let decaf = data.activeBean, decaf.decaf { return usual }
            return data.recipe(for: .herbalTea)
        }
        switch hour {
        case 5..<11: return usual
        case 11..<15: return CaffeineEstimator.milligrams(for: usual) > 120 ? (Lighter.alternative(to: usual) ?? usual) : usual
        default:
            let month = Calendar.current.component(.month, from: Date())
            return (5...9).contains(month) ? data.recipe(for: .icedCaffeLatte) : (Lighter.alternative(to: usual) ?? usual)
        }
    }
}

/// Children's profiles get no caffeine: milk, babyccino, water and herbal tea.
enum ChildSafety {
    static let allowed: Set<BeverageID> = [.hotMilk, .babyccino, .coldMilk, .hotWater, .herbalTea]

    static func isAllowed(_ recipe: Recipe) -> Bool { allowed.contains(recipe.beverage) }
}
