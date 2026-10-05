import XCTest
@testable import CoffeeAccess

final class RecipeTests: XCTestCase {
    func testEveryBeverageHasConsistentSpec() {
        for beverage in BeverageID.allCases {
            let spec = beverage.spec
            XCTAssertEqual(spec.id, beverage)
            XCTAssertFalse(spec.layers.isEmpty, "\(beverage)")
            XCTAssertTrue(spec.coffee != nil || spec.milk != nil || spec.water != nil, "\(beverage) has no amount")
            for range in [spec.coffee, spec.milk, spec.water].compactMap({ $0 }) {
                XCTAssertLessThan(range.min, range.max, "\(beverage)")
                XCTAssertEqual(range.clamp(range.standard), range.standard, "\(beverage) standard is off the grid")
                XCTAssertFalse(range.presets.isEmpty)
            }
            let standard = Recipe.standard(beverage)
            XCTAssertEqual(standard.normalized(), standard, "\(beverage)")
            XCTAssertTrue(standard.isStandard)
            if spec.supportsToGo {
                let toGo = Recipe.standard(beverage, toGo: true)
                XCTAssertTrue(toGo.toGo)
                XCTAssertEqual(toGo.normalized(), toGo, "\(beverage) to go")
                XCTAssertGreaterThan(toGo.approximateVolumeML, standard.approximateVolumeML, "\(beverage)")
            } else {
                XCTAssertFalse(Recipe.standard(beverage, toGo: true).toGo)
            }
        }
    }

    func testCatalogMatchesTheMachineMenu() {
        XCTAssertEqual(BeverageID.allCases.count, 47)
        XCTAssertEqual(BeverageCatalog.beverages(in: .hotCoffee).count, 14)
        XCTAssertEqual(BeverageCatalog.beverages(in: .milk).count, 15)
        XCTAssertEqual(BeverageCatalog.beverages(in: .coldCoffee).count, 6)
        XCTAssertEqual(BeverageCatalog.beverages(in: .coldMilk).count, 8)
        XCTAssertEqual(BeverageCatalog.beverages(in: .teaWater).count, 4)
    }

    func testEcamCodesAreUniqueExceptTheTeaProgramme() {
        let codes = BeverageID.allCases.filter { !$0.spec.isTea }.compactMap(\.spec.ecamCode)
        XCTAssertEqual(codes.count, Set(codes).count)
        XCTAssertEqual(Set([BeverageID.greenTea, .blackTea, .herbalTea].map(\.spec.ecamCode)), [0x16])
    }

    func testCollectionsAreNonEmptyAndDistinct() {
        for collection in DrinkCollection.allCases {
            let drinks = collection.beverages(hour: 9)
            XCTAssertFalse(drinks.isEmpty, "\(collection)")
            XCTAssertEqual(drinks.count, Set(drinks).count, "\(collection) repeats a drink")
        }
        XCTAssertNotEqual(DrinkCollection.suggested.beverages(hour: 8), DrinkCollection.suggested.beverages(hour: 21))
        XCTAssertTrue(DrinkCollection.toGo.beverages().allSatisfy { $0.spec.supportsToGo })
        XCTAssertTrue(DrinkCollection.refreshing.beverages().allSatisfy { $0.spec.isCold })
    }

    func testToGoDoublesAmountsAndBack() {
        let cup = Recipe.standard(.caffeLatte)
        let mug = cup.withToGo(true)
        XCTAssertTrue(mug.toGo)
        XCTAssertEqual(mug.coffeeML, 120)
        XCTAssertEqual(mug.milkSeconds, 100)
        XCTAssertEqual(mug.withToGo(false).coffeeML, cup.coffeeML)
        XCTAssertEqual(Recipe.standard(.espresso).withToGo(true).toGo, false, "espresso has no travel size")
    }

    func testExtraShotAndFoamHint() {
        XCTAssertTrue(BeverageID.cappuccino.spec.supportsExtraShot)
        XCTAssertFalse(BeverageID.espresso.spec.supportsExtraShot)
        XCTAssertFalse(BeverageID.coldBrew.spec.supportsExtraShot)
        var cap = Recipe.standard(.cappuccino)
        cap.extraShot = true
        XCTAssertTrue(cap.normalized().extraShot)
        XCTAssertTrue(cap.normalized().spokenSummary.contains(L("summary.extraShot")))
        var esp = Recipe.standard(.espresso)
        esp.extraShot = true
        XCTAssertFalse(esp.normalized().extraShot, "espresso drops the unsupported extra shot")
        let latte = Recipe.standard(.latteMacchiato)
        XCTAssertNotNil(latte.idealFoamLevel)
        XCTAssertNil(Recipe.standard(.espresso).idealFoamLevel)
    }

