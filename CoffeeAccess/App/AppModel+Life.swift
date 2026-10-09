import Foundation
import UIKit

/// Version 2 behaviour on the app model: the usual drink, caffeine, ratings,
/// care forecast and log, scheduled drinks, the morning routine, descaling
/// runs, carafe reminders and signature recipes.
extension AppModel {
    // MARK: Usual, last and caffeine

    var usualRecipe: Recipe { Suggestions.usual(for: data) }
    var lastRecipe: Recipe? { data.guestMode ? nil : Suggestions.last(in: activeProfile.history) }
    var caffeineToday: Int { CaffeineEstimator.total(on: Date(), in: activeProfile.history) }

    func caffeineWarning(for recipe: Recipe) -> String? {
        guard !data.guestMode else { return nil }
        return CaffeineEstimator.warning(for: recipe, today: caffeineToday, limit: settings.caffeineLimitMg,
                                         cutoffHour: settings.caffeineCutoffHour)
    }

    /// What to do before the machine starts: cup, travel mug, froth dial, ice.
    func preBrewChecklist(for recipe: Recipe) -> [String] {
        guard settings.preBrewReminders else { return [] }
        var steps: [String] = []
        switch recipe.spec.vessel {
        case .pot: steps.append(L("prebrew.pot"))
        case .travelMug: steps.append(L("prebrew.mug"))
        default: steps.append(recipe.toGo ? L("prebrew.mug") : L("prebrew.cup"))
        }
        if recipe.spec.usesMilk {
            steps.append(recipe.spec.isCold ? L("prebrew.coldCarafe") : L("prebrew.carafe"))
            if let foam = recipe.idealFoamLevel, !recipe.spec.isCold { steps.append(L("prebrew.froth", foam.title)) }
        }
        if let ice = recipe.iceLevel { steps.append(L("brew.ice.hint", ice.cubes)) }
        return steps
    }

    // MARK: Ratings and tasting notes

    var lastFinishedRecord: BrewRecord? { activeProfile.history.first { $0.completed } }

    func rating(for recordID: UUID) -> DrinkRating? { data.life.ratings[recordID] }

    func rate(_ recordID: UUID, _ change: (inout DrinkRating) -> Void) {
        updateData { data in
            var rating = data.life.ratings[recordID] ?? DrinkRating()
            change(&rating)
            rating.date = Date()
            data.life.ratings[recordID] = rating
        }
    }

    /// "Stronger" or "weaker" adjusts this person's own version of the drink,
    /// so the next cup follows the feedback.
    func applyStrengthFeedback(_ feedback: StrengthFeedback, to recipe: Recipe) {
        guard feedback != .right, !data.guestMode, recipe.spec.hasAroma, let aroma = recipe.aroma else { return }
        let step = feedback == .stronger ? 1 : -1
        guard let next = Aroma(rawValue: aroma.rawValue + step) else { return }
        var adjusted = recipe
        adjusted.aroma = next
        adjusted.customName = ""
        updateData { $0.setPersonalDefault(adjusted) }
        Announcer.shared.announce(L("rating.adjusted", recipe.beverage.name, next.title))
    }

    // MARK: Care

    var forecast: CareForecast {
        CareForecast.make(history: data.profiles.flatMap(\.history), log: data.life,
                          hardness: machineSettings.waterHardness, usesFilter: data.life.usesWaterFilter)
    }

    func logCare(_ task: CareTask, note: String = "") {
        updateData { $0.life.log(task, note: note) }
        if task == .milkCarafe { markCarafeCleaned(announce: false) }
        Announcer.shared.announce(L("log.saved", task.title))
        NotificationManager.shared.scheduleCare(forecast, enabled: settings.predictiveCareReminders)
    }

    func markCarafeCleaned(announce: Bool = true) {
        NotificationManager.shared.cancelCarafeReminder()
        guard data.life.carafeCleanPending else { return }
        updateData { $0.life.carafeCleanPending = false }
        if announce { Announcer.shared.announce(L("carafe.done")) }
    }

    // MARK: Scheduled drinks

    func saveSchedule(_ schedule: ScheduledBrew) {
        updateData { data in
            if let index = data.life.scheduledBrews.firstIndex(where: { $0.id == schedule.id }) {
                data.life.scheduledBrews[index] = schedule
            } else {
                data.life.scheduledBrews.append(schedule)
            }
        }
        rescheduleDrinks()
    }

