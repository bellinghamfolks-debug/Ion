import XCTest
@testable import CoffeeAccess

/// Version 2: upgrades keep old data, and the estimates behave sensibly.
final class UpgradeTests: XCTestCase {
    func testVersionOneDataStillLoads() throws {
        // App data as saved by version 1: no "life", no newer bean fields.
        let json = """
        {"activeProfileID":2,"guestMode":false,"beanProfiles":[{"id":"6C1B2D2E-1A2B-4C3D-8E9F-0A1B2C3D4E5F","kind":"arabica","name":"Ethiopia","roast":"light","strengthBias":1}],
         "profiles":[{"id":1,"name":"Sara","colorIndex":0,"favorites":[],"history":[],"personalDefaults":{}},
                     {"id":2,"name":"Ali","colorIndex":1,"favorites":[],"history":[],"personalDefaults":{}},
                     {"id":3,"name":"3","colorIndex":2,"favorites":[],"history":[],"personalDefaults":{}},
                     {"id":4,"name":"4","colorIndex":3,"favorites":[],"history":[],"personalDefaults":{}}]}
        """
        let data = try JSONDecoder.coffee.decode(AppData.self, from: Data(json.utf8))
        XCTAssertEqual(data.activeProfileID, 2)
        XCTAssertEqual(data.profiles[1].name, "Ali")
        XCTAssertEqual(data.beanProfiles.first?.strengthBias, 1)
        XCTAssertEqual(data.beanProfiles.first?.grindOffset, 0)
        XCTAssertEqual(data.life, CoffeeLife())
    }

    func testVersionOneSettingsKeepTheirValues() throws {
        let json = #"{"linkKind":"bluetooth","confirmBeforeBrewing":false,"hasCompletedOnboarding":true,"haptics":false}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertTrue(settings.hasCompletedOnboarding)
        XCTAssertFalse(settings.confirmBeforeBrewing)
        XCTAssertEqual(settings.linkKind, .bluetooth)
        XCTAssertEqual(settings.caffeineLimitMg, 400)
        XCTAssertTrue(settings.preBrewReminders)
    }

    func testCutoffOffSurvivesSaving() throws {
        var settings = AppSettings()
        settings.caffeineCutoffHour = -1
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.caffeineCutoffHour, -1)
    }

    func testLifeRoundTrips() throws {
        var data = AppData.initial(names: ["a", "b", "c", "d"])
        data.life.household = [HouseholdMember(name: "Sara", recipe: .standard(.flatWhite))]
        data.life.ratings[UUID()] = DrinkRating(liked: true, strength: .stronger, note: "nice")
        data.life.log(.descaling)
        let decoded = try JSONDecoder.coffee.decode(AppData.self, from: JSONEncoder.coffee.encode(data))
        XCTAssertEqual(decoded.life.household.first?.name, "Sara")
        XCTAssertEqual(decoded.life.ratings.count, 1)
        XCTAssertNotNil(decoded.life.lastDone(.descaling))
    }

    func testHomeSectionsKeepNewOnesAndHideChosen() {
        var life = CoffeeLife()
        life.homeOrder = [.favorites, .ready]
        XCTAssertEqual(life.orderedHomeSections.prefix(2), [.favorites, .ready])
        XCTAssertEqual(Set(life.orderedHomeSections), Set(HomeSection.allCases))
        life.setHomeSection(.journey, visible: false)
        XCTAssertFalse(life.visibleHomeSections.contains(.journey))
        life.moveHomeSection(.ready, by: -1)
        XCTAssertEqual(life.orderedHomeSections.first, .ready)
    }
}

final class CaffeineTests: XCTestCase {
    func testEspressoIsAboutEightyMilligrams() {
        let mg = CaffeineEstimator.milligrams(for: .standard(.espresso))
        XCTAssertTrue((60...100).contains(mg), "\(mg)")
    }

    func testMilkAndWaterHaveNone() {
        XCTAssertEqual(CaffeineEstimator.milligrams(for: .standard(.hotMilk)), 0)
        XCTAssertEqual(CaffeineEstimator.milligrams(for: .standard(.hotWater)), 0)
        XCTAssertEqual(CaffeineEstimator.milligrams(for: .standard(.herbalTea)), 0)
    }

