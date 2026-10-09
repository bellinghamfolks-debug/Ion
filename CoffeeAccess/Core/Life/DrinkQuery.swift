import Foundation

/// Understands a spoken or typed order such as "لاتيه بارد قوي" or
/// "large americano to go" and turns it into a recipe.
enum DrinkQuery {
    struct Match: Equatable {
        var recipe: Recipe
        /// What was understood besides the drink, for the spoken summary.
        var understood: [String]
    }

    /// Everyday names people use that differ from the menu.
    static let synonyms: [BeverageID: [String]] = [
        .caffeLatte: ["لاتيه", "لاتي", "latte"],
        .latteMacchiato: ["ماكياتو لاتيه"],
        .americano: ["قهوه امريكيه", "امريكان"],
        .coffee: ["قهوه عاديه", "regular coffee"],
        .espresso: ["اسبرسو", "اكسبريسو"],
        .icedCaffeLatte: ["ايس لاتيه", "لاتيه مثلج", "iced latte"],
        .icedCoffee: ["ايس كوفي", "قهوه بارده"],
        .icedAmericano: ["ايس امريكانو"],
        .hotWater: ["موية حاره", "ماء حار", "water"],
        .greenTea: ["شاي اخضر"],
        .blackTea: ["شاي", "tea"],
        .coldBrew: ["كولدبرو"],
        .flatWhite: ["فلات"],
        .cappuccino: ["كابتشينو", "كابيتشينو", "كابوتشينو"],
    ]

    /// The iced counterpart of a hot drink, for "cold" in the order.
    static let icedVersion: [BeverageID: BeverageID] = [
        .caffeLatte: .icedCaffeLatte, .cappuccino: .icedCappuccino, .cappuccinoMix: .icedCappuccinoMix,
        .americano: .icedAmericano, .espresso: .icedEspresso, .coffee: .icedCoffee,
        .flatWhite: .icedFlatWhite, .latteMacchiato: .icedLatteMacchiato, .hotMilk: .coldMilk,
    ]

    static func parse(_ text: String, base: (BeverageID) -> Recipe = { Recipe.standard($0) }) -> Match? {
        let query = normalize(text)
        guard !query.isEmpty else { return nil }
        var best: (BeverageID, Int)?
        for beverage in BeverageID.allCases {
            for name in names(for: beverage) where !name.isEmpty && contains(query, name) {
                if best == nil || name.count > best!.1 { best = (beverage, name.count) }
            }
        }
        guard var beverage = best?.0 else { return nil }
        var understood: [String] = []

        if hasAny(query, ["بارد", "مثلج", "ايس", "iced", "cold"]), !beverage.spec.isCold, let iced = icedVersion[beverage] {
            beverage = iced
            understood.append(L("query.cold"))
        }
        var recipe = base(beverage)
        if recipe.spec.hasAroma {
            if hasAny(query, ["قوي جدا", "extra strong", "very strong"]) {
                recipe.aroma = .extraStrong; understood.append(Aroma.extraStrong.title)
            } else if hasAny(query, ["خفيف جدا", "extra mild", "very mild"]) {
                recipe.aroma = .extraMild; understood.append(Aroma.extraMild.title)
            } else if hasAny(query, ["قوي", "ثقيل", "strong"]) {
                recipe.aroma = .strong; understood.append(Aroma.strong.title)
            } else if hasAny(query, ["خفيف", "mild", "light"]) {
                recipe.aroma = .mild; understood.append(Aroma.mild.title)
            }
        }
        if hasAny(query, ["سفري", "للطريق", "to go", "travel"]), recipe.spec.supportsToGo {
            recipe = recipe.withToGo(true); understood.append(L("summary.toGo"))
        }
        if hasAny(query, ["كبير", "large", "big"]) {
            scale(&recipe, toLarge: true); understood.append(L("preset.large"))
        } else if hasAny(query, ["صغير", "small"]) {
            scale(&recipe, toLarge: false); understood.append(L("preset.small"))
        }
        if hasAny(query, ["شوت اضافي", "شوت زياده", "extra shot"]), recipe.spec.supportsExtraShot {
            recipe.extraShot = true; understood.append(L("summary.extraShot"))
        }
        if hasAny(query, ["الحليب اولا", "حليب اولا", "milk first"]), recipe.spec.supportsMilkFirst {
            recipe.milkFirst = true; understood.append(L("summary.milkFirst"))
        }
        return Match(recipe: recipe.normalized(), understood: understood)
    }

    private static func scale(_ recipe: inout Recipe, toLarge: Bool) {
        if let range = recipe.coffeeRange, range.presets.count > 1 {
            recipe.coffeeML = toLarge ? range.presets.last : range.presets.first
        } else if let range = recipe.waterRange {
            recipe.waterML = toLarge ? range.presets.last : range.presets.first
        }
        if let range = recipe.milkRange {
            recipe.milkSeconds = toLarge ? range.presets.last : range.presets.first
        }
    }

    static func names(for beverage: BeverageID) -> [String] {
        let key = "drink.\(beverage.rawValue).name"
        var names: [String] = []
        if let entry = Strings.table[key] { names += [entry.ar, entry.en] }
        names += synonyms[beverage] ?? []
        return names.map(normalize)
    }

    /// Lower-case, no diacritics, one form of alef, ta marbuta and ya.
    static func normalize(_ text: String) -> String {
        var value = text.lowercased()
        let replacements: [(String, String)] = [
            ("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ٱ", "ا"), ("ة", "ه"), ("ى", "ي"), ("ؤ", "و"), ("ئ", "ي"), ("ـ", ""),
        ]
        for (from, to) in replacements { value = value.replacingOccurrences(of: from, with: to) }
        value = String(value.unicodeScalars.filter { !(0x064B...0x0652).contains($0.value) }.map(Character.init))
        value = value.replacingOccurrences(of: "[^\\p{L}\\p{N} ]", with: " ", options: .regularExpression)
        return value.split(separator: " ").joined(separator: " ")
    }

    private static func contains(_ query: String, _ phrase: String) -> Bool {
        (" " + query + " ").contains(" " + phrase + " ")
            || (phrase.count >= 5 && query.contains(phrase))
    }

    private static func hasAny(_ query: String, _ phrases: [String]) -> Bool {
        phrases.map(normalize).contains { contains(query, $0) }
    }
}
