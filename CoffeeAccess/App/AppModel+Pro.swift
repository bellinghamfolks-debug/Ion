import Foundation
import UIKit

/// A drink the app offers to make: after an alarm is fixed, or once the
/// machine connects after a drink was asked for offline.
struct BrewOffer: Identifiable, Equatable {
    let id = UUID()
    var recipe: Recipe
    var message: String
}

/// Several drinks in a row (a combo, or warming the cup first). The person
/// confirms each next step on the brewing screen once the cup is ready.
struct BrewSequence: Equatable {
    var name: String
    var steps: [Recipe]
    /// What to do before each step after the first ("empty the cup").
    var instructions: [Int: String] = [:]
    var index = 0

    var current: Recipe? { steps[safe: index] }
    var next: Recipe? { steps[safe: index + 1] }
    var nextInstruction: String? { instructions[index + 1] }
}

/// Short-lived state that is never saved.
@MainActor
final class ProRuntime {
    var disconnectTask: Task<Void, Never>?
    var disconnectedAt: Date?
    var lastTick = -1
}

/// Version 3 behaviour on the app model: brewing rules and feedback,
/// learned durations, the offline queue and resume, alarms, the grinder
/// coach, quiet reconnects, clock sync, following the machine's profile,
/// combos and the "left on" reminder.
extension AppModel {
    // MARK: Before brewing

    /// Why this drink may not start now (a child's profile), or nil.
    func brewBlockReason(_ recipe: Recipe) -> String? {
        if !data.guestMode, data.life.pro.childProfiles.contains(activeProfile.id), !ChildSafety.isAllowed(recipe) {
            return L("child.blocked", activeProfile.name)
        }
        return nil
    }

    func startAnnouncement(for recipe: Recipe) -> String {
        let name = settings.brailleBrief ? recipe.brief : recipe.displayName
        var text = L("announce.brewStarted", name)
        if settings.verbosity >= 2 { text += L("sentence.separator") + recipe.spokenSummary }
        return text
    }

    /// Everything said or done once a drink has started.
    func didStartBrewing(_ recipe: Recipe) {
        if settings.hapticOnly { HapticPatterns.play(.started) }
        proRuntime.lastTick = 0
        NotificationManager.shared.cancelLeftOn()
        if data.life.pro.queuedBrew != nil || data.life.pro.resumeRecipe != nil {
            updateData { $0.life.pro.queuedBrew = nil; $0.life.pro.resumeRecipe = nil }
        }
        if recipe.coffeeML != nil, let grind = GrindCoach.pendingSetting(for: data.activeBean, lastSet: data.life.pro.lastGrindSet),
           let bean = data.activeBean {
            Announcer.shared.announce(L("grindCoach.now", grind))
            updateData { $0.life.pro.lastGrindSet[bean.id] = grind }
        }
        if let milk = milkWarning(for: recipe) { Announcer.shared.announce(milk) }
    }

    /// The machine is not connected: keep the drink and offer it on connect.
    func queueForConnection(_ recipe: Recipe) -> Bool {
        guard settings.offlineQueue, !connection.isConnected else { return false }
        updateData { $0.life.pro.queuedBrew = recipe }
        Announcer.shared.announce(L("offline.saved", recipe.displayName), priority: .high)
        return true
    }

    /// Opened milk past its days, or a plant milk that foams differently.
    func milkWarning(for recipe: Recipe) -> String? {
        guard recipe.spec.usesMilk else { return nil }
        return MilkFreshness.warning(openedAt: data.life.pro.milkOpenedAt, shelfDays: data.life.pro.milkShelfDays)
    }

    /// Extra lines for the confirmation: cup size, milk type, stale water.
    func proChecklist(for recipe: Recipe) -> [String] {
        var lines: [String] = []
        if settings.verbosity == 0 { return lines }
        if let cup = CupFit.sentence(for: recipe, cups: data.life.pro.cups) { lines.append(cup) }
        if recipe.spec.usesMilk {
            let milk = data.life.pro.milk(for: recipe, profileID: activeProfile.id)
            if milk != .whole { lines.append(L("milk.use", milk.title)) }
            if let warning = milkWarning(for: recipe) { lines.append(warning) }
        }
        if settings.tankWaterReminder, TankWater.isStale(filledAt: data.life.pro.tankFilledAt) {
            lines.append(L("tank.stale", TankWater.days(since: data.life.pro.tankFilledAt)))
        }
        if recipe.double == true { lines.append(L("double.twoCups")) }
        return lines
    }

