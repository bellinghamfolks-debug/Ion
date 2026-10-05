import Foundation

/// A deterministic model of a bean-to-cup machine, advanced by explicit time
/// steps so it can be unit tested. It drives the demo mode: every screen,
/// announcement and maintenance flow can be tried without the real machine.
struct DemoMachineEngine: Equatable {
    static let waterCapacityML = 1800
    static let beanCapacityDoses = 40
    static let groundsCapacity = 14
    static let drinksBetweenDescaling = 150

    enum Event: Equatable {
        case poweredOn
        case phase(MachineActivity)
        case finished(Recipe)
        case stopped(Recipe)
        case alarmsChanged([MachineAlarm])
    }

    private struct Step: Equatable {
        let activity: MachineActivity
        var remaining: Double
    }

    private(set) var snapshot = MachineSnapshot(power: .off)
    private(set) var waterML = 1500
    private(set) var beanDoses = 30
    private(set) var groundsCount = 3
    private(set) var drinksUntilDescale = 120
    private(set) var milkCleanPending = false
    private(set) var current: Recipe?
    private(set) var settings = MachineSettings()
    // Lifetime counters, as the real machine keeps them.
    private(set) var coffeeDrinks = 0
    private(set) var milkDrinks = 0
    private(set) var coldMilkDrinks = 0
    private(set) var teaDrinks = 0
    private(set) var waterUsedML = 0
    private(set) var descaleCount = 0
    private(set) var milkCleanings = 0
    private var steps: [Step] = []
    private var totalSeconds: Double = 0
    private var elapsed: Double = 0
    private var warmUpRemaining: Double = 0

    init(poweredOn: Bool = false) {
        if poweredOn { snapshot.power = .ready }
        refreshAlarms()
    }

    // MARK: Commands

    mutating func powerOn() -> [Event] {
        guard snapshot.power == .off || snapshot.power == .unknown else { return [] }
        snapshot.power = .turningOn
        snapshot.activity = .heating
        warmUpRemaining = 8
        return [.phase(.heating)]
    }

    mutating func powerOff() {
        steps = []
        current = nil
        snapshot.power = .off
        snapshot.activity = .idle
        snapshot.progress = nil
    }

    mutating func brew(_ recipe: Recipe) throws -> [Event] {
        guard snapshot.power == .ready else {
            if snapshot.power == .off { throw MachineError.notReady([]) }
            throw MachineError.notReady(snapshot.blockingAlarms)
        }
        let blocking = snapshot.blockingAlarms
        guard blocking.isEmpty else { throw MachineError.notReady(blocking) }

        let recipe = recipe.normalized()
        let spec = recipe.spec
        var plan: [Step] = []
        // Pots and cold extraction take longer per millilitre.
        let secondsPerML = spec.vessel == .pot ? 1.0 / 6 : (spec.isCold && spec.layers.contains(.coffee) ? 0.4 : 0.25)
        let coffeeSteps: [Step] = recipe.coffeeML.map { ml in
            [Step(activity: .grinding, remaining: 4), Step(activity: .brewingCoffee, remaining: Double(ml) * secondsPerML)]
        } ?? []
        let milkStep: [Step] = recipe.milkSeconds.map { [Step(activity: .dispensingMilk, remaining: Double($0))] } ?? []
        let waterStep: [Step] = recipe.waterML.map { [Step(activity: .dispensingWater, remaining: Double($0) / 12)] } ?? []
        let milkBefore = recipe.milkFirst || spec.layers.first == .milk
        plan = milkBefore ? milkStep + coffeeSteps : coffeeSteps + milkStep
        // Americano and long black pour water first, as on the machine.
        plan = waterStep + plan
        if recipe.extraShot {
            plan.append(Step(activity: .brewingCoffee, remaining: 8))
        }

        steps = plan
        totalSeconds = plan.reduce(0) { $0 + $1.remaining }
        elapsed = 0
        current = recipe
        snapshot.power = .busy
        snapshot.activity = plan.first?.activity ?? .idle
        snapshot.progress = 0
        return [.phase(snapshot.activity)]
    }

    mutating func stop() -> [Event] {
        guard let recipe = current else { return [] }
        let before = snapshot.alarms
        consume(recipe, fraction: totalSeconds > 0 ? elapsed / totalSeconds : 1)
        finishBrewing()
        return [.stopped(recipe)] + alarmEvents(changedFrom: before)
    }

    mutating func selectProfile(_ profile: Int) {
        snapshot.activeProfile = max(1, min(profile, AppData.profileCount))
    }

    mutating func apply(_ settings: MachineSettings) { self.settings = settings }

    var counters: MachineCounters {
        MachineCounters(values: [
            3000: coffeeDrinks, 3001: milkDrinks, 3017: coldMilkDrinks, 3025: teaDrinks,
            106: waterUsedML * 2, 105: descaleCount, 111: milkCleanings, 108: 0,
        ])
    }

    // MARK: Time

    mutating func advance(by seconds: Double) -> [Event] {
        var events: [Event] = []
        var remaining = seconds
        if snapshot.power == .turningOn {
            warmUpRemaining -= remaining
            if warmUpRemaining <= 0 {
                snapshot.power = .ready
                snapshot.activity = .idle
                events.append(.poweredOn)
            }
            return events
        }
        guard let recipe = current else { return events }
        while remaining > 0, !steps.isEmpty {
            let used = min(remaining, steps[0].remaining)
            steps[0].remaining -= used
            elapsed += used
            remaining -= used
            if steps[0].remaining <= 0.0001 {
                steps.removeFirst()
                if let next = steps.first {
                    snapshot.activity = next.activity
                    events.append(.phase(next.activity))
                }
            }
        }
        if steps.isEmpty {
            let before = snapshot.alarms
            consume(recipe, fraction: 1)
            finishBrewing()
            events.append(.finished(recipe))
            events += alarmEvents(changedFrom: before)
        } else {
            snapshot.progress = totalSeconds > 0 ? min(99, Int(elapsed / totalSeconds * 100)) : nil
        }
        return events
    }

