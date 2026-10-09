import Foundation

struct AppSettings: Codable, Equatable {
    var linkKind: MachineLinkKind = .demo
    var confirmBeforeBrewing = true
    var announcePhases = true
    var announceProgress = true
    var announceAlarms = true
    var haptics = true
    var speakWithoutVoiceOver = false
    var hasCompletedOnboarding = false
    var notifyWhenReady = true
    var remindBrewingUnitWeekly = false
    var remindCarafeDaily = false
    var remindFilterMonthly = false

    // Version 2
    /// Daily caffeine limit in milligrams (an estimate from the recipes).
    var caffeineLimitMg = 400
    /// No caffeine after this hour (0-23); -1 turns the reminder off.
    var caffeineCutoffHour = 17
    var writeCaffeineToHealth = false
    /// "Put a cup under the spout" and froth-dial reminders before milk drinks.
    var preBrewReminders = true
    /// Suggest rinsing the milk carafe after a milk drink.
    var carafeCleanPrompt = true
    /// A distinct short sound for each brewing phase.
    var soundCues = false
    /// A rising tone while changing an amount.
    var quantityTones = true
    /// Three big buttons only.
    var simpleMode = false
    /// Warmer home colours in the morning, calmer in the evening.
    var timeOfDayTheme = true
    /// A summary every Sunday evening.
    var weeklySummary = false
    /// Remind when the filter or descaling is predicted to be due.
    var predictiveCareReminders = true
    /// Sync recipes, beans and settings through iCloud.
    var iCloudSync = false
    /// Live Activity on the Lock Screen while a drink is made.
    var liveActivities = true

    // Version 3
    /// Vibration patterns for every phase, for people who neither see nor hear.
    var hapticOnly = false
    /// Short wording for braille displays ("Cappuccino, strong, 60 ml").
    var brailleBrief = false
    /// Voice and rate for announcements spoken without VoiceOver.
    var speechVoiceID = ""
    var speechRate: Double = 0.5
    /// 0 brief, 1 standard, 2 detailed.
    var verbosity = 1
    var shakeForStatus = true
    var giantBrewing = false
    /// Two-finger double-tap on Home makes the usual drink.
    var magicTapUsual = true
    var progressTicks = false
    var dripWait = true
    var offlineQueue = true
    var cupPrewarm = false
    var waterReminder = false
    var milkFridgeReminder = true
    var tankWaterReminder = true
    var quietReconnect = true
    var settingsLock = false
    var leftOnReminder = true
    var followMachineProfile = true
    var locationSwitch = false
    /// What a coffee costs at the café, for "you saved".
    var cafePrice: Double = 15
    /// 0 automatic in Ramadan, 1 always on, 2 off.
    var ramadanMode = 0
    var lastSeenVersion = ""

    private static let key = "app.settings.v1"