    func testStrongerAndExtraShotAddCaffeine() {
        var cup = Recipe.standard(.cappuccino)
        let base = CaffeineEstimator.milligrams(for: cup)
        cup.aroma = .extraStrong
        cup.extraShot = true
        XCTAssertGreaterThan(CaffeineEstimator.milligrams(for: cup), base + 50)
    }

    func testLateAndOverLimitWarnings() {
        let evening = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date())!
        let morning = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
        XCTAssertNotNil(CaffeineEstimator.warning(for: .standard(.espresso), today: 0, limit: 400, cutoffHour: 17, now: evening))
        XCTAssertNil(CaffeineEstimator.warning(for: .standard(.espresso), today: 0, limit: 400, cutoffHour: 17, now: morning))
        XCTAssertNotNil(CaffeineEstimator.warning(for: .standard(.espresso), today: 390, limit: 400, cutoffHour: -1, now: morning))
        XCTAssertNil(CaffeineEstimator.warning(for: .standard(.hotMilk), today: 900, limit: 400, cutoffHour: 17, now: evening))
    }
}

final class QueryTests: XCTestCase {
    func testColdStrongLatte() {
        let match = DrinkQuery.parse("لاتيه بارد قوي")
        XCTAssertEqual(match?.recipe.beverage, .icedCaffeLatte)
        XCTAssertEqual(match?.recipe.aroma, .strong)
    }

    func testEnglishLargeAmericanoToGo() {
        let match = DrinkQuery.parse("large americano to go")
        XCTAssertEqual(match?.recipe.beverage, .americano)
        XCTAssertEqual(match?.recipe.toGo, true)
    }

    func testArabicSpellingVariants() {
        XCTAssertEqual(DrinkQuery.parse("اسبرسو")?.recipe.beverage, .espresso)
        XCTAssertEqual(DrinkQuery.parse("كابوتشينو خفيف")?.recipe.aroma, .mild)
    }

    func testUnknownTextHasNoMatch() {
        XCTAssertNil(DrinkQuery.parse("مرحبا"))
    }
}

final class BeanTests: XCTestCase {
    func testStockFallsWithCupsSinceOpening() {
        var bean = BeanProfile(name: "Test")
        bean.bagGrams = 250
        bean.openedAt = Date().addingTimeInterval(-86_400 * 3)
        var profile = UserProfile(id: 1, name: "a", colorIndex: 0)
        for _ in 0..<10 {
            profile.history.append(BrewRecord(recipe: .standard(.espresso), date: Date(), completed: true, beanID: bean.id))
        }
        let estimate = BeanStock.estimate(for: bean, profiles: [profile])
        XCTAssertNotNil(estimate)
        XCTAssertLessThan(estimate!.remainingGrams, 250)
        XCTAssertGreaterThan(estimate!.cupsLeft, 0)
        XCTAssertNil(BeanStock.estimate(for: BeanProfile(name: "x"), profiles: [profile]))
    }

    func testCalibrationMovesTheRightWay() {
        let sour = Calibration.advice(taste: .sour, body: .right, round: 1)
        XCTAssertEqual(sour.grindStep, -1)
        let bitter = Calibration.advice(taste: .bitter, body: .thin, round: 2)
        XCTAssertEqual(bitter.grindStep, 1)
        XCTAssertEqual(bitter.temperatureStep, -1)
        XCTAssertEqual(bitter.strengthStep, 1)
        XCTAssertTrue(Calibration.advice(taste: .balanced, body: .right, round: 1).isBalanced)
        let bean = Calibration.apply(sour, to: BeanProfile(name: "x", roast: .medium))
        XCTAssertEqual(bean.recommendedGrind, bean.baseGrind - 1)
    }

    func testBagReaderFindsRoastOriginAndWeight() {
        let reading = BagReader.read(["Sunrise Blend", "Ethiopia Yirgacheffe", "Light roast", "100% Arabica", "250 g"])
        XCTAssertEqual(reading.roast, .light)
        XCTAssertEqual(reading.origin, .ethiopia)
        XCTAssertEqual(reading.kind, .arabica)
        XCTAssertEqual(reading.grams, 250)
        XCTAssertEqual(reading.name, "Sunrise Blend")
    }
}