    // MARK: Demo maintenance controls

    mutating func refillWater() -> [Event] { mutateResources { $0.waterML = Self.waterCapacityML } }
    mutating func refillBeans() -> [Event] { mutateResources { $0.beanDoses = Self.beanCapacityDoses } }
    mutating func emptyGrounds() -> [Event] { mutateResources { $0.groundsCount = 0 } }
    mutating func cleanMilkCarafe() -> [Event] {
        mutateResources { $0.milkCleanPending = false; $0.milkCleanings += 1 }
    }
    mutating func completeDescaling() -> [Event] {
        mutateResources { $0.drinksUntilDescale = Self.drinksBetweenDescaling; $0.descaleCount += 1 }
    }

    // MARK: Internals

    private mutating func mutateResources(_ change: (inout DemoMachineEngine) -> Void) -> [Event] {
        let before = snapshot.alarms
        change(&self)
        refreshAlarms()
        return alarmEvents(changedFrom: before)
    }

    private mutating func consume(_ recipe: Recipe, fraction: Double) {
        let share = max(0, min(fraction, 1))
        let water = Double((recipe.coffeeML ?? 0) + (recipe.waterML ?? 0)) * share
        waterML = max(0, waterML - Int(water.rounded()))
        waterUsedML += Int(water.rounded())
        if share >= 1 {
            if recipe.spec.isTea { teaDrinks += 1 }
            else if recipe.beverage == .coldMilk { coldMilkDrinks += 1 }
            else if recipe.milkSeconds != nil && recipe.coffeeML != nil { milkDrinks += 1 }
            else if recipe.coffeeML != nil { coffeeDrinks += 1 }
        }
        if recipe.coffeeML != nil {
            var doses = recipe.beverage == .espressoDouble || recipe.beverage == .doppioPlus ? 2 : 1
            if recipe.extraShot { doses += 1 }
            beanDoses = max(0, beanDoses - doses)
            groundsCount += 1
        }
        if recipe.milkSeconds != nil { milkCleanPending = true }
        drinksUntilDescale -= 1
        refreshAlarms()
    }

    private mutating func finishBrewing() {
        steps = []
        current = nil
        totalSeconds = 0
        elapsed = 0
        snapshot.power = .ready
        snapshot.activity = .idle
        snapshot.progress = nil
        refreshAlarms()
    }

    private mutating func refreshAlarms() {
        var alarms: Set<MachineAlarm> = []
        if waterML < 100 { alarms.insert(.waterTankEmpty) }
        if groundsCount >= Self.groundsCapacity { alarms.insert(.wasteContainerFull) }
        if beanDoses == 0 { alarms.insert(.beansEmpty) }
        if drinksUntilDescale <= 0 { alarms.insert(.descaleNeeded) }
        if milkCleanPending { alarms.insert(.milkCarafeNeedsCleaning) }
        snapshot.alarms = MachineAlarm.allCases.filter(alarms.contains)
        snapshot.updatedAt = Date()
    }

    private func alarmEvents(changedFrom before: [MachineAlarm]) -> [Event] {
        before == snapshot.alarms ? [] : [.alarmsChanged(snapshot.alarms)]
    }

    var waterLevel: Double { Double(waterML) / Double(Self.waterCapacityML) }
    var beanLevel: Double { Double(beanDoses) / Double(Self.beanCapacityDoses) }
    var groundsLevel: Double { min(1, Double(groundsCount) / Double(Self.groundsCapacity)) }
}

/// Runs the demo engine in real time (sped up a little so waiting is short).
@MainActor
final class DemoMachineLink: MachineLink {
    let kind: MachineLinkKind = .demo
    var onSnapshot: ((MachineSnapshot) -> Void)?
    var onConnection: ((ConnectionState) -> Void)?
    var onEvent: ((DemoMachineEngine.Event) -> Void)?

    private(set) var engine = DemoMachineEngine()
    private var timer: Timer?
    private let tick: TimeInterval = 0.5
    private let speed: Double

    init(speed: Double = 2) { self.speed = speed }

    func connect() {
        onConnection?(.connected(L("demo.machine.name")))
        startTimer()
        publish([])
    }

    func disconnect() {
        timer?.invalidate()
        timer = nil
        onConnection?(.disconnected)
    }

    func refresh() { publish([]) }

    func powerOn() async throws { publish(engine.powerOn()) }

    func brew(_ recipe: Recipe) async throws { publish(try engine.brew(recipe)) }

    func stop(_ beverage: BeverageID) async throws { publish(engine.stop()) }

    func powerOff() async throws { engine.powerOff(); publish([]) }

    func apply(_ settings: MachineSettings) async throws { engine.apply(settings) }

    func readSettings(into settings: MachineSettings) async -> MachineSettings? { engine.settings }

    func readCounters() async -> MachineCounters { engine.counters }

    func readProfileNames() async -> [Int: String] { [:] }

    func setClock(_ date: Date) async throws {}

    func selectProfile(_ profile: Int) async throws { engine.selectProfile(profile); publish([]) }

    func perform(_ change: (inout DemoMachineEngine) -> [DemoMachineEngine.Event]) {
        publish(change(&engine))
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: tick, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.publish(self.engine.advance(by: self.tick * self.speed))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func publish(_ events: [DemoMachineEngine.Event]) {
        onSnapshot?(engine.snapshot)
        events.forEach { onEvent?($0) }
    }
}