    static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

extension AppSettings {
    /// Settings saved by an earlier version keep their values; new ones
    /// start at their defaults instead of resetting everything.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        linkKind = read(.linkKind, linkKind)
        confirmBeforeBrewing = read(.confirmBeforeBrewing, confirmBeforeBrewing)
        announcePhases = read(.announcePhases, announcePhases)
        announceProgress = read(.announceProgress, announceProgress)
        announceAlarms = read(.announceAlarms, announceAlarms)
        haptics = read(.haptics, haptics)
        speakWithoutVoiceOver = read(.speakWithoutVoiceOver, speakWithoutVoiceOver)
        hasCompletedOnboarding = read(.hasCompletedOnboarding, hasCompletedOnboarding)
        notifyWhenReady = read(.notifyWhenReady, notifyWhenReady)
        remindBrewingUnitWeekly = read(.remindBrewingUnitWeekly, remindBrewingUnitWeekly)
        remindCarafeDaily = read(.remindCarafeDaily, remindCarafeDaily)
        remindFilterMonthly = read(.remindFilterMonthly, remindFilterMonthly)
        caffeineLimitMg = read(.caffeineLimitMg, caffeineLimitMg)
        caffeineCutoffHour = read(.caffeineCutoffHour, caffeineCutoffHour)
        writeCaffeineToHealth = read(.writeCaffeineToHealth, writeCaffeineToHealth)
        preBrewReminders = read(.preBrewReminders, preBrewReminders)
        carafeCleanPrompt = read(.carafeCleanPrompt, carafeCleanPrompt)
        soundCues = read(.soundCues, soundCues)
        quantityTones = read(.quantityTones, quantityTones)
        simpleMode = read(.simpleMode, simpleMode)
        timeOfDayTheme = read(.timeOfDayTheme, timeOfDayTheme)
        weeklySummary = read(.weeklySummary, weeklySummary)
        predictiveCareReminders = read(.predictiveCareReminders, predictiveCareReminders)
        iCloudSync = read(.iCloudSync, iCloudSync)
        liveActivities = read(.liveActivities, liveActivities)
        hapticOnly = read(.hapticOnly, hapticOnly)
        brailleBrief = read(.brailleBrief, brailleBrief)
        speechVoiceID = read(.speechVoiceID, speechVoiceID)
        speechRate = read(.speechRate, speechRate)
        verbosity = read(.verbosity, verbosity)
        shakeForStatus = read(.shakeForStatus, shakeForStatus)
        giantBrewing = read(.giantBrewing, giantBrewing)
        magicTapUsual = read(.magicTapUsual, magicTapUsual)
        progressTicks = read(.progressTicks, progressTicks)
        dripWait = read(.dripWait, dripWait)
        offlineQueue = read(.offlineQueue, offlineQueue)
        cupPrewarm = read(.cupPrewarm, cupPrewarm)
        waterReminder = read(.waterReminder, waterReminder)
        milkFridgeReminder = read(.milkFridgeReminder, milkFridgeReminder)
        tankWaterReminder = read(.tankWaterReminder, tankWaterReminder)
        quietReconnect = read(.quietReconnect, quietReconnect)
        settingsLock = read(.settingsLock, settingsLock)
        leftOnReminder = read(.leftOnReminder, leftOnReminder)
        followMachineProfile = read(.followMachineProfile, followMachineProfile)
        locationSwitch = read(.locationSwitch, locationSwitch)
        cafePrice = read(.cafePrice, cafePrice)
        ramadanMode = read(.ramadanMode, ramadanMode)
        lastSeenVersion = read(.lastSeenVersion, lastSeenVersion)
    }
}

/// Tracks one drink from the moment it is ordered until it is in the cup.
struct BrewSession: Equatable, Identifiable {
    enum Outcome: Equatable { case running, finished, stopped, failed(String) }

    let id = UUID()
    let recipe: Recipe
    let startedAt: Date
    var activity: MachineActivity = .grinding
    var progress: Double = 0           // 0...1
    var outcome: Outcome = .running
    var sawMachineBusy = false
    var announcedMilestones: Set<Int> = []

    var isRunning: Bool { outcome == .running }

    /// Progress milestones (in percent) worth announcing, at most once each.
    mutating func milestonesToAnnounce() -> [Int] {
        let percent = Int(progress * 100)
        let due = [25, 50, 75].filter { percent >= $0 && !announcedMilestones.contains($0) }
        announcedMilestones.formUnion(due)
        return due
    }

    /// Bluetooth brewing: infer progress and completion from status polls.
    mutating func update(with snapshot: MachineSnapshot, now: Date = Date(), expectedSeconds: Double? = nil) {
        guard isRunning else { return }
        if snapshot.power == .busy {
            sawMachineBusy = true
            if snapshot.activity != .idle { activity = snapshot.activity }
            if let reported = snapshot.progress {
                progress = max(progress, Double(reported) / 100)
            } else {
                let expected = expectedSeconds ?? Double(max(recipe.estimatedSeconds, 1))
                let estimate = now.timeIntervalSince(startedAt) / max(expected, 1)
                progress = max(progress, min(0.95, estimate))
            }
        } else if snapshot.power == .ready, sawMachineBusy {
            progress = 1
            outcome = .finished
        } else if !sawMachineBusy, now.timeIntervalSince(startedAt) > 15 {
            outcome = .failed(L("brew.error.didNotStart"))
        }
        if isRunning, let blocking = snapshot.blockingAlarms.first, sawMachineBusy, snapshot.power != .busy {
            outcome = .failed(blocking.title)
        }
    }
}
