import AppIntents
import Foundation

/// Drinks as a Siri / Shortcuts parameter.
enum DrinkChoice: String, AppEnum {
    case espresso, ristretto, espressoDouble, doppioPlus, coffee, longCoffee
    case americano, longBlack, travelMug
    case cappuccino, cappuccinoPlus, cappuccinoMix, latteMacchiato, caffeLatte
    case flatWhite, espressoMacchiato, cortado, hotMilk
    case overIce, icedCappuccino, icedLatteMacchiato, coldMilk
    case hotWater, tea

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Drink"

    static var caseDisplayRepresentations: [DrinkChoice: DisplayRepresentation] = [
        .espresso: "إسبريسو", .ristretto: "ريستريتو", .espressoDouble: "إسبريسو مزدوج", .doppioPlus: "دوبيو بلس",
        .coffee: "قهوة", .longCoffee: "قهوة طويلة", .americano: "أمريكانو", .longBlack: "لونغ بلاك",
        .travelMug: "كوب السفر", .cappuccino: "كابتشينو", .cappuccinoPlus: "كابتشينو بلس",
        .cappuccinoMix: "كابتشينو ميكس", .latteMacchiato: "لاتيه ماكياتو", .caffeLatte: "كافيه لاتيه",
        .flatWhite: "فلات وايت", .espressoMacchiato: "إسبريسو ماكياتو", .cortado: "كورتادو",
        .hotMilk: "حليب ساخن", .overIce: "قهوة على الثلج", .icedCappuccino: "كابتشينو مثلج",
        .icedLatteMacchiato: "لاتيه ماكياتو مثلج", .coldMilk: "حليب بارد", .hotWater: "ماء ساخن", .tea: "شاي",
    ]

    var beverage: BeverageID { BeverageID(rawValue: rawValue) ?? .coffee }
}

enum StrengthChoice: Int, AppEnum {
    case extraMild = 1, mild, normal, strong, extraStrong

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Strength"
    static var caseDisplayRepresentations: [StrengthChoice: DisplayRepresentation] = [
        .extraMild: "خفيفة جدًا", .mild: "خفيفة", .normal: "متوسطة", .strong: "قوية", .extraStrong: "قوية جدًا",
    ]
}

struct BrewDrinkIntent: AppIntent {
    static var title: LocalizedStringResource = "Make a drink"
    static var description = IntentDescription("Prepares a drink with your saved settings, or with the strength and amount you say.")
    static var openAppWhenRun = true

    @Parameter(title: "Drink") var drink: DrinkChoice
    @Parameter(title: "Strength") var strength: StrengthChoice?
    @Parameter(title: "Coffee (ml)") var coffeeML: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Make \(\.$drink)") {
            \.$strength
            \.$coffeeML
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        model.start()
        var recipe = model.activeProfile.recipe(for: drink.beverage)
        if let strength, recipe.spec.hasAroma { recipe.aroma = Aroma(rawValue: strength.rawValue) }
        if let coffeeML, recipe.spec.coffee != nil { recipe.coffeeML = coffeeML }
        recipe = recipe.normalized()
        try await IntentSupport.waitForConnection(model)
        let started = await model.brew(recipe)
        let text = started ? L("intent.brewing", recipe.spokenSummary) : (model.lastMessage ?? L("intent.failed"))
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct BrewFavoriteIntent: AppIntent {
    static var title: LocalizedStringResource = "Make my favorite"
    static var description = IntentDescription("Prepares the first favorite of the active profile.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        model.start()
        guard let favorite = model.activeProfile.favorites.first else {
            return .result(dialog: IntentDialog(stringLiteral: L("intent.noFavorite")))
        }
        try await IntentSupport.waitForConnection(model)
        let started = await model.brew(favorite)
        let text = started ? L("intent.brewing", favorite.spokenSummary) : (model.lastMessage ?? L("intent.failed"))
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct MachineStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Machine status"
    static var description = IntentDescription("Says whether the machine is ready and lists any alerts.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        model.start()
        try? await IntentSupport.waitForConnection(model)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let text = model.connection.isConnected ? model.snapshot.spokenStatus : model.connection.title
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct TurnOnMachineIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn on the machine"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        model.start()
        try await IntentSupport.waitForConnection(model)
        await model.powerOn()
        return .result(dialog: IntentDialog(stringLiteral: L("announce.turningOn")))
    }
}

enum IntentSupport {
    struct NotConnected: Error, CustomLocalizedStringResourceConvertible {
        var localizedStringResource: LocalizedStringResource { "The machine is not connected." }
    }

    @MainActor
    static func waitForConnection(_ model: AppModel, seconds: Double = 12) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !model.connection.isConnected {
            if Date() > deadline { throw NotConnected() }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        // Give the first status poll a moment to arrive.
        if model.snapshot.power == .unknown { try? await Task.sleep(nanoseconds: 1_200_000_000) }
    }
}

struct CoffeeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: BrewDrinkIntent(),
            phrases: [
                "حضّر \(\.$drink) في \(.applicationName)",
                "اعمل \(\.$drink) في \(.applicationName)",
                "Make \(\.$drink) with \(.applicationName)",
            ],
            shortTitle: "Make a drink",
            systemImageName: "cup.and.saucer.fill"
        )
        AppShortcut(
            intent: BrewFavoriteIntent(),
            phrases: [
                "حضّر مشروبي المفضل في \(.applicationName)",
                "Make my favorite with \(.applicationName)",
            ],
            shortTitle: "My favorite",
            systemImageName: "star.fill"
        )
        AppShortcut(
            intent: MachineStatusIntent(),
            phrases: [
                "حالة الماكينة في \(.applicationName)",
                "What is the machine status in \(.applicationName)",
            ],
            shortTitle: "Machine status",
            systemImageName: "gauge.with.dots.needle.67percent"
        )
        AppShortcut(
            intent: TurnOnMachineIntent(),
            phrases: [
                "شغّل الماكينة في \(.applicationName)",
                "Turn on the machine with \(.applicationName)",
            ],
            shortTitle: "Turn on",
            systemImageName: "power"
        )
    }
}
