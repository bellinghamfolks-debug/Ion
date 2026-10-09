import CoreLocation
import XCTest
@testable import CoffeeAccess

/// Version 3: upgrades keep data, and the new logic behaves as described.
final class ProUpgradeTests: XCTestCase {
    func testVersionTwoLifeLoadsWithEmptyProData() throws {
        let json = #"{"ratings":[],"household":[],"usesWaterFilter":false,"beanSettleCups":2}"#
        let life = try JSONDecoder.coffee.decode(CoffeeLife.self, from: Data(json.utf8))
        XCTAssertFalse(life.usesWaterFilter)
        XCTAssertEqual(life.beanSettleCups, 2)
        XCTAssertEqual(life.pro, ProData())
    }

    func testProDataRoundTrips() throws {
        var pro = ProData()
        pro.cups = [CupProfile(name: "Blue mug", capacityML: 300)]
        pro.milkShelfDays = 6
        pro.waterSource = .bottled
        pro.reduction = ReductionPlan(startMg: 400, targetMg: 200, weeks: 4)
        pro.recordAlarms([.waterTankEmpty])
        pro.office.people = [OfficePerson(name: "Huda", cups: 3)]
        let decoded = try JSONDecoder.coffee.decode(ProData.self, from: JSONEncoder.coffee.encode(pro))
        XCTAssertEqual(decoded.cups.first?.capacityML, 300)
        XCTAssertEqual(decoded.milkShelfDays, 6)
        XCTAssertEqual(decoded.waterSource, .bottled)
        XCTAssertEqual(decoded.reduction?.targetMg, 200)
        XCTAssertEqual(decoded.alarmHistory.first?.alarm, .waterTankEmpty)
        XCTAssertEqual(decoded.office.people.first?.cups, 3)
    }

    func testOldBeansAndSettingsKeepDefaults() throws {
        let bean = try JSONDecoder.coffee.decode(BeanProfile.self, from: Data(#"{"name":"Kenya","roast":"dark"}"#.utf8))
        XCTAssertFalse(bean.decaf)
        XCTAssertNil(bean.price)
        XCTAssertTrue(bean.grindNotes.isEmpty)
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"hasCompletedOnboarding":true}"#.utf8))
        XCTAssertEqual(settings.verbosity, 1)
        XCTAssertTrue(settings.offlineQueue)
        XCTAssertFalse(settings.hapticOnly)
        XCTAssertEqual(settings.lastSeenVersion, "")
    }
}

final class ProBrewTests: XCTestCase {
    func testDoubleOnlyWhereSupportedAndNotToGo() {
        var espresso = Recipe.standard(.espresso)
        espresso.double = true
        XCTAssertEqual(espresso.normalized().double, true)
        XCTAssertEqual(espresso.normalized().cupCount, 2)
        var latte = Recipe.standard(.caffeLatte)
        latte.double = true
        XCTAssertNil(latte.normalized().double)
        var mug = Recipe.standard(.coffee, toGo: true)
        mug.double = true
        if mug.toGo { XCTAssertNil(mug.normalized().double) }
    }

    func testDoubleIsSentAsTwoPortions() {
        var espresso = Recipe.standard(.espresso)
        XCTAssertTrue(ECAMCommands.ingredients(for: espresso).contains(ECAMCommands.Ingredient.dueXPer.rawValue))
        espresso.double = true
        let bytes = ECAMCommands.ingredients(for: espresso)
        let index = bytes.firstIndex(of: ECAMCommands.Ingredient.dueXPer.rawValue)
        XCTAssertNotNil(index)
        if let index { XCTAssertEqual(bytes[index + 1], 1) }
    }

    func testCupFitPicksTheSmallestCupThatFits() {
        let cups = [CupProfile(name: "Small", capacityML: 90), CupProfile(name: "Mug", capacityML: 350), CupProfile(name: "Glass", capacityML: 250)]
        var latte = Recipe.standard(.caffeLatte)
        latte.coffeeML = 60
        latte.milkSeconds = 20
        XCTAssertEqual(CupFit.bestCup(for: latte, in: cups)?.name, "Glass")
        let espresso = Recipe.standard(.espresso)
        XCTAssertEqual(CupFit.bestCup(for: espresso, in: cups)?.name, "Small")
        if case .overflows(_, let suggestion) = CupFit.verdict(for: latte, cup: cups[0], cups: cups) {
            XCTAssertEqual(suggestion?.name, "Glass")
        } else {
            XCTFail("a latte should overflow a 90 ml cup")
        }
    }