final class CareTests: XCTestCase {
    func testHarderWaterMeansSoonerDescaling() {
        let history = (0..<40).map { day in
            BrewRecord(recipe: .standard(.coffee), date: Date().addingTimeInterval(-Double(day) * 43_200), completed: true)
        }
        var life = CoffeeLife()
        life.log(.descaling, at: Date().addingTimeInterval(-86_400 * 10))
        let soft = CareForecast.make(history: history, log: life, hardness: 1, usesFilter: false)
        let hard = CareForecast.make(history: history, log: life, hardness: 4, usesFilter: false)
        let softDays = soft.items.first { $0.task == .descaling }!.daysLeft
        let hardDays = hard.items.first { $0.task == .descaling }!.daysLeft
        XCTAssertLessThan(hardDays, softDays)
    }

    func testBrewingUnitIsWeekly() {
        var life = CoffeeLife()
        life.log(.brewingUnit, at: Date().addingTimeInterval(-86_400 * 2))
        let forecast = CareForecast.make(history: [], log: life, hardness: 3, usesFilter: true)
        XCTAssertEqual(forecast.items.first { $0.task == .brewingUnit }?.daysLeft, 5)
    }

    func testHardnessStripMapsToLevels() {
        XCTAssertEqual(HardnessTestView.level(forRedSquares: 0), 1)
        XCTAssertEqual(HardnessTestView.level(forRedSquares: 3), 3)
        XCTAssertEqual(HardnessTestView.level(forRedSquares: 4), 4)
    }
}

final class RecipeLifeTests: XCTestCase {
    func testSharedRecipeRoundTrips() {
        var recipe = Recipe.standard(.flatWhite)
        recipe.aroma = .strong
        recipe.customName = "صباحي"
        let url = RecipeShare.url(for: recipe)!
        let back = RecipeShare.recipe(from: url)!
        XCTAssertEqual(back.beverage, .flatWhite)
        XCTAssertEqual(back.aroma, .strong)
        XCTAssertEqual(back.customName, "صباحي")
        XCTAssertNil(RecipeShare.recipe(from: URL(string: "coffeeaccess://recipe?d=garbage")!))
    }

    func testSignatureRecipesAreComplete() {
        for id in SignatureRecipeID.allCases {
            XCTAssertFalse(id.title.hasPrefix("signature."), "\(id)")
            XCTAssertEqual(id.ingredients.count, id.spec.ingredients, "\(id)")
            XCTAssertEqual(id.recipe.beverage, id.spec.base)
            XCTAssertTrue(id.afterSteps.allSatisfy { !$0.hasPrefix("signature.") })
        }
    }

    func testRamadanIsDetected() {
        // 1 Ramadan 1448 AH ≈ 8 February 2027.
        let ramadan = DateComponents(calendar: Calendar(identifier: .islamicUmmAlQura), year: 1448, month: 9, day: 10).date!
        XCTAssertTrue(Season.current(on: ramadan).contains(.ramadan))
        XCTAssertFalse(SignatureSpec.seasonal(on: ramadan).isEmpty)
    }

    func testDrinkOfTheDayIsStableForTheDay() {
        let morning = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
        let later = morning.addingTimeInterval(600)
        XCTAssertEqual(Suggestions.drinkOfTheDay(date: morning, history: []), Suggestions.drinkOfTheDay(date: later, history: []))
    }

    func testCloseToTasteSkipsTriedDrinks() {
        let history = [BrewRecord(recipe: .standard(.cappuccino), date: Date(), completed: true),
                       BrewRecord(recipe: .standard(.caffeLatte), date: Date(), completed: true)]
        let picks = Suggestions.closeToTaste(history: history, favorites: [])
        XCTAssertFalse(picks.contains(.cappuccino))
        XCTAssertTrue(picks.allSatisfy { $0.spec.usesMilk })
    }

    func testGoalsAndWeeklySummary() {
        let today = Date()
        let history = (0..<7).map { BrewRecord(recipe: .standard(.espresso), date: today.addingTimeInterval(-Double($0) * 86_400), completed: true) }
        XCTAssertEqual(Goal.streak7.progress(history: history, favorites: [], life: CoffeeLife(), now: today), 7)
        let summary = WeeklySummary.make(history: history, now: today.addingTimeInterval(60))
        XCTAssertEqual(summary.topDrink, .espresso)
        XCTAssertGreaterThan(summary.cups, 5)
    }

    func testKnowledgeRatio() {
        XCTAssertNotNil(DrinkKnowledge.ratio(.standard(.caffeLatte)))
        XCTAssertNil(DrinkKnowledge.ratio(.standard(.espresso)))
    }
}