    func testColdIntensityAndIceOnlyOnColdDrinks() {
        var cold = Recipe.standard(.coldBrew).normalized()
        XCTAssertEqual(cold.coldIntensity, .original)
        cold.coldIntensity = .intense
        XCTAssertEqual(cold.normalized().coldIntensity, .intense)
        let iced = Recipe.standard(.icedCappuccino).normalized()
        XCTAssertEqual(iced.iceLevel, .ice)
        XCTAssertTrue(iced.spec.supportsIce)
        var hot = Recipe.standard(.cappuccino)
        hot.coldIntensity = .intense
        hot.iceLevel = .extraIce
        XCTAssertNil(hot.normalized().coldIntensity)
        XCTAssertNil(hot.normalized().iceLevel)
    }

    func testTeaUsesWaterAndTemperatureOnly() {
        let green = Recipe.standard(.greenTea)
        XCTAssertNil(green.coffeeML)
        XCTAssertNil(green.aroma)
        XCTAssertEqual(green.temperature, .low)
        XCTAssertEqual(Recipe.standard(.blackTea).temperature, .high)
        XCTAssertTrue(green.spokenSummary.contains(BrewTemperature.low.teaTitle))
    }

    func testBeanProfileTunesDefaults() {
        var bean = BeanProfile(name: "Dark")
        bean.roast = .dark
        bean.strengthBias = 1
        let adjusted = bean.adjust(.standard(.espresso))
        XCTAssertEqual(adjusted.temperature, .low)
        XCTAssertEqual(adjusted.aroma, .strong)
        XCTAssertEqual(bean.recommendedGrind, 8)
        var light = BeanProfile(name: "Light")
        light.roast = .light
        light.kind = .arabica
        XCTAssertEqual(light.recommendedGrind, 3)
        XCTAssertEqual(light.adjust(.standard(.greenTea)).temperature, .low, "tea temperature is not changed by beans")
    }

    func testClampKeepsValuesOnTheGridAndInRange() {
        let range = QuantityRange(min: 20, max: 80, step: 5, standard: 40)
        XCTAssertEqual(range.clamp(3), 20)
        XCTAssertEqual(range.clamp(500), 80)
        XCTAssertEqual(range.clamp(42), 40)
        XCTAssertEqual(range.clamp(43), 45)
        XCTAssertEqual(range.stepped(80, by: 1), 80)
        XCTAssertEqual(range.stepped(40, by: -2), 30)
        XCTAssertEqual(range.presets, [30, 40, 60])
    }

    func testNormalizedDropsUnsupportedSettings() {
        var recipe = Recipe.standard(.espresso)
        recipe.milkSeconds = 30
        recipe.waterML = 100
        recipe.milkFirst = true
        recipe.coffeeML = 999
        recipe.customName = "  Morning  "
        let normalized = recipe.normalized()
        XCTAssertNil(normalized.milkSeconds)
        XCTAssertNil(normalized.waterML)
        XCTAssertFalse(normalized.milkFirst)
        XCTAssertEqual(normalized.coffeeML, 80)
        XCTAssertEqual(normalized.customName, "Morning")
        XCTAssertEqual(normalized.displayName, "Morning")
    }

    func testHotMilkHasNoCoffeeSettings() {
        let recipe = Recipe.standard(.hotMilk)
        XCTAssertNil(recipe.coffeeML)
        XCTAssertNil(recipe.aroma)
        XCTAssertNil(recipe.temperature)
        XCTAssertNotNil(recipe.milkSeconds)
    }

    func testSpokenSummaryNamesEverySetting() {
        var recipe = Recipe.standard(.cappuccino)
        recipe.milkFirst = true
        let summary = recipe.spokenSummary
        XCTAssertTrue(summary.contains(recipe.beverage.name))
        XCTAssertTrue(summary.contains(Aroma.normal.title))
        XCTAssertTrue(summary.contains(L("summary.milkFirst")))
        XCTAssertFalse(summary.contains("drink."), "untranslated key in \(summary)")
    }
}

final class AppDataTests: XCTestCase {
    private func makeData() -> AppData { AppData.initial(names: ["A", "B", "C", "D"]) }

