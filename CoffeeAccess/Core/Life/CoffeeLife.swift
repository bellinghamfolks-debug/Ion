import Foundation

/// Everything version 2 remembers beyond profiles and beans: how each cup
/// tasted, scheduled drinks, the household, machines, care history and the
/// home layout. Saved inside AppData; every field reads safely when absent.
struct CoffeeLife: Codable, Equatable {
    /// Feedback per cup, keyed by the BrewRecord id.
    var ratings: [UUID: DrinkRating] = [:]
    var scheduledBrews: [ScheduledBrew] = []
    var household: [HouseholdMember] = []
    var maintenanceLog: [MaintenanceEntry] = []
    var machines: [MachineRecord] = []
    var activeMachineID: UUID?
    var homeOrder: [HomeSection] = HomeSection.allCases
    var hiddenHomeSections: [HomeSection] = []
    /// Cups left before freshly changed beans have settled in the grinder.
    var beanSettleCups = 0
    /// A descaling run in progress, so the timer survives the app closing.
    var descale: DescaleRun?
    /// A milk drink was made and the carafe has not been rinsed yet.
    var carafeCleanPending = false
    /// Signature recipes the person has made at least once.
    var madeSignatures: [String] = []
    /// A filter cartridge is fitted in the water tank.
    var usesWaterFilter = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        ratings = read(.ratings, [:])
        scheduledBrews = read(.scheduledBrews, [])
        household = read(.household, [])
        maintenanceLog = read(.maintenanceLog, [])
        machines = read(.machines, [])
        activeMachineID = try? c.decodeIfPresent(UUID.self, forKey: .activeMachineID)
        homeOrder = read(.homeOrder, HomeSection.allCases)
        hiddenHomeSections = read(.hiddenHomeSections, [])
        beanSettleCups = read(.beanSettleCups, 0)
        descale = try? c.decodeIfPresent(DescaleRun.self, forKey: .descale)
        carafeCleanPending = read(.carafeCleanPending, false)
        madeSignatures = read(.madeSignatures, [])
        usesWaterFilter = read(.usesWaterFilter, true)
    }

    /// The saved order, with any section added in a later version at the end.
    var orderedHomeSections: [HomeSection] {
        var order = homeOrder.filter { HomeSection.allCases.contains($0) }
        for section in HomeSection.allCases where !order.contains(section) { order.append(section) }
        var seen = Set<HomeSection>()
        return order.filter { seen.insert($0).inserted }
    }

    var visibleHomeSections: [HomeSection] { orderedHomeSections.filter { !hiddenHomeSections.contains($0) } }

    var activeMachine: MachineRecord? { machines.first { $0.id == activeMachineID } ?? machines.first }

    mutating func moveHomeSection(_ section: HomeSection, by offset: Int) {
        var order = orderedHomeSections
        guard let index = order.firstIndex(of: section) else { return }
        let target = index + offset
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        homeOrder = order
    }

    mutating func setHomeSection(_ section: HomeSection, visible: Bool) {
        hiddenHomeSections.removeAll { $0 == section }
        if !visible { hiddenHomeSections.append(section) }
    }

    mutating func log(_ task: CareTask, at date: Date = Date(), note: String = "") {
        maintenanceLog.insert(MaintenanceEntry(task: task, date: date, note: note), at: 0)
        if maintenanceLog.count > 300 { maintenanceLog.removeLast(maintenanceLog.count - 300) }
    }

    func lastDone(_ task: CareTask) -> Date? {
        maintenanceLog.first { $0.task == task }?.date
    }
}

/// How a cup turned out, from the quick questions after brewing.
struct DrinkRating: Codable, Equatable {
    var liked: Bool?
    var strength: StrengthFeedback?
    /// A free tasting note, typed or dictated.
    var note: String = ""
    var date = Date()
}

enum StrengthFeedback: String, Codable, CaseIterable {
    case weaker, right, stronger
    var title: String { L("rating.strength.\(rawValue)") }
}

/// "Make my cappuccino at 7:00": a reminder that opens the app ready to brew.
struct ScheduledBrew: Codable, Equatable, Identifiable {
    var id = UUID()
    var recipe: Recipe
    var hour: Int = 7
    var minute: Int = 0
    /// 1 = Sunday … 7 = Saturday. Empty means once, at the next such time.
    var weekdays: [Int] = []
    var enabled = true
    /// Turn the machine on first, as in the morning routine.
    var turnOnFirst = true
    var ownerName: String = ""

    var timeText: String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLanguage.current.locale))
    }

    var daysText: String {
        if weekdays.isEmpty { return L("schedule.once") }
        if Set(weekdays) == Set(1...7) { return L("schedule.everyDay") }
        if Set(weekdays) == Set([1, 2, 3, 4, 5]) { return L("schedule.workdays") }
        let symbols = AppLanguage.current == .arabic ? Self.arabicDays : Calendar.current.shortWeekdaySymbols
        return weekdays.sorted().compactMap { symbols[safe: $0 - 1] }.joined(separator: L("list.separator"))
    }

    static let arabicDays = ["الأحد", "الإثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"]
}

/// A person in the household with the drink they usually have.
struct HouseholdMember: Codable, Equatable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var recipe: Recipe
}

/// The care jobs the log and the forecast know about.
enum CareTask: String, Codable, CaseIterable, Identifiable {
    case descaling, waterFilter, brewingUnit, milkCarafe, emptyContainers, waterHardness
    var id: String { rawValue }
    var title: String { L("care.\(rawValue)") }
    var guide: MaintenanceGuideID {
        switch self {
        case .descaling: return .descaling
        case .waterFilter: return .waterFilter
        case .brewingUnit: return .brewingUnit
        case .milkCarafe: return .milkCarafe
        case .emptyContainers: return .emptyContainers
        case .waterHardness: return .waterHardness
        }
    }

    init?(guide: MaintenanceGuideID) {
        switch guide {
        case .descaling: self = .descaling
        case .waterFilter: self = .waterFilter
        case .brewingUnit: self = .brewingUnit
        case .milkCarafe, .coldCarafe: self = .milkCarafe
        case .emptyContainers: self = .emptyContainers
        case .waterHardness: self = .waterHardness
        case .fillWater, .fillBeans: return nil
        }
    }
}

struct MaintenanceEntry: Codable, Equatable, Identifiable {
    var id = UUID()
    var task: CareTask
    var date: Date
    var note: String = ""
}

/// A machine the person owns: home, office, holiday flat.
struct MachineRecord: Codable, Equatable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var model: String = "Eletta Ultra ECAM 472.85.MB"
    var serial: String = ""
    var purchaseDate: Date?
    var warrantyYears: Int = 2
    /// The Bluetooth identity the app remembered for this machine.
    var peripheralID: String?

    var warrantyEnds: Date? {
        purchaseDate.flatMap { Calendar.current.date(byAdding: .year, value: warrantyYears, to: $0) }
    }

    func warrantyActive(now: Date = Date()) -> Bool? {
        warrantyEnds.map { $0 > now }
    }
}

/// Home screen sections the person can reorder or hide.
enum HomeSection: String, Codable, CaseIterable, Identifiable {
    case ready, caffeine, today, family, favorites, journey, moment, seasonal, recommended, signature, collections, frequent
    var id: String { rawValue }
    var title: String { L("homeSection.\(rawValue)") }
}

/// A descaling run: which stage is under way and when it ends.
struct DescaleRun: Codable, Equatable {
    var startedAt: Date
    var stageIndex: Int
    var stageEndsAt: Date?
}
