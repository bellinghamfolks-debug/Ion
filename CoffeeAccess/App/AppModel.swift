import Foundation
import Observation

/// The app's single source of truth: profiles and favorites, the machine
/// link, live machine status and the drink being prepared.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var data: AppData
    private(set) var settings: AppSettings
    private(set) var snapshot = MachineSnapshot()
    private(set) var connection: ConnectionState = .disconnected
    private(set) var session: BrewSession?
    private(set) var traffic: [BluetoothMachineLink.TrafficEntry] = []
    /// Bumped on every demo-engine change so demo level gauges refresh.
    private(set) var demoRevision = 0
    private(set) var machineSettings: MachineSettings
    private(set) var counters = MachineCounters()
    private(set) var countersUpdatedAt: Date?
    var lastMessage: String?

    private(set) var link: MachineLink
    private let store: AppDataStore
    private let announcer = Announcer.shared
    private var started = false

    var activeProfile: UserProfile { data.activeProfile }
    var demoLink: DemoMachineLink? { link as? DemoMachineLink }
    var bluetoothLink: BluetoothMachineLink? { link as? BluetoothMachineLink }

    init(store: AppDataStore = .standard, settings: AppSettings = .load()) {
        self.store = store
        self.settings = settings
        self.data = store.load() ?? AppData.initial(names: (1...AppData.profileCount).map { L("profile.default.name", $0) })
        self.link = Self.makeLink(settings.linkKind)
        self.machineSettings = Self.loadMachineSettings()
        applyFeedbackSettings()
    }

    /// Every change to profiles, favorites or history goes through here so
    /// it is saved immediately.
    func updateData(_ change: (inout AppData) -> Void) {
        var copy = data
        change(&copy)
        guard copy != data else { return }
        data = copy
        persist()
    }

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        var copy = settings
        change(&copy)
        guard copy != settings else { return }
        let old = settings
        settings = copy
        settings.save()
        applyFeedbackSettings()
        let notifications = NotificationManager.shared
        let reminders: [(NotificationManager.Reminder, Bool, Bool)] = [
            (.brewingUnitWeekly, old.remindBrewingUnitWeekly, copy.remindBrewingUnitWeekly),
            (.carafeDaily, old.remindCarafeDaily, copy.remindCarafeDaily),
            (.filterMonthly, old.remindFilterMonthly, copy.remindFilterMonthly),
        ]
        let turnedOn = reminders.contains { !$0.1 && $0.2 } || (!old.notifyWhenReady && copy.notifyWhenReady)
        Task {
            if turnedOn { await notifications.requestPermission() }
            for (reminder, before, after) in reminders where before != after {
                notifications.schedule(reminder, enabled: after)
            }
        }
    }

    func initialRecipe(for route: DrinkRoute) -> Recipe {
        switch route {
        case .beverage(let beverage): return data.recipe(for: beverage)
        case .toGo(let beverage): return data.recipe(for: beverage, toGo: true)
        case .favorite(let favorite): return favorite.normalized()
        case .newRecipe(let beverage): return data.recipe(for: beverage)
        }
    }

    func start() {
        guard !started else { return }
        started = true
        wire(link)
        link.connect()
    }

    // MARK: Machine link

    func switchLink(to kind: MachineLinkKind) {
        guard kind != link.kind else { return }
        link.disconnect()
        updateSettings { $0.linkKind = kind }
        snapshot = MachineSnapshot()
        session = nil
        link = Self.makeLink(kind)
        wire(link)
        link.connect()
    }

    func reconnect() {
        link.disconnect()
        link.connect()
    }

    private static func makeLink(_ kind: MachineLinkKind) -> MachineLink {
        switch kind {
        case .demo: return DemoMachineLink()
        case .bluetooth: return BluetoothMachineLink()
        }
    }

    private func wire(_ link: MachineLink) {
        link.onSnapshot = { [weak self] snapshot in self?.receive(snapshot) }
        link.onConnection = { [weak self] state in self?.receive(state) }
        if let demo = link as? DemoMachineLink {
            demo.onEvent = { [weak self] event in self?.receive(event) }
        }
        if let bluetooth = link as? BluetoothMachineLink {
            bluetooth.onTraffic = { [weak self] entry in
                guard let self else { return }
                traffic.append(entry)
                if traffic.count > 200 { traffic.removeFirst(traffic.count - 200) }
            }
        }
    }

    // MARK: Commands

    func powerOn() async {
        do {
            try await link.powerOn()
            announcer.announce(L("announce.turningOn"))
        } catch {
            report(error)
        }
    }

    /// Starts a drink. Returns false (and announces why) when it cannot.
    @discardableResult
    func brew(_ recipe: Recipe) async -> Bool {
        guard session?.isRunning != true else {
            report(message: L("brew.error.busy"))
            return false
        }
        let recipe = recipe.normalized()
        do {
            try await link.brew(recipe)
            session = BrewSession(recipe: recipe, startedAt: Date())
            announcer.tick()
            announcer.announce(L("announce.brewStarted", recipe.displayName), priority: .high)
            return true
        } catch {
            report(error)
            return false
        }
    }

    func powerOff() async {
        do {
            try await link.powerOff()
            announcer.announce(L("announce.turningOff"))
        } catch {
            report(error)
        }
    }

    /// Saves the machine settings and sends them to the machine.
    func updateMachineSettings(_ change: (inout MachineSettings) -> Void) {
        var copy = machineSettings
        change(&copy)
        guard copy != machineSettings else { return }
        machineSettings = copy
        if let data = try? JSONEncoder().encode(copy) { UserDefaults.standard.set(data, forKey: Self.machineSettingsKey) }
        guard connection.isConnected else { return }
        Task {
            do {
                try await link.apply(copy)
                announcer.announce(L("announce.settingsSent"))
            } catch {
                report(error)
            }
        }
    }

    /// Reads back what the machine reports (sounds, cup light, energy saving).
    func syncMachineSettings() async {
        guard connection.isConnected, let read = await link.readSettings(into: machineSettings) else { return }
        machineSettings = read
    }

    func refreshCounters() async {
        guard connection.isConnected else { return }
        let read = await link.readCounters()
        if !read.isEmpty {
            counters = read
            countersUpdatedAt = Date()
        }
    }

    /// Copies the profile names stored on the machine into the app.
    @discardableResult
    func importProfileNames() async -> Int {
        guard connection.isConnected else { return 0 }
        let names = await link.readProfileNames()
        for (id, name) in names { renameProfile(id, to: name) }
        return names.count
    }

    func setGuestMode(_ enabled: Bool) {
        updateData { $0.guestMode = enabled }
        announcer.announce(enabled ? L("announce.guestOn") : L("announce.guestOff"))
    }

    func selectBean(_ id: UUID?) {
        updateData { $0.activeBeanID = id }
        if let bean = data.activeBean {
            announcer.announce(L("announce.beanSelected", bean.name, bean.recommendedGrind))
        }
    }

    private static let machineSettingsKey = "machine.settings.v1"

    private static func loadMachineSettings() -> MachineSettings {
        guard let data = UserDefaults.standard.data(forKey: machineSettingsKey),
              let settings = try? JSONDecoder().decode(MachineSettings.self, from: data) else { return MachineSettings() }
        return settings
    }

    func stopBrewing() async {
        guard let session, session.isRunning else { return }
        do {
            try await link.stop(session.recipe.beverage)
            finishSession(.stopped)
        } catch {
            report(error)
        }
    }

    func dismissSession() {
        if session?.isRunning == false { session = nil }
    }

    func selectProfile(_ id: Int) {
        guard data.profiles.contains(where: { $0.id == id }) else { return }
        updateData { $0.activeProfileID = id }
        announcer.announce(L("announce.profileSelected", data.activeProfile.name))
        if connection.isConnected {
            Task { try? await link.selectProfile(id) }
        }
    }

    func renameProfile(_ id: Int, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = data.profiles.firstIndex(where: { $0.id == id }) else { return }
        updateData { $0.profiles[index].name = String(trimmed.prefix(20)) }
    }

    func setProfileColor(_ id: Int, colorIndex: Int) {
        guard let index = data.profiles.firstIndex(where: { $0.id == id }) else { return }
        updateData { $0.profiles[index].colorIndex = colorIndex % Theme.profileColors.count }
    }

    func demo(_ change: (inout DemoMachineEngine) -> [DemoMachineEngine.Event]) {
        demoLink?.perform(change)
        demoRevision += 1
    }

    // MARK: Updates from the link

    private func receive(_ state: ConnectionState) {
        let old = connection
        connection = state
        guard old != state else { return }
        switch state {
        case .connected(let name):
            announcer.announce(L("announce.connected", name))
            Task {
                await syncMachineSettings()
                await refreshCounters()
            }
        case .failed(let reason): announcer.announce(reason)
        case .disconnected where old.isConnected: announcer.announce(L("announce.disconnected"))
        default: break
        }
    }

    private func receive(_ new: MachineSnapshot) {
        let old = snapshot
        snapshot = new
        if settings.announceAlarms {
            let added = new.alarms.filter { !old.alarms.contains($0) }
            if !added.isEmpty {
                if settings.notifyWhenReady { NotificationManager.shared.alarms(added) }
                announcer.warning()
                announcer.announce(L("announce.alarm", added.map(\.title).joined(separator: L("list.separator"))), priority: .high)
            }
            if !old.blockingAlarms.isEmpty, new.blockingAlarms.isEmpty, new.power == .ready {
                announcer.announce(L("announce.alarmsCleared"))
            }
        }
        if old.power == .turningOn, new.power == .ready {
            announcer.success()
            announcer.announce(L("announce.ready"))
        }
        guard var current = session, current.isRunning else { return }
        // Demo sessions get phases from engine events; only progress here.
        if link.kind == .demo {
            if let progress = new.progress {
                current.progress = max(current.progress, Double(progress) / 100)
                session = current
                announceMilestones()
            }
            return
        }
        // Bluetooth sessions are tracked entirely from status polls.
        let previousActivity = current.activity
        current.update(with: new)
        session = current
        if current.activity != previousActivity { announcePhase(current.activity) }
        announceMilestones()
        switch current.outcome {
        case .finished: finishSession(.finished)
        case .failed(let reason): finishSession(.failed(reason))
        default: break
        }
    }

    private func receive(_ event: DemoMachineEngine.Event) {
        demoRevision += 1
        guard var current = session, current.isRunning else { return }
        switch event {
        case .phase(let activity):
            current.activity = activity
            session = current
            announcePhase(activity)
        case .finished:
            finishSession(.finished)
        case .stopped:
            finishSession(.stopped)
        default:
            break
        }
    }

    private func announcePhase(_ activity: MachineActivity) {
        guard settings.announcePhases, let text = activity.phaseAnnouncement else { return }
        announcer.announce(text)
    }

    private func announceMilestones() {
        guard settings.announceProgress, var current = session else { return }
        let due = current.milestonesToAnnounce()
        session = current
        if let last = due.last { announcer.announce(L("announce.progress", last)) }
    }

    private func finishSession(_ outcome: BrewSession.Outcome) {
        guard var current = session, current.isRunning else { return }
        current.outcome = outcome
        if outcome == .finished { current.progress = 1 }
        session = current
        updateData { $0.record(current.recipe, completed: outcome == .finished) }
        switch outcome {
        case .finished:
            announcer.success()
            announcer.announce(L("announce.brewFinished", current.recipe.displayName), priority: .high)
            if settings.notifyWhenReady { NotificationManager.shared.drinkFinished(current.recipe) }
        case .stopped:
            announcer.announce(L("announce.brewStopped"))
        case .failed(let reason):
            announcer.warning()
            announcer.announce(L("announce.brewFailed", reason), priority: .high)
        case .running:
            break
        }
    }

    // MARK: Errors and persistence

    private func report(_ error: Error) {
        report(message: (error as? MachineError)?.message ?? error.localizedDescription)
    }

    private func report(message: String) {
        lastMessage = message
        announcer.warning()
        announcer.announce(message, priority: .high)
    }

    private func persist() {
        do { try store.save(data) } catch { lastMessage = L("error.saveFailed") }
    }

    private func applyFeedbackSettings() {
        announcer.hapticsEnabled = settings.haptics
        announcer.speakWithoutVoiceOver = settings.speakWithoutVoiceOver
    }
}

extension MachineError {
    var message: String {
        switch self {
        case .notConnected: return L("error.notConnected")
        case .notReady(let alarms):
            if alarms.isEmpty { return L("error.machineOff") }
            return L("error.notReady", alarms.map(\.title).joined(separator: L("list.separator")))
        case .unsupportedOverBluetooth(let beverage): return L("error.unsupportedBluetooth", beverage.name)
        case .noResponse: return L("error.noResponse")
        case .bluetoothUnavailable(let reason): return reason
        }
    }
}