    func testFavoritesAddUpdateDeduplicateAndRemove() {
        var data = makeData()
        var recipe = Recipe.standard(.cappuccino)
        recipe.customName = "Mine"
        XCTAssertTrue(data.saveFavorite(recipe))
        var copy = recipe
        copy.id = UUID()
        XCTAssertFalse(data.saveFavorite(copy), "same drink and name must not be saved twice")
        recipe.coffeeML = 80
        XCTAssertTrue(data.saveFavorite(recipe))
        XCTAssertEqual(data.activeProfile.favorites.count, 1)
        XCTAssertEqual(data.activeProfile.favorites[0].coffeeML, 80)
        data.removeFavorite(id: recipe.id)
        XCTAssertTrue(data.activeProfile.favorites.isEmpty)
    }

    func testFavoritesBelongToTheActiveProfile() {
        var data = makeData()
        data.saveFavorite(.standard(.espresso))
        data.activeProfileID = 2
        XCTAssertTrue(data.activeProfile.favorites.isEmpty)
        data.activeProfileID = 1
        XCTAssertEqual(data.activeProfile.favorites.count, 1)
    }

    func testMoveFavorite() {
        var data = makeData()
        for beverage in [BeverageID.espresso, .coffee, .cappuccino] { data.saveFavorite(.standard(beverage)) }
        data.moveFavorite(from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(data.activeProfile.favorites.map(\.beverage), [.coffee, .cappuccino, .espresso])
        data.moveFavorite(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(data.activeProfile.favorites.map(\.beverage), [.espresso, .coffee, .cappuccino])
    }

    func testPersonalDefaultReplacesStandardAndResets() {
        var data = makeData()
        var recipe = Recipe.standard(.coffee)
        recipe.aroma = .extraStrong
        data.setPersonalDefault(recipe)
        XCTAssertEqual(data.activeProfile.recipe(for: .coffee).aroma, .extraStrong)
        data.setPersonalDefault(.standard(.coffee))
        XCTAssertNil(data.activeProfile.personalDefaults[.coffee], "standard settings are not stored")
        data.setPersonalDefault(recipe)
        data.resetPersonalDefault(.coffee)
        let current = data.activeProfile.recipe(for: .coffee)
        XCTAssertEqual(current, Recipe.standard(.coffee).withID(current.id))
    }

    func testHistoryIsCappedAndFrequentCountsCompletedOnly() {
        var data = makeData()
        for index in 0..<(AppData.historyLimit + 10) { data.record(.standard(index % 3 == 0 ? .espresso : .coffee), completed: true) }
        data.record(.standard(.greenTea), completed: false)
        XCTAssertEqual(data.activeProfile.history.count, AppData.historyLimit)
        let frequent = data.frequentRecipes(limit: 3).map(\.beverage)
        XCTAssertEqual(frequent.first, .coffee)
        XCTAssertFalse(frequent.contains(.greenTea))
    }

    func testGuestModeUsesStandardDrinksAndRecordsNothing() {
        var data = makeData()
        var personal = Recipe.standard(.coffee)
        personal.aroma = .extraStrong
        data.setPersonalDefault(personal)
        data.guestMode = true
        XCTAssertEqual(data.recipe(for: .coffee).aroma, Recipe.standard(.coffee).aroma)
        data.record(.standard(.coffee), completed: true)
        XCTAssertTrue(data.activeProfile.history.isEmpty)
        data.guestMode = false
        XCTAssertEqual(data.recipe(for: .coffee).aroma, .extraStrong)
    }

    func testBeanProfilesLimitAndActiveSelection() {
        var data = makeData()
        XCTAssertFalse(data.saveBean(BeanProfile(name: "   ")))
        for index in 0..<BeanProfile.maxCount { XCTAssertTrue(data.saveBean(BeanProfile(name: "Bean \(index)"))) }
        XCTAssertFalse(data.saveBean(BeanProfile(name: "Seventh")))
        XCTAssertEqual(data.activeBean?.name, "Bean 0")
        data.removeBean(id: data.beanProfiles[0].id)
        XCTAssertEqual(data.activeBean?.name, "Bean 1")
        var dark = data.beanProfiles[0]
        dark.roast = .dark
        data.saveBean(dark)
        XCTAssertEqual(data.recipe(for: .espresso).temperature, .low)
    }

    func testStoreRoundTripsAndQuarantinesCorruptFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppDataStore(url: directory.appendingPathComponent("data.json"))
        var data = makeData()
        var recipe = Recipe.standard(.flatWhite)
        recipe.milkSeconds = 30
        data.setPersonalDefault(recipe)
        data.saveFavorite(recipe)
        data.record(recipe, completed: true, at: Date(timeIntervalSince1970: 1_800_000_000))
        try store.save(data)
        XCTAssertEqual(store.load(), data)

        try Data("not json".utf8).write(to: store.url)
        XCTAssertNil(store.load())
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(leftovers.contains { $0.contains("corrupt") }, "corrupt file must be kept aside")
    }
}

private extension Recipe {
    func withID(_ id: UUID) -> Recipe {
        var copy = self
        copy.id = id
        return copy
    }
}

final class DemoMachineTests: XCTestCase {
    func testPowerOnWarmsUpThenIsReady() {
        var engine = DemoMachineEngine()
        XCTAssertEqual(engine.snapshot.power, .off)
        XCTAssertThrowsError(try engine.brew(.standard(.espresso)))
        XCTAssertEqual(engine.powerOn(), [.phase(.heating)])
        XCTAssertEqual(engine.advance(by: 4), [])
        XCTAssertEqual(engine.advance(by: 5), [.poweredOn])
        XCTAssertEqual(engine.snapshot.power, .ready)
    }