    func testLearnedDurationMovesTowardsRealTimes() {
        XCTAssertEqual(LearnedDuration.update(nil, with: 40), 40)
        XCTAssertEqual(LearnedDuration.update(30, with: 60), 40, accuracy: 0.01)
        XCTAssertEqual(LearnedDuration.update(30, with: 1), 30)
        let recipe = Recipe.standard(.cappuccino)
        XCTAssertEqual(LearnedDuration.expected(for: recipe, learned: [:]), Double(recipe.estimatedSeconds))
        XCTAssertEqual(LearnedDuration.expected(for: recipe, learned: [LearnedDuration.key(for: recipe): 75]), 75)
    }

    func testSessionUsesExpectedSeconds() {
        var session = BrewSession(recipe: .standard(.coffee), startedAt: Date(timeIntervalSince1970: 0))
        var busy = MachineSnapshot()
        busy.power = .busy
        busy.activity = .brewingCoffee
        session.update(with: busy, now: Date(timeIntervalSince1970: 30), expectedSeconds: 60)
        XCTAssertEqual(session.progress, 0.5, accuracy: 0.01)
    }

    func testLighterAlternativeIsMilder() throws {
        var recipe = Recipe.standard(.coffee)
        recipe.aroma = .extraStrong
        recipe.extraShot = true
        let lighter = try XCTUnwrap(Lighter.alternative(to: recipe))
        XCTAssertLessThan(lighter.aroma!.rawValue, recipe.aroma!.rawValue)
        XCTAssertFalse(lighter.extraShot)
        XCTAssertLessThan(CaffeineEstimator.milligrams(for: lighter), CaffeineEstimator.milligrams(for: recipe))
        XCTAssertNotEqual(lighter.id, recipe.id)
    }

    func testOneTimeTweaks() {
        var recipe = Recipe.standard(.cappuccino)
        recipe.aroma = .normal
        XCTAssertEqual(OneTimeTweak.stronger.applied(to: recipe).aroma, .strong)
        XCTAssertEqual(OneTimeTweak.milder.applied(to: recipe).aroma, .mild)
        XCTAssertGreaterThanOrEqual(OneTimeTweak.bigger.applied(to: recipe).approximateVolumeML, recipe.approximateVolumeML)
        recipe.aroma = .extraStrong
        XCTAssertFalse(OneTimeTweak.stronger.applies(to: recipe))
    }

    func testCaloriesComeFromMilk() {
        let latte = Recipe.standard(.caffeLatte)
        XCTAssertGreaterThan(Nutrition.calories(for: latte, milk: .whole), Nutrition.calories(for: latte, milk: .almond))
        XCTAssertLessThanOrEqual(Nutrition.calories(for: .standard(.espresso)), 2)
    }

    func testChildrenOnlyGetCaffeineFreeDrinks() {
        XCTAssertTrue(ChildSafety.isAllowed(.standard(.babyccino)))
        XCTAssertFalse(ChildSafety.isAllowed(.standard(.cappuccino)))
    }
}

final class ProBeanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFreshnessFromRoastAndOpening() {
        var bean = BeanProfile(name: "Test")
        XCTAssertEqual(Freshness.state(of: bean, now: now), .unknown)
        bean.roastDate = now.addingTimeInterval(-2 * 86_400)
        XCTAssertEqual(Freshness.state(of: bean, now: now), .resting)
        bean.roastDate = now.addingTimeInterval(-14 * 86_400)
        XCTAssertEqual(Freshness.state(of: bean, now: now), .peak)
        bean.roastDate = now.addingTimeInterval(-120 * 86_400)
        XCTAssertEqual(Freshness.state(of: bean, now: now), .stale)
        bean.roastDate = nil
        bean.openedAt = now.addingTimeInterval(-50 * 86_400)
        XCTAssertEqual(Freshness.state(of: bean, now: now), .stale)
    }

    func testCostPerCup() throws {
        var bean = BeanProfile(name: "Test")
        XCTAssertNil(CostPerCup.beans(for: .standard(.espresso), bean: bean))
        bean.price = 50
        bean.bagGrams = 1000
        let espresso = try XCTUnwrap(CostPerCup.beans(for: .standard(.espresso), bean: bean))
        XCTAssertEqual(espresso, 0.05 * BeanStock.grams(for: .standard(.espresso)), accuracy: 0.0001)
        let latte = try XCTUnwrap(CostPerCup.total(for: .standard(.caffeLatte), bean: bean, milkPricePerLitre: 6))
        XCTAssertGreaterThan(latte, CostPerCup.beans(for: .standard(.caffeLatte), bean: bean) ?? 0)
    }

