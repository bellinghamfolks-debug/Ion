import Foundation

/// Everything version 3 remembers: cups, favorite tags and versions, milk,
/// combos, learned brewing times, purchases, supplies, alarm history, the
/// household's cups, the office tally, a caffeine plan and lessons. Saved
/// inside CoffeeLife; every field reads safely when absent.
struct ProData: Codable, Equatable {
    var cups: [CupProfile] = []
    var favoriteTags: [UUID: [String]] = [:]
    var recipeVersions: [UUID: [RecipeVersion]] = [:]
    /// Milk per favorite, and a default per profile.
    var milkTypes: [UUID: MilkType] = [:]
    var profileMilk: [Int: MilkType] = [:]
    /// "Add a spoon of sugar" kept with a favorite and said after brewing.
    var additions: [UUID: String] = [:]
    var combos: [DrinkCombo] = []
    /// Seconds a drink really took on this machine, keyed by LearnedDuration.key.
    var learnedSeconds: [String: Double] = [:]
    /// A drink asked for while the machine was not connected.
    var queuedBrew: Recipe?
    /// A drink stopped by an alarm (no water, no beans), offered again once it clears.
    var resumeRecipe: Recipe?
    var purchases: [BeanPurchase] = []
    var waterSource: WaterSource = .tap
    var supplies = Supplies()
    var alarmHistory: [AlarmEvent] = []
    var milkOpenedAt: Date?
    var milkShelfDays = 4
    var tankFilledAt: Date?
    /// Profiles that belong to children: no caffeine.
    var childProfiles: [Int] = []
    var memberCups: [MemberCup] = []
    var office = OfficeTally()
    var reduction: ReductionPlan?
    /// The grind each bag was last set to, so the coach only speaks on a change.
    var lastGrindSet: [UUID: Int] = [:]
    /// Cups recorded but spilled or not drunk: kept, but not counted as caffeine.
    var spilled: [UUID] = []
    var lessonsDone: [String] = []
    var quizBest = 0
    var lastClockSync: Date?
    var electricityPrice: Double = 0.18
    var milkPricePerLitre: Double = 6
    var warrantyNotified: [UUID] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        cups = read(.cups, [])
        favoriteTags = read(.favoriteTags, [:])
        recipeVersions = read(.recipeVersions, [:])
        milkTypes = read(.milkTypes, [:])
        profileMilk = read(.profileMilk, [:])
        additions = read(.additions, [:])
        combos = read(.combos, [])
        learnedSeconds = read(.learnedSeconds, [:])
        queuedBrew = try? c.decodeIfPresent(Recipe.self, forKey: .queuedBrew)
        resumeRecipe = try? c.decodeIfPresent(Recipe.self, forKey: .resumeRecipe)
        purchases = read(.purchases, [])
        waterSource = read(.waterSource, .tap)
        supplies = read(.supplies, Supplies())
        alarmHistory = read(.alarmHistory, [])
        milkOpenedAt = try? c.decodeIfPresent(Date.self, forKey: .milkOpenedAt)
        milkShelfDays = read(.milkShelfDays, 4)
        tankFilledAt = try? c.decodeIfPresent(Date.self, forKey: .tankFilledAt)
        childProfiles = read(.childProfiles, [])
        memberCups = read(.memberCups, [])
        office = read(.office, OfficeTally())
        reduction = try? c.decodeIfPresent(ReductionPlan.self, forKey: .reduction)
        lastGrindSet = read(.lastGrindSet, [:])
        spilled = read(.spilled, [])
        lessonsDone = read(.lessonsDone, [])
        quizBest = read(.quizBest, 0)
        lastClockSync = try? c.decodeIfPresent(Date.self, forKey: .lastClockSync)
        electricityPrice = read(.electricityPrice, 0.18)
        milkPricePerLitre = read(.milkPricePerLitre, 6)
        warrantyNotified = read(.warrantyNotified, [])
    }

    /// The milk to use for a favorite, else the profile's milk.
    func milk(for recipe: Recipe, profileID: Int) -> MilkType {
        milkTypes[recipe.id] ?? profileMilk[profileID] ?? .whole
    }

    mutating func recordAlarms(_ alarms: [MachineAlarm], at date: Date = Date()) {
        for alarm in alarms { alarmHistory.insert(AlarmEvent(alarm: alarm, date: date), at: 0) }
        if alarmHistory.count > 300 { alarmHistory.removeLast(alarmHistory.count - 300) }
    }

    /// Keeps the ten previous versions of a favorite, newest first.
    mutating func rememberVersion(of recipe: Recipe) {
        var versions = recipeVersions[recipe.id] ?? []
        versions.insert(RecipeVersion(recipe: recipe), at: 0)
        recipeVersions[recipe.id] = Array(versions.prefix(10))
    }
}