    func testCappuccinoRunsThroughPhasesAndFinishes() throws {
        var engine = DemoMachineEngine(poweredOn: true)
        var recipe = Recipe.standard(.cappuccino)
        recipe.coffeeML = 40
        recipe.milkSeconds = 10
        XCTAssertEqual(try engine.brew(recipe), [.phase(.grinding)])
        XCTAssertEqual(engine.snapshot.power, .busy)
        var events: [DemoMachineEngine.Event] = []
        for _ in 0..<60 { events += engine.advance(by: 0.5) }
        let phases = events.compactMap { event -> MachineActivity? in
            if case .phase(let activity) = event { return activity }
            return nil
        }
        XCTAssertEqual(phases, [.brewingCoffee, .dispensingMilk])
        XCTAssertTrue(events.contains(.finished(recipe.normalized())))
        XCTAssertEqual(engine.snapshot.power, .ready)
        XCTAssertTrue(engine.snapshot.alarms.contains(.milkCarafeNeedsCleaning))
    }

    func testMilkFirstDrinkPoursMilkBeforeCoffee() throws {
        var engine = DemoMachineEngine(poweredOn: true)
        XCTAssertEqual(try engine.brew(.standard(.latteMacchiato)), [.phase(.dispensingMilk)])
    }

    func testFullGroundsContainerBlocksUntilEmptied() throws {
        var engine = DemoMachineEngine(poweredOn: true)
        for _ in 0..<(DemoMachineEngine.groundsCapacity - 3) {
            _ = try engine.brew(.standard(.espresso))
            _ = engine.advance(by: 60)
        }
        XCTAssertTrue(engine.snapshot.alarms.contains(.wasteContainerFull))
        XCTAssertThrowsError(try engine.brew(.standard(.espresso))) { error in
            XCTAssertEqual(error as? MachineError, .notReady([.wasteContainerFull]))
        }
        XCTAssertEqual(engine.emptyGrounds(), [.alarmsChanged(engine.snapshot.alarms)])
        XCTAssertFalse(engine.snapshot.alarms.contains(.wasteContainerFull))
        XCTAssertNoThrow(try engine.brew(.standard(.espresso)))
    }

    func testStopEndsTheDrinkEarly() throws {
        var engine = DemoMachineEngine(poweredOn: true)
        let recipe = Recipe.standard(.coffee)
        _ = try engine.brew(recipe)
        _ = engine.advance(by: 5)
        XCTAssertEqual(engine.stop().first, .stopped(recipe.normalized()))
        XCTAssertEqual(engine.snapshot.power, .ready)
        XCTAssertEqual(engine.stop(), [])
    }