    func testGrindCoachAndNotes() {
        var bean = BeanProfile(name: "Test")
        XCTAssertEqual(GrindCoach.pendingSetting(for: bean, lastSet: [:]), bean.recommendedGrind)
        XCTAssertNil(GrindCoach.pendingSetting(for: bean, lastSet: [bean.id: bean.recommendedGrind]))
        bean.grindNotes = [GrindNote(grind: 5, rating: 5), GrindNote(grind: 7, rating: 2), GrindNote(grind: 5, rating: 4)]
        XCTAssertEqual(GrindCoach.bestFromNotes(bean.grindNotes), 5)
        XCTAssertNil(GrindCoach.bestFromNotes([GrindNote(grind: 6, rating: 5)]))
    }

    func testBarcodeMatchesAKnownBag() {
        var bean = BeanProfile(name: "Yemen")
        bean.barcode = "6281234567890"
        XCTAssertEqual(BarcodeLookup.match(" 6281234567890 ", beans: [bean])?.name, "Yemen")
        XCTAssertNil(BarcodeLookup.match("", beans: [bean]))
    }

    func testDecafAndSpilledCupsDoNotCount() {
        let decafBean = UUID()
        let day = Date()
        let normal = BrewRecord(recipe: .standard(.espresso), date: day, completed: true, beanID: nil)
        let decaf = BrewRecord(recipe: .standard(.espresso), date: day, completed: true, beanID: decafBean)
        let spilled = BrewRecord(recipe: .standard(.espresso), date: day, completed: true, beanID: nil)
        let history = [normal, decaf, spilled]
        let full = CaffeineEstimator.milligrams(for: .standard(.espresso))
        let total = CaffeineEstimator.total(on: day, in: history, spilled: [spilled.id], decafBeans: [decafBean])
        XCTAssertEqual(total, full + Int((Double(full) * CaffeineEstimator.decafFactor).rounded()))
    }
}

final class ProHostingTests: XCTestCase {
    func testGuestRepliesWithArabicAndWesternDigits() {
        XCTAssertEqual(GuestMenu.parse("1, 3 و٣", count: 9), [0, 2, 2])
        XCTAssertEqual(GuestMenu.parse("أبغى ٢ والعاشر 10", count: 9), [1])
        XCTAssertEqual(GuestMenu.parse("no numbers", count: 9), [])
    }

    func testHostingPlanCountsRefillsAndGrounds() {
        let recipes = Array(repeating: Recipe.standard(.coffee), count: 16)
        let plan = HostingPlan.make(recipes)
        XCTAssertEqual(plan.cups, 16)
        XCTAssertGreaterThan(plan.beansGrams, 100)
        XCTAssertGreaterThanOrEqual(plan.tankRefills, 1)
        XCTAssertEqual(plan.groundsEmpties, 1)
        XCTAssertFalse(plan.sentence.isEmpty)
    }

    func testQueueOrderBlackThenHotMilkThenCold() {
        let drinks: [Recipe] = [.standard(.icedCaffeLatte), .standard(.cappuccino), .standard(.espresso)]
        let ordered = QueuePlanner.ordered(drinks, recipe: { $0 })
        XCTAssertEqual(ordered.map(\.beverage), [.espresso, .cappuccino, .icedCaffeLatte])
    }

    func testWaitsGrowAndRefillIsFound() {
        let recipes = Array(repeating: Recipe.standard(.coffeePot), count: 3)
        let waits = QueuePlanner.waits(recipes, learned: [:])
        XCTAssertEqual(waits.count, 3)
        XCTAssertLessThan(waits[0], waits[2])
        XCTAssertNotNil(QueuePlanner.refillBefore(recipes, tankML: 500))
        XCTAssertNil(QueuePlanner.refillBefore([.standard(.espresso)]))
    }

    func testOfficeTally() {
        var tally = OfficeTally()
        tally.pricePerCup = 2
        tally.people = [OfficePerson(name: "A", cups: 3), OfficePerson(name: "B", cups: 1)]
        XCTAssertEqual(tally.totalCups, 4)
        XCTAssertEqual(tally.owed(by: tally.people[0]), 6)
        XCTAssertTrue(tally.text().contains("A"))
    }
}