    func deleteSchedule(_ id: UUID) {
        updateData { $0.life.scheduledBrews.removeAll { $0.id == id } }
        rescheduleDrinks()
    }

    func rescheduleDrinks() {
        Task {
            await NotificationManager.shared.requestPermission()
            NotificationManager.shared.reschedule(data.life.scheduledBrews)
        }
    }

    /// From a reminder: either open the drink ready to confirm, or (from the
    /// "Make it now" button) run the routine straight away.
    func openScheduled(_ id: UUID, brewNow: Bool) {
        guard let schedule = data.life.scheduledBrews.first(where: { $0.id == id }) else { return }
        if schedule.weekdays.isEmpty {
            updateData { data in
                if let index = data.life.scheduledBrews.firstIndex(where: { $0.id == id }) { data.life.scheduledBrews[index].enabled = false }
            }
        }
        if brewNow {
            Task { await runRoutine(schedule.recipe, turnOnFirst: schedule.turnOnFirst) }
        } else {
            pendingScheduledRecipe = schedule.recipe
        }
    }

    // MARK: Morning routine

    /// Wake the machine (it rinses itself when it heats), wait until it is
    /// ready, then make the drink. Every step is spoken.
    func runRoutine(_ recipe: Recipe, turnOnFirst: Bool = true) async {
        guard routineStatus == nil else { return }
        start()
        routineStatus = L("routine.connecting")
        defer { routineStatus = nil }
        let deadline = Date().addingTimeInterval(15)
        while !connection.isConnected, Date() < deadline { try? await Task.sleep(nanoseconds: 300_000_000) }
        guard connection.isConnected else {
            Announcer.shared.announce(L("error.notConnected"), priority: .high)
            return
        }
        if turnOnFirst, snapshot.power == .off {
            routineStatus = L("routine.heating")
            Announcer.shared.announce(L("routine.heating"))
            await powerOn()
            let ready = Date().addingTimeInterval(150)
            while snapshot.power != .ready, Date() < ready { try? await Task.sleep(nanoseconds: 1_000_000_000) }
        }
        guard snapshot.isReadyToBrew else {
            Announcer.shared.announce(MachineError.notReady(snapshot.blockingAlarms).message, priority: .high)
            return
        }
        routineStatus = L("routine.brewing", recipe.displayName)
        await brew(recipe)
    }

    // MARK: Descaling run

    /// Stages of the machine's descaling programme with typical durations.
    static let descaleStages: [(key: String, minutes: Int)] = [
        ("descale.stage.prepare", 5), ("descale.stage.run", 25), ("descale.stage.rinseFill", 3),
        ("descale.stage.rinse", 10), ("descale.stage.finish", 2),
    ]

    func startDescale() {
        updateData { $0.life.descale = DescaleRun(startedAt: Date(), stageIndex: 0, stageEndsAt: nil) }
        Announcer.shared.announce(L(Self.descaleStages[0].key))
    }

    /// Starts the timer for the current stage (after the person did the step).
    func startDescaleTimer() {
        guard var run = data.life.descale else { return }
        let stage = Self.descaleStages[run.stageIndex]
        let ends = Date().addingTimeInterval(TimeInterval(stage.minutes * 60))
        run.stageEndsAt = ends
        updateData { $0.life.descale = run }
        NotificationManager.shared.scheduleDescaleStage(L("descale.stageDone", L(stage.key + ".title")), at: ends)
        Announcer.shared.announce(L("descale.timerStarted", stage.minutes))
    }

    func advanceDescale() {
        guard var run = data.life.descale else { return }
        NotificationManager.shared.cancelDescaleStage()
        if run.stageIndex + 1 >= Self.descaleStages.count {
            updateData { $0.life.descale = nil }
            logCare(.descaling)
            Announcer.shared.success()
            Announcer.shared.announce(L("descale.finished"))
            return
        }
        run.stageIndex += 1
        run.stageEndsAt = nil
        updateData { $0.life.descale = run }
        Announcer.shared.announce(L(Self.descaleStages[run.stageIndex].key))
    }