    func testWaterRunsOutAndRefillClearsIt() throws {
        var engine = DemoMachineEngine(poweredOn: true)
        var guardCount = 0
        while !engine.snapshot.alarms.contains(.waterTankEmpty), guardCount < 40 {
            _ = engine.emptyGrounds()
            _ = engine.refillBeans()
            _ = try engine.brew(.standard(.coffee, toGo: true))
            _ = engine.advance(by: 300)
            guardCount += 1
        }
        XCTAssertTrue(engine.snapshot.alarms.contains(.waterTankEmpty))
        _ = engine.refillWater()
        XCTAssertFalse(engine.snapshot.alarms.contains(.waterTankEmpty))
        XCTAssertEqual(engine.waterLevel, 1, accuracy: 0.001)
    }
}

final class BrewSessionTests: XCTestCase {
    func testBluetoothSessionFinishesAfterBusyThenReady() {
        let start = Date()
        var session = BrewSession(recipe: .standard(.espresso), startedAt: start)
        var busy = MachineSnapshot(power: .busy, activity: .brewingCoffee)
        busy.progress = 40
        session.update(with: busy, now: start.addingTimeInterval(5))
        XCTAssertEqual(session.progress, 0.4, accuracy: 0.001)
        XCTAssertEqual(session.milestonesToAnnounce(), [25])
        XCTAssertEqual(session.milestonesToAnnounce(), [])
        session.update(with: MachineSnapshot(power: .ready), now: start.addingTimeInterval(20))
        XCTAssertEqual(session.outcome, .finished)
        XCTAssertEqual(session.progress, 1)
    }

    func testSessionFailsWhenMachineNeverStarts() {
        let start = Date()
        var session = BrewSession(recipe: .standard(.espresso), startedAt: start)
        session.update(with: MachineSnapshot(power: .ready), now: start.addingTimeInterval(5))
        XCTAssertTrue(session.isRunning)
        session.update(with: MachineSnapshot(power: .ready), now: start.addingTimeInterval(16))
        XCTAssertEqual(session.outcome, .failed(L("brew.error.didNotStart")))
    }

    func testFinishedSessionIsNotOverriddenByLaterAlarm() {
        let start = Date()
        var session = BrewSession(recipe: .standard(.espresso), startedAt: start)
        session.update(with: MachineSnapshot(power: .busy, activity: .brewingCoffee), now: start.addingTimeInterval(3))
        var ready = MachineSnapshot(power: .ready)
        ready.alarms = [.wasteContainerFull]
        session.update(with: ready, now: start.addingTimeInterval(20))
        XCTAssertEqual(session.outcome, .finished)
    }
}

final class LocalizationTests: XCTestCase {
    func testEveryEnumHasText() {
        for beverage in BeverageID.allCases {
            XCTAssertFalse(beverage.name.hasPrefix("drink."), "\(beverage)")
            XCTAssertFalse(beverage.summary.hasPrefix("drink."), "\(beverage)")
        }
        for alarm in MachineAlarm.allCases {
            XCTAssertFalse(alarm.title.hasPrefix("alarm."), "\(alarm)")
            XCTAssertFalse(alarm.advice.hasPrefix("alarm."), "\(alarm)")
        }
        for guide in MaintenanceGuideID.allCases {
            XCTAssertEqual(guide.steps.count, guide.stepCount)
            XCTAssertFalse(guide.steps.contains { $0.hasPrefix("guide.") }, "\(guide)")
        }
    }

    func testSiriDrinkListMatchesTheCatalog() {
        XCTAssertEqual(DrinkChoice.allCases.map(\.rawValue), BeverageID.allCases.map(\.rawValue))
        for collection in DrinkCollection.allCases {
            XCTAssertFalse(collection.title.hasPrefix("collection."), "\(collection)")
        }
    }

    func testFormattedStringsSubstituteArguments() {
        XCTAssertFalse(L("unit.ml", 40).contains("%"))
        XCTAssertTrue(L("unit.percent", 50).contains("50"))
        XCTAssertFalse(L("control.levelValue", "x", 2, 5).contains("%"))
    }
}

final class StatisticsTests: XCTestCase {
    func testLastDaysCountsCompletedDrinksPerDay() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let history = [
            BrewRecord(recipe: .standard(.espresso), date: now, completed: true),
            BrewRecord(recipe: .standard(.cappuccino), date: now, completed: true),
            BrewRecord(recipe: .standard(.coffee), date: yesterday, completed: true),
            BrewRecord(recipe: .standard(.coffee), date: yesterday, completed: true),
            BrewRecord(recipe: .standard(.coffee), date: yesterday, completed: false),
        ]
        let stats = DrinkStatistics(history: history)
        let days = stats.lastDays(7, now: now, calendar: calendar)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.last?.count, 2)
        XCTAssertEqual(days[5].count, 2)
        XCTAssertEqual(stats.total, 4)
        XCTAssertEqual(stats.byCategory().map(\.category), [.hotCoffee, .milk])
        XCTAssertEqual(stats.byDrink().first?.beverage, .coffee)
    }
}
