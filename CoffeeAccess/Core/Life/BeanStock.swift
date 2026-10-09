import Foundation

/// How much of a bag is left, estimated from the cups made since it was
/// opened, and what tasting says about the grind.
enum BeanStock {
    /// Grams of ground coffee for one drink. Espresso-style drinks use about
    /// 9 g per 40 ml up to a double dose; long coffees about 11 g per 180 ml.
    static func grams(for recipe: Recipe) -> Double {
        guard let coffee = recipe.coffeeML, recipe.spec.layers.contains(where: { $0 == .espresso || $0 == .coffee }) else { return 0 }
        var grams: Double
        if recipe.spec.vessel == .pot {
            grams = Double(coffee) * 0.06
        } else if recipe.spec.layers.contains(.espresso) {
            grams = min(Double(coffee) * 0.225, 18)
        } else {
            grams = min(max(Double(coffee) * 0.06, 8), 16)
        }
        if let aroma = recipe.aroma { grams *= 1 + Double(aroma.rawValue - Aroma.normal.rawValue) * 0.08 }
        if recipe.extraShot { grams += 7 }
        return grams
    }

    struct Estimate: Equatable {
        var usedGrams: Int
        var remainingGrams: Int
        /// Cups left at the person's usual dose.
        var cupsLeft: Int
        var fractionLeft: Double
        var isLow: Bool { fractionLeft < 0.15 }
    }

    /// nil when the bag weight or opening date is unknown.
    static func estimate(for bean: BeanProfile, profiles: [UserProfile]) -> Estimate? {
        guard let bag = bean.bagGrams, bag > 0, let opened = bean.openedAt else { return nil }
        let records = profiles.flatMap(\.history).filter { $0.completed && $0.date >= opened && ($0.beanID == bean.id || $0.beanID == nil) }
        let used = records.reduce(0.0) { $0 + grams(for: $1.recipe) }
        let remaining = max(0, Double(bag) - used)
        let typical = records.isEmpty ? 10 : max(6, used / Double(records.count))
        return Estimate(usedGrams: Int(used.rounded()), remainingGrams: Int(remaining.rounded()),
                        cupsLeft: Int((remaining / typical).rounded(.down)), fractionLeft: remaining / Double(bag))
    }
}

/// Bean Adapt calibration: three tasting rounds, each moving the grind,
/// temperature or strength one step toward a balanced cup.
enum Calibration {
    enum Taste: String, CaseIterable, Identifiable {
        case sour, balanced, bitter
        var id: String { rawValue }
        var title: String { L("calibration.taste.\(rawValue)") }
    }

    enum Body: String, CaseIterable, Identifiable {
        case thin, right, heavy
        var id: String { rawValue }
        var title: String { L("calibration.body.\(rawValue)") }
    }

    struct Advice: Equatable {
        var grindStep: Int        // −1 finer, +1 coarser
        var temperatureStep: Int  // −1 cooler, +1 hotter
        var strengthStep: Int     // −1 milder, +1 stronger
        var isBalanced: Bool { grindStep == 0 && temperatureStep == 0 && strengthStep == 0 }
    }

    /// Sour means under-extracted: grind finer, brew hotter. Bitter means
    /// over-extracted: grind coarser, brew cooler. Body follows strength.
    static func advice(taste: Taste, body: Body, round: Int) -> Advice {
        var advice = Advice(grindStep: 0, temperatureStep: 0, strengthStep: 0)
        switch taste {
        case .sour:
            advice.grindStep = -1
            if round >= 2 { advice.temperatureStep = 1 }
        case .bitter:
            advice.grindStep = 1
            if round >= 2 { advice.temperatureStep = -1 }
        case .balanced: break
        }
        switch body {
        case .thin: advice.strengthStep = 1
        case .heavy: advice.strengthStep = -1
        case .right: break
        }
        return advice
    }

    static func apply(_ advice: Advice, to bean: BeanProfile) -> BeanProfile {
        var copy = bean
        copy.grindOffset = max(-4, min(4, bean.grindOffset + advice.grindStep))
        if advice.temperatureStep != 0 {
            let current = bean.recommendedTemperature.rawValue + advice.temperatureStep
            copy.temperatureOverride = BrewTemperature(rawValue: max(0, min(2, current)))
        }
        copy.strengthBias = max(-2, min(2, bean.strengthBias + advice.strengthStep))
        return copy
    }

    static func sentence(_ advice: Advice, bean: BeanProfile) -> String {
        if advice.isBalanced { return L("calibration.balanced") }
        var parts: [String] = []
        if advice.grindStep < 0 { parts.append(L("calibration.grindFiner", bean.recommendedGrind + advice.grindStep)) }
        if advice.grindStep > 0 { parts.append(L("calibration.grindCoarser", bean.recommendedGrind + advice.grindStep)) }
        if advice.temperatureStep > 0 { parts.append(L("calibration.hotter")) }
        if advice.temperatureStep < 0 { parts.append(L("calibration.cooler")) }
        if advice.strengthStep > 0 { parts.append(L("calibration.stronger")) }
        if advice.strengthStep < 0 { parts.append(L("calibration.milder")) }
        return parts.joined(separator: L("sentence.separator"))
    }
}