final class ProCaffeineTests: XCTestCase {
    func testCaffeineHalvesAfterFiveHours() {
        let now = Date()
        let record = BrewRecord(recipe: .standard(.coffee), date: now.addingTimeInterval(-5 * 3600), completed: true)
        let mg = CaffeineEstimator.milligrams(for: record.recipe)
        let left = CaffeineEstimator.remaining(at: now, history: [record])
        XCTAssertEqual(Double(left), Double(mg) / 2, accuracy: 1.5)
        let below = CaffeineEstimator.time(below: left / 2, from: now, history: [record])
        XCTAssertNotNil(below)
        if let below { XCTAssertEqual(below.timeIntervalSince(now) / 3600, 5, accuracy: 0.3) }
    }

    func testReductionPlanStepsDownWeekly() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let plan = ReductionPlan(startMg: 400, targetMg: 200, weeks: 4, startDate: start)
        XCTAssertEqual(plan.limit(on: start), 350)
        XCTAssertEqual(plan.limit(on: start.addingTimeInterval(7 * 86_400 + 60)), 300)
        XCTAssertEqual(plan.limit(on: start.addingTimeInterval(40 * 86_400)), 200)
        XCTAssertTrue(plan.isFinished(on: start.addingTimeInterval(40 * 86_400)))
    }

    func testRamadanSetting() {
        XCTAssertTrue(RamadanMode.isActive(setting: 1))
        XCTAssertFalse(RamadanMode.isActive(setting: 2))
    }

    func testHourlyCounts() {
        let calendar = Calendar.current
        let eight = calendar.date(bySettingHour: 8, minute: 15, second: 0, of: Date())!
        let records = [BrewRecord(recipe: .standard(.espresso), date: eight, completed: true),
                       BrewRecord(recipe: .standard(.espresso), date: eight.addingTimeInterval(60), completed: true)]
        let hours = CaffeineEstimator.byHour(records, now: eight.addingTimeInterval(3600))
        XCTAssertEqual(hours.count, 24)
        XCTAssertEqual(hours[8], 2)
    }

    func testCSVEscapesCommasAndQuotes() {
        XCTAssertEqual(HistoryExport.escape("plain"), "plain")
        XCTAssertEqual(HistoryExport.escape("a, b"), "\"a, b\"")
        XCTAssertEqual(HistoryExport.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
        var data = AppData.initial(names: ["A", "B", "C", "D"])
        data.record(.standard(.espresso), completed: true)
        let csv = HistoryExport.csv(data: data)
        XCTAssertEqual(csv.split(separator: "\n").count, 2)
    }

    func testMonthlyReportSavings() {
        var data = AppData.initial(names: ["A", "B", "C", "D"])
        var bean = BeanProfile(name: "House")
        bean.price = 40
        bean.bagGrams = 1000
        _ = data.saveBean(bean)
        data.record(.standard(.espresso), completed: true)
        data.record(.standard(.espresso), completed: true)
        let report = MonthlyReport.make(data: data, cafePrice: 10)
        XCTAssertEqual(report.cups, 2)
        XCTAssertNotNil(report.savings)
        if let savings = report.savings { XCTAssertGreaterThan(savings, 19) }
        XCTAssertGreaterThan(report.energyKWh, 0)
    }
}

final class ProMachineTests: XCTestCase {
    func testAlarmStatsCountAndSort() {
        let now = Date()
        let events = [AlarmEvent(alarm: .waterTankEmpty, date: now), AlarmEvent(alarm: .waterTankEmpty, date: now.addingTimeInterval(-60)),
                      AlarmEvent(alarm: .beansEmpty, date: now)]
        let counts = AlarmStats.counts(events)
        XCTAssertEqual(counts.first?.alarm, .waterTankEmpty)
        XCTAssertEqual(counts.first?.count, 2)
    }

    func testServiceReportMentionsTheMachine() {
        let machine = MachineRecord(name: "Home", serial: "SN123")
        let text = ServiceReport.text(machine: machine, counters: MachineCounters(), log: [], alarms: [], appVersion: "3.0.0 (3)")
        XCTAssertTrue(text.contains("SN123"))
        XCTAssertTrue(text.contains("3.0.0"))
    }

    func testSignalStrengthWords() {
        XCTAssertEqual(SignalStrength(rssi: -50), .strong)
        XCTAssertEqual(SignalStrength(rssi: -72), .fair)
        XCTAssertEqual(SignalStrength(rssi: -90), .weak)
    }