/// A cup or mug the person owns, to warn before a drink overflows it.
struct CupProfile: Codable, Equatable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var capacityML: Int
}

struct RecipeVersion: Codable, Equatable, Identifiable {
    var id = UUID()
    var recipe: Recipe
    var savedAt = Date()
}

enum MilkType: String, Codable, CaseIterable, Identifiable {
    case whole, lowFat, lactoseFree, oat, almond, soy
    var id: String { rawValue }
    var title: String { L("milk.\(rawValue)") }

    /// Energy per 100 ml (typical values for unsweetened milk).
    var kcalPer100ml: Double {
        switch self {
        case .whole: return 64
        case .lowFat: return 46
        case .lactoseFree: return 50
        case .oat: return 45
        case .almond: return 15
        case .soy: return 33
        }
    }

    /// Plant drinks made for baristas foam best; ordinary ones foam less.
    var foamTip: String? {
        switch self {
        case .oat, .almond, .soy: return L("milk.tip.plant")
        case .lowFat: return L("milk.tip.lowFat")
        default: return nil
        }
    }

    var hasLactose: Bool { self == .whole || self == .lowFat }
}

/// Several machine drinks one after another: "espresso, then hot water".
struct DrinkCombo: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var steps: [Recipe]
}

struct BeanPurchase: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var roaster: String = ""
    var date = Date()
    var grams: Int?
    var price: Double?
    var beanID: UUID?
}

/// Where the tank water comes from; softer water scales the machine slower.
enum WaterSource: String, Codable, CaseIterable, Identifiable {
    case tap, jugFilter, bottled, softened
    var id: String { rawValue }
    var title: String { L("water.\(rawValue)") }

    /// How fast scale builds up compared with tap water.
    var scaleFactor: Double {
        switch self {
        case .tap: return 1
        case .jugFilter: return 0.7
        case .bottled: return 0.6
        case .softened: return 0.5
        }
    }
}

struct Supplies: Codable, Equatable {
    var descaler = 0
    var filters = 0
    var milkCleaner = 0
}

struct AlarmEvent: Codable, Equatable, Identifiable {
    var id = UUID()
    var alarm: MachineAlarm
    var date: Date
}

/// A cup made for someone in the household, for their own caffeine count.
struct MemberCup: Codable, Equatable {
    var memberID: UUID
    var date: Date
    var mg: Int
}

/// Who had how many cups at the office, and what each owes.
struct OfficeTally: Codable, Equatable {
    var people: [OfficePerson] = []
    /// When the count was last reset; nil until the first reset.
    var since: Date?
    var pricePerCup: Double = 2
}

struct OfficePerson: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var cups = 0
}

/// Less caffeine week by week, from today's habit to a target.
struct ReductionPlan: Codable, Equatable {
    var startMg: Int
    var targetMg: Int
    var weeks: Int
    var startDate = Date()

    func week(on date: Date = Date(), calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: startDate), to: date).day ?? 0
        return max(0, days / 7)
    }

    /// The limit for the week containing `date`; the target once finished.
    func limit(on date: Date = Date(), calendar: Calendar = .current) -> Int {
        let week = self.week(on: date, calendar: calendar)
        guard weeks > 0, week < weeks else { return targetMg }
        let step = Double(startMg - targetMg) / Double(weeks)
        return Int((Double(startMg) - step * Double(week + 1)).rounded())
    }

    func isFinished(on date: Date = Date()) -> Bool { week(on: date) >= weeks }
}