    func cancelDescale() {
        NotificationManager.shared.cancelDescaleStage()
        updateData { $0.life.descale = nil }
    }

    // MARK: Signature recipes

    func brewSignature(_ id: SignatureRecipeID) async {
        let started = await brew(id.recipe)
        if started, !data.life.madeSignatures.contains(id.rawValue) {
            updateData { $0.life.madeSignatures.append(id.rawValue) }
        }
    }

    // MARK: App lifecycle, widgets and settings

    /// Refreshes everything computed from the history when the app opens.
    func appBecameActive() {
        NotificationManager.shared.scheduleCare(forecast, enabled: settings.predictiveCareReminders)
        NotificationManager.shared.scheduleWeeklySummary(WeeklySummary.make(history: activeProfile.history).sentence,
                                                         enabled: settings.weeklySummary)
        publishWidgetSnapshot()
        if settings.iCloudSync { CloudSync.shared.pull(into: self) }
    }

    func didChangeSettings(from old: AppSettings) {
        if old.weeklySummary != settings.weeklySummary || old.predictiveCareReminders != settings.predictiveCareReminders {
            Task {
                if settings.weeklySummary || settings.predictiveCareReminders { await NotificationManager.shared.requestPermission() }
                appBecameActive()
            }
        }
        if !old.iCloudSync, settings.iCloudSync { CloudSync.shared.push(from: self) }
        publishWidgetSnapshot()
    }

    /// What the Home Screen and Lock Screen widgets show.
    func publishWidgetSnapshot() {
        let usual = usualRecipe
        let status = connection.isConnected ? snapshot.spokenStatus : connection.title
        let snapshot = WidgetSnapshot(
            usualName: usual.displayName, usualSummary: usual.spokenSummary, usualLink: CoffeeLink.usual.absoluteString,
            machineStatus: status, machineReady: self.snapshot.isReadyToBrew, caffeineToday: caffeineToday,
            caffeineLimit: settings.caffeineLimitMg, isArabic: AppLanguage.current == .arabic, updatedAt: Date())
        if snapshot.store() { WidgetReloader.reload() }
        WatchBridge.shared.publish(model: self)
    }

    // MARK: Hooks called by the core model

    /// Called when a session ends, after it is recorded in history.
    func didFinishSession(_ session: BrewSession) {
        FamilyQueue.shared.sessionEnded(session.outcome)
        guard session.outcome == .finished else {
            if settings.soundCues { Tones.shared.cue(.problem) }
            return
        }
        if settings.soundCues { Tones.shared.cue(.ready) }
        if data.life.beanSettleCups > 0 {
            updateData { $0.life.beanSettleCups -= 1 }
        }
        if session.recipe.spec.usesMilk, settings.carafeCleanPrompt, !data.guestMode {
            updateData { $0.life.carafeCleanPending = true }
            NotificationManager.shared.remindCarafe()
        }
        HealthCaffeine.shared.record(session.recipe, enabled: settings.writeCaffeineToHealth)
        publishWidgetSnapshot()
        NotificationManager.shared.scheduleCare(forecast, enabled: settings.predictiveCareReminders)
    }

    func didChangePhase(_ activity: MachineActivity) {
        guard settings.soundCues else { return }
        switch activity {
        case .grinding: Tones.shared.cue(.grinding)
        case .dispensingMilk, .steaming: Tones.shared.cue(.milk)
        case .brewingCoffee, .dispensingWater: Tones.shared.cue(.pouring)
        default: break
        }
    }

    /// Ties the Bluetooth machine just connected to the active machine record,
    /// so switching machines later reconnects to the right one.
    func rememberConnectedMachine() {
        guard let id = UserDefaults.standard.string(forKey: BluetoothMachineLink.rememberedPeripheralKey),
              let machine = data.life.activeMachine, machine.peripheralID != id else { return }
        updateData { data in
            if let index = data.life.machines.firstIndex(where: { $0.id == machine.id }) { data.life.machines[index].peripheralID = id }
        }
    }

    func didSelectBean(previous: UUID?) {
        guard previous != nil, previous != data.activeBeanID else { return }
        updateData { $0.life.beanSettleCups = 3 }
        Announcer.shared.announce(L("bean.settle.announce"))
    }
}