    func testMilkAndTankFreshness() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(MilkFreshness.daysLeft(openedAt: now.addingTimeInterval(-86_400), shelfDays: 4, now: now), 3)
        XCTAssertNotNil(MilkFreshness.warning(openedAt: now.addingTimeInterval(-6 * 86_400), shelfDays: 4, now: now))
        XCTAssertNil(MilkFreshness.warning(openedAt: nil, shelfDays: 4, now: now))
        XCTAssertTrue(TankWater.isStale(filledAt: now.addingTimeInterval(-3 * 86_400), now: now))
        XCTAssertFalse(TankWater.isStale(filledAt: now.addingTimeInterval(-3600), now: now))
    }

    func testSofterWaterDelaysDescaling() {
        let history = (0..<60).map { BrewRecord(recipe: .standard(.coffee), date: Date().addingTimeInterval(-Double($0) * 40_000), completed: true) }
        let life = CoffeeLife()
        let tap = CareForecast.make(history: history, log: life, hardness: 4, usesFilter: false)
        let bottled = CareForecast.make(history: history, log: life, hardness: 4, usesFilter: false, waterFactor: WaterSource.bottled.scaleFactor)
        let tapDays = tap.items.first { $0.task == .descaling }?.daysLeft ?? 0
        let bottledDays = bottled.items.first { $0.task == .descaling }?.daysLeft ?? 0
        XCTAssertGreaterThan(bottledDays, tapDays)
    }

    func testTouchscreenSentenceFindsTheWordUnderTheFinger() {
        let words = [TouchscreenReader.Word(text: "Espresso", center: CGPoint(x: 0.2, y: 0.5)),
                     TouchscreenReader.Word(text: "Cappuccino", center: CGPoint(x: 0.6, y: 0.5))]
        let sentence = TouchscreenReader.sentence(words: words, fingertip: CGPoint(x: 0.22, y: 0.48))
        XCTAssertTrue(sentence.contains("Espresso"))
        XCTAssertTrue(sentence.contains("Cappuccino"))
    }

    func testWarrantyReminderIsAMonthBeforeTheEnd() throws {
        var machine = MachineRecord(name: "Home")
        machine.purchaseDate = Date(timeIntervalSince1970: 1_800_000_000)
        machine.warrantyYears = 2
        let reminder = try XCTUnwrap(WarrantyReminder.date(for: machine))
        let ends = try XCTUnwrap(machine.warrantyEnds)
        XCTAssertEqual(ends.timeIntervalSince(reminder) / 86_400, 30, accuracy: 1)
    }

    func testProfileNameRowsCompare() {
        let profiles = AppData.initial(names: ["Sara", "Ali", "3", "4"]).profiles
        let rows = ProfileNameCheck.rows(app: profiles, machine: [1: "sara", 2: "Omar"])
        XCTAssertTrue(rows[0].matches)
        XCTAssertFalse(rows[1].matches)
        XCTAssertTrue(rows[2].matches)
    }

    @MainActor
    func testNearestMachineWithinRadius() {
        var home = MachineRecord(name: "Home")
        home.latitude = 24.7136
        home.longitude = 46.6753
        var office = MachineRecord(name: "Office")
        office.latitude = 24.7743
        office.longitude = 46.7386
        let nearHome = CLLocation(latitude: 24.7140, longitude: 46.6755)
        XCTAssertEqual(LocationSwitcher.nearest(to: nearHome, in: [home, office])?.name, "Home")
        let farAway = CLLocation(latitude: 21.4858, longitude: 39.1925)
        XCTAssertNil(LocationSwitcher.nearest(to: farAway, in: [home, office]))
    }
}

final class ProKnowledgeTests: XCTestCase {
    func testEveryQuestionKeepsTheRightAnswerAmongChoices() {
        for lesson in AcademyLesson.allCases {
            for question in lesson.questions {
                XCTAssertEqual(Set(question.shuffled), Set(question.choices))
                XCTAssertTrue(question.shuffled.contains(question.correct))
            }
        }
    }

    func testGlobalSearchFindsDrinksAndScreens() {
        let data = AppData.initial(names: ["A", "B", "C", "D"])
        let espresso = BeverageID.espresso.name
        XCTAssertFalse(GlobalSearch.search(espresso, data: data).isEmpty)
        XCTAssertTrue(GlobalSearch.search("x", data: data).isEmpty)
    }

    func testBriefWordingIsShort() {
        var recipe = Recipe.standard(.cappuccino)
        recipe.aroma = .strong
        XCTAssertLessThan(recipe.brief.count, recipe.spokenSummary.count + 1)
        XCTAssertTrue(recipe.brief.hasPrefix(recipe.displayName))
    }
}