    // MARK: While brewing

    var expectedSecondsForSession: Double? {
        guard let recipe = session?.recipe, link.kind == .bluetooth else { return nil }
        return data.life.pro.learnedSeconds[LearnedDuration.key(for: recipe)]
    }

    /// A rising tick every 10%, for progress without speech.
    func progressTick(_ progress: Double) {
        guard settings.progressTicks || settings.hapticOnly else { return }
        let decile = Int(progress * 10)
        guard decile > proRuntime.lastTick, decile < 10 else { return }
        proRuntime.lastTick = decile
        if settings.progressTicks, !FocusFilterState.quiet { Tones.shared.level(progress) }
        if settings.hapticOnly { HapticPatterns.play(.attention) }
    }

    func proPhase(_ activity: MachineActivity) {
        if settings.hapticOnly, let pattern = HapticPatterns.pattern(for: activity) { HapticPatterns.play(pattern) }
    }

    // MARK: After brewing

    func proDidFinish(_ session: BrewSession) {
        let recipe = session.recipe
        recordMemberCup(session)
        guard session.outcome == .finished else {
            if settings.hapticOnly { HapticPatterns.play(.problem) }
            if case .failed = session.outcome, !snapshot.blockingAlarms.isEmpty {
                updateData { $0.life.pro.resumeRecipe = recipe }
                Announcer.shared.announce(L("resume.saved"))
            }
            sequence = nil
            return
        }
        if settings.hapticOnly { HapticPatterns.play(.finished) }
        if link.kind == .bluetooth {
            let seconds = Date().timeIntervalSince(session.startedAt)
            let key = LearnedDuration.key(for: recipe)
            updateData { $0.life.pro.learnedSeconds[key] = LearnedDuration.update($0.life.pro.learnedSeconds[key], with: seconds) }
        }
        var later: [String] = []
        if let note = data.life.pro.additions[recipe.id], !note.isEmpty { later.append(L("additions.remind", note)) }
        if settings.waterReminder, CaffeineEstimator.milligrams(for: recipe) > 0 { later.append(L("water.reminder")) }
        if settings.dripWait, recipe.spec.vessel != .pot {
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                Announcer.shared.announce(L("drip.wait"))
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                Announcer.shared.announce(([L("drip.take")] + later).joined(separator: L("sentence.separator")))
            }
        } else if !later.isEmpty {
            Announcer.shared.announce(later.joined(separator: L("sentence.separator")))
        }
        if recipe.spec.usesMilk, settings.milkFridgeReminder { NotificationManager.shared.remindMilkToFridge() }
        if var running = sequence {
            if let next = running.next {
                running.index += 1
                sequence = running
                Announcer.shared.announce(L("sequence.next", running.nextInstructionForCurrent ?? "", next.displayName))
            } else {
                sequence = nil
            }
        }
        scheduleLeftOnReminder()
    }

    private func recordMemberCup(_ session: BrewSession) {
        let queue = FamilyQueue.shared
        guard session.outcome == .finished, queue.isRunning, !queue.waitingForCup, let member = queue.current?.memberID else { return }
        let mg = CaffeineEstimator.milligrams(for: session.recipe)
        updateData { data in
            data.life.pro.memberCups.insert(MemberCup(memberID: member, date: Date(), mg: mg), at: 0)
            if data.life.pro.memberCups.count > 500 { data.life.pro.memberCups.removeLast(data.life.pro.memberCups.count - 500) }
        }
    }

    // MARK: Sequences: warm the cup first, combos

    func startSequence(_ sequence: BrewSequence) async {
        guard let first = sequence.current else { return }
        self.sequence = sequence
        let started = await brew(first)
        if !started { self.sequence = nil }
    }

    /// Hot water first to warm the cup, then the drink.
    func brewWithPrewarm(_ recipe: Recipe) async {
        var water = Recipe.standard(.hotWater)
        water.waterML = water.waterRange.map { $0.clamp(60) } ?? 60
        water.customName = L("prewarm.step")
        await startSequence(BrewSequence(name: recipe.displayName, steps: [water, recipe], instructions: [1: L("prewarm.empty")]))
    }

    func runCombo(_ combo: DrinkCombo) async {
        var instructions: [Int: String] = [:]
        for index in combo.steps.indices.dropFirst() { instructions[index] = L("combo.sameCup") }
        await startSequence(BrewSequence(name: combo.name, steps: combo.steps, instructions: instructions))
    }

    /// The person put the cup back: make the next drink of the sequence.
    func continueSequence() async {
        guard let running = sequence, let recipe = running.current else { return }
        let started = await brew(recipe)
        if !started { sequence = nil }
    }

    func cancelSequence() {
        sequence = nil
    }

    // MARK: Alarms

    func proDidReceiveAlarms(_ added: [MachineAlarm]) {
        updateData { $0.life.pro.recordAlarms(added) }
        if settings.hapticOnly { HapticPatterns.play(.attention) }
    }

    func proAlarmsChanged(from old: MachineSnapshot, to new: MachineSnapshot) {
        let water: Set<MachineAlarm> = [.waterTankEmpty, .waterTankMissing]
        if old.alarms.contains(where: water.contains), !new.alarms.contains(where: water.contains) {
            updateData { $0.life.pro.tankFilledAt = Date() }
        }
        if old.alarms.contains(.beansEmpty), !new.alarms.contains(.beansEmpty), data.beanProfiles.count > 1 {
            askWhichBean = true
        }
        if !old.blockingAlarms.isEmpty, new.blockingAlarms.isEmpty, new.power == .ready,
           let recipe = data.life.pro.resumeRecipe, session?.isRunning != true {
            updateData { $0.life.pro.resumeRecipe = nil }
            offer = BrewOffer(recipe: recipe, message: L("resume.offer", recipe.displayName))
            Announcer.shared.announce(L("resume.offer", recipe.displayName), priority: .high)
        }
    }

    // MARK: The machine's own profile and power

    func proSnapshotChanged(from old: MachineSnapshot, to new: MachineSnapshot) {
        if settings.followMachineProfile, connection.isConnected, old.power != .unknown,
           old.activeProfile != new.activeProfile, new.activeProfile != data.activeProfileID,
           let profile = data.profiles.first(where: { $0.id == new.activeProfile }) {
            updateData { $0.activeProfileID = profile.id }
            Announcer.shared.announce(L("follow.profile", profile.name))
        }
        if new.power == .off || new.power == .shuttingDown {
            NotificationManager.shared.cancelLeftOn()
        } else if new.power == .ready, old.power != .ready, old.power != .busy {
            scheduleLeftOnReminder()
        }
    }

    /// Only when the machine's own auto-off is two hours or longer.
    func scheduleLeftOnReminder() {
        guard settings.leftOnReminder, machineSettings.autoOff.rawValue >= MachineSettings.AutoOff.twoHours.rawValue else { return }
        NotificationManager.shared.remindLeftOn(after: 3600)
    }

    // MARK: Connection

    /// With quiet reconnect, a short drop is not announced.
    func announceDisconnect(_ announce: @escaping () -> Void) {
        proRuntime.disconnectedAt = Date()
        guard settings.quietReconnect else { announce(); return }
        proRuntime.disconnectTask?.cancel()
        proRuntime.disconnectTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled, !self.connection.isConnected else { return }
            announce()
        }
    }

    /// True when the connect is a quick reconnect that should stay silent.
    func isQuietReconnect() -> Bool {
        defer { proRuntime.disconnectedAt = nil }
        guard settings.quietReconnect, let dropped = proRuntime.disconnectedAt, Date().timeIntervalSince(dropped) < 10 else { return false }
        proRuntime.disconnectTask?.cancel()
        return true
    }

    func proDidConnect() {
        if link.kind == .bluetooth { updateData { $0.life.pro.lastClockSync = Date() } }
        if let queued = data.life.pro.queuedBrew {
            updateData { $0.life.pro.queuedBrew = nil }
            offer = BrewOffer(recipe: queued, message: L("offline.offer", queued.displayName))
            Announcer.shared.announce(L("offline.offer", queued.displayName), priority: .high)
        }
    }

    /// Keeps the machine's clock right: daily, and when the time or time zone changes.
    func syncClockIfNeeded(force: Bool = false) {
        guard connection.isConnected, link.kind == .bluetooth else { return }
        if !force, let last = data.life.pro.lastClockSync, Date().timeIntervalSince(last) < 20 * 3600 { return }
        Task {
            do {
                try await link.setClock(Date())
                updateData { $0.life.pro.lastClockSync = Date() }
            } catch {}
        }
    }

    // MARK: Opening the app

    func proBecameActive() {
        Announcer.shared.focusQuiet = FocusFilterState.quiet
        syncClockIfNeeded()
        scheduleWarrantyReminders()
        NotificationManager.shared.scheduleMilkExpiry(openedAt: data.life.pro.milkOpenedAt, shelfDays: data.life.pro.milkShelfDays)
        if settings.locationSwitch { LocationSwitcher.shared.checkNearestMachine(model: self) }
    }

    /// The person opened a new carton of milk today.
    func openedNewMilk() {
        updateData { $0.life.pro.milkOpenedAt = Date() }
        NotificationManager.shared.scheduleMilkExpiry(openedAt: Date(), shelfDays: data.life.pro.milkShelfDays)
        Announcer.shared.announce(L("milk.opened.done", data.life.pro.milkShelfDays))
    }

    /// The person opened a new bag of the beans in the hopper: date it and log the purchase.
    @discardableResult
    func openedNewBag() -> String {
        guard var bean = data.activeBean else { return L("bag.noBean") }
        bean.openedAt = Date()
        let purchase = BeanPurchase(name: bean.name, roaster: bean.roaster, grams: bean.bagGrams, price: bean.price, beanID: bean.id)
        updateData { data in
            _ = data.saveBean(bean)
            data.life.pro.purchases.insert(purchase, at: 0)
            data.life.beanSettleCups = max(data.life.beanSettleCups, 2)
        }
        let text = L("bag.opened", bean.name)
        Announcer.shared.announce(text)
        return text
    }

    // MARK: Machines

    func switchMachine(to machine: MachineRecord, announcement: String? = nil) {
        guard machine.id != data.life.activeMachine?.id else { return }
        updateData { $0.life.activeMachineID = machine.id }
        if let id = machine.peripheralID {
            UserDefaults.standard.set(id, forKey: BluetoothMachineLink.rememberedPeripheralKey)
        } else {
            bluetoothLink?.forgetMachine()
        }
        if settings.linkKind == .bluetooth { reconnect() }
        Announcer.shared.announce(announcement ?? L("machines.switched", machine.name))
    }

    /// Warranty reminders for every machine with a purchase date.
    func scheduleWarrantyReminders() {
        for machine in data.life.machines {
            NotificationManager.shared.scheduleWarranty(machine)
        }
    }

    // MARK: Status

    /// One sentence for a shake or the giant screen: machine, drink, caffeine.
    var statusSentence: String {
        var parts: [String] = []
        if let session, session.isRunning {
            parts.append(L("status.brewing", session.recipe.displayName, Int(session.progress * 100)))
        }
        parts.append(connection.isConnected ? snapshot.spokenStatus : connection.title)
        if !data.guestMode { parts.append(L("caffeine.spoken", caffeineToday, caffeineLimitToday)) }
        return parts.joined(separator: L("sentence.separator"))
    }

    /// Today's limit: the reduction plan's week, else the person's own.
    var caffeineLimitToday: Int {
        data.life.pro.reduction.map { $0.limit() } ?? settings.caffeineLimitMg
    }

    var decafBeanIDs: Set<UUID> { Set(data.beanProfiles.filter(\.decaf).map(\.id)) }

    var ramadanActive: Bool { RamadanMode.isActive(setting: settings.ramadanMode) }
}

extension BrewSequence {
    /// The instruction before the step now current.
    var nextInstructionForCurrent: String? { instructions[index] }
}

/// Set by the Focus filter: quiet sounds while a Focus such as Sleep is on.
enum FocusFilterState {
    static let key = "focus.quiet"
    static var quiet: Bool {
        UserDefaults(suiteName: SharedCoffee.appGroup)?.bool(forKey: key) ?? false
    }
}
