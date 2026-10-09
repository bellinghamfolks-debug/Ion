import SwiftUI

// MARK: - First setup

/// Setting up a machine step by step: name it, prepare it, test the water,
/// say whether a filter is fitted, and connect.
struct MachineSetupView: View {
    @Environment(AppModel.self) var model
    @Environment(\.dismiss) var dismiss
    @State var step = 0
    @State var record = MachineRecord(name: L("setup.defaultName"))
    @State var hasFilter = true
    @AccessibilityFocusState var titleFocused: Bool

    private let stepCount = 6

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L("setup.stepOf", step + 1, stepCount))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text(L("setup.step\(step + 1).title"))
                    .font(.display(.title, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
                Text(L("setup.step\(step + 1).body"))
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                content
                HStack(spacing: 12) {
                    if step > 0 {
                        Button(L("guide.previous")) { go(-1) }.buttonStyle(SecondaryButtonStyle())
                    }
                    if step < stepCount - 1 {
                        Button(L("guide.next")) { go(1) }.buttonStyle(PrimaryButtonStyle())
                    } else {
                        Button(L("setup.finish")) { finish() }.buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle(L("setup.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { titleFocused = true }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            MachineIllustration().frame(maxWidth: 220).frame(maxWidth: .infinity).accessibilityHidden(true)
        case 1:
            VStack(spacing: 12) {
                TextField(L("setup.name"), text: $record.name)
                    .padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                TextField(L("setup.model"), text: $record.model)
                    .padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                TextField(L("machineInfo.serial"), text: $record.serial)
                    .padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
            }
        case 2:
            VStack(spacing: 10) {
                guideLink(.fillWater)
                guideLink(.fillBeans)
                guideLink(.emptyContainers)
            }
        case 3:
            NavigationLink { HardnessTestView() } label: {
                NavigationRowCard(title: L("hardness.title"), subtitle: L("hardness.current", model.machineSettings.waterHardness), symbol: "testtube.2")
            }
            .buttonStyle(.plain)
        case 4:
            Toggle(L("setup.filter"), isOn: $hasFilter)
                .padding(14).card()
            guideLink(.waterFilter)
        default:
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent(L("settings.status"), value: model.connection.title)
                Button(L("setup.connectBluetooth")) { model.switchLink(to: .bluetooth); model.reconnect() }
                    .buttonStyle(PrimaryButtonStyle())
                Button(L("setup.useDemo")) { model.switchLink(to: .demo) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func guideLink(_ guide: MaintenanceGuideID) -> some View {
        NavigationLink { GuideView(guide: guide) } label: {
            NavigationRowCard(title: guide.title, subtitle: L("guide.duration", guide.minutes, guide.stepCount), symbol: guide.symbol)
        }
        .buttonStyle(.plain)
    }

    private func go(_ delta: Int) {
        step = max(0, min(stepCount - 1, step + delta))
        titleFocused = true
    }

    private func finish() {
        var saved = record
        saved.name = saved.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if saved.name.isEmpty { saved.name = L("setup.defaultName") }
        if saved.purchaseDate == nil { saved.purchaseDate = Date() }
        model.updateData { data in
            data.life.machines.append(saved)
            data.life.activeMachineID = saved.id
            data.life.usesWaterFilter = hasFilter
            if hasFilter { data.life.log(.waterFilter) }
        }
        Announcer.shared.success()
        Announcer.shared.announce(L("setup.done", saved.name))
        dismiss()
    }
}

// MARK: - Water hardness test

/// Dip the strip, wait a minute (counted aloud), count the red squares.
struct HardnessTestView: View {
    @Environment(AppModel.self) var model
    @State var endsAt: Date?
    @State var redSquares = 2
    @State var countdown: Task<Void, Never>?
    @State var saved = false

    private static let seconds = 60

    var body: some View {
        Form {
            Section {
                Text(L("hardness.step1"))
                Text(L("hardness.step2"))
                if let endsAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let left = max(0, Int(endsAt.timeIntervalSince(context.date).rounded(.up)))
                        Text(left > 0 ? L("hardness.waiting", left) : L("hardness.readNow"))
                            .font(.title2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                } else {
                    Button(L("hardness.dipped")) { startCountdown() }.bold()
                }
            } header: {
                Text(L("hardness.title"))
            }
            Section {
                Picker(L("hardness.redSquares"), selection: $redSquares) {
                    ForEach(0...4, id: \.self) { Text(L("hardness.squares", $0)).tag($0) }
                }
                LabeledContent(L("hardness.level"), value: L("hardness.\(Self.level(forRedSquares: redSquares))"))
                Button(L("hardness.apply")) {
                    let level = Self.level(forRedSquares: redSquares)
                    model.updateMachineSettings { $0.waterHardness = level }
                    model.logCare(.waterHardness)
                    saved = true
                    Announcer.shared.announce(L("hardness.saved", L("hardness.\(level)")))
                }
                .bold()
                if saved { Text(L("hardness.savedNote")).font(.footnote) }
            } footer: {
                Text(L("hardness.footer"))
            }
        }
        .tint(Theme.accent)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("hardness.title"))
        .onDisappear { countdown?.cancel() }
    }

    /// The strip's red squares give the machine's level 1…4.
    static func level(forRedSquares squares: Int) -> Int { max(1, min(4, squares)) }

    private func startCountdown() {
        endsAt = Date().addingTimeInterval(TimeInterval(Self.seconds))
        Announcer.shared.announce(L("hardness.started"))
        countdown?.cancel()
        countdown = Task {
            for mark in [30, 10, 0] {
                let wait = Double(Self.seconds - mark) - Date().timeIntervalSince(endsAt!.addingTimeInterval(-Double(Self.seconds)))
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                if Task.isCancelled { return }
                if mark == 0 {
                    Announcer.shared.success()
                    Announcer.shared.announce(L("hardness.readNow"), priority: .high)
                } else {
                    Announcer.shared.announce(L("hardness.waiting", mark))
                }
            }
        }
    }
}

// MARK: - My machines

struct MachinesView: View {
    @Environment(AppModel.self) var model
    @State var editing: MachineRecord?
    @State var settingUp = false

    var body: some View {
        List {
            Section {
                ForEach(model.data.life.machines) { machine in
                    let active = machine.id == model.data.life.activeMachine?.id
                    Button { switchTo(machine) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(machine.name).font(.headline).foregroundStyle(Theme.textPrimary)
                                Text(machine.model).font(.footnote).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            if active { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).accessibilityHidden(true) }
                        }
                    }
                    .accessibilityAddTraits(active ? .isSelected : [])
                    .accessibilityAction(named: Text(L("machineInfo.title"))) { editing = machine }
                    .swipeActions { Button(L("action.edit")) { editing = machine } }
                }
                .onDelete { offsets in model.updateData { $0.life.machines.remove(atOffsets: offsets) } }
            } footer: {
                Text(L("machines.footer"))
            }
            Section {
                Button { settingUp = true } label: { Label(L("machines.add"), systemImage: "plus") }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("machines.title"))
        .navigationDestination(isPresented: $settingUp) { MachineSetupView() }
        .sheet(item: $editing) { machine in
            MachineInfoEditor(machine: machine) { saved in
                model.updateData { data in
                    if let index = data.life.machines.firstIndex(where: { $0.id == saved.id }) { data.life.machines[index] = saved }
                }
            }
        }
    }

    /// Each machine remembers its Bluetooth identity; switching connects to it.
    private func switchTo(_ machine: MachineRecord) {
        guard machine.id != model.data.life.activeMachine?.id else { return }
        model.updateData { $0.life.activeMachineID = machine.id }
        if let id = machine.peripheralID {
            UserDefaults.standard.set(id, forKey: BluetoothMachineLink.rememberedPeripheralKey)
        } else {
            model.bluetoothLink?.forgetMachine()
        }
        if model.settings.linkKind == .bluetooth { model.reconnect() }
        Announcer.shared.announce(L("machines.switched", machine.name))
    }
}

/// Name, model, serial number, purchase date and warranty.
struct MachineInfoEditor: View {
    @Environment(\.dismiss) var dismiss
    @State var machine: MachineRecord
    let onSave: (MachineRecord) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("setup.name"), text: $machine.name)
                TextField(L("setup.model"), text: $machine.model)
                TextField(L("machineInfo.serial"), text: $machine.serial)
                DatePicker(L("machineInfo.purchased"), selection: Binding(get: { machine.purchaseDate ?? Date() },
                                                                          set: { machine.purchaseDate = $0 }),
                           in: ...Date(), displayedComponents: .date)
                Stepper(value: $machine.warrantyYears, in: 1...5) {
                    LabeledContent(L("machineInfo.warranty"), value: L("machineInfo.years", machine.warrantyYears))
                }
                if let ends = machine.warrantyEnds {
                    LabeledContent(L("machineInfo.warrantyEnds"), value: ends.formatted(date: .long, time: .omitted))
                    Text(machine.warrantyActive() == true ? L("machineInfo.underWarranty") : L("machineInfo.outOfWarranty"))
                        .font(.footnote)
                }
                if !machine.serial.isEmpty {
                    Button(L("machineInfo.copySerial")) {
                        UIPasteboard.general.string = machine.serial
                        Announcer.shared.announce(L("machineInfo.copied"))
                    }
                }
            }
            .navigationTitle(L("machineInfo.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("action.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L("action.save")) { onSave(machine); dismiss() } }
            }
        }
    }
}

// MARK: - Descaling with a live timer

struct DescaleRunView: View {
    @Environment(AppModel.self) var model

    var body: some View {
        let run = model.data.life.descale
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let run {
                    let stage = AppModel.descaleStages[run.stageIndex]
                    Text(L("descale.stageOf", run.stageIndex + 1, AppModel.descaleStages.count))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text(L(stage.key + ".title"))
                        .font(.display(.title, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(L(stage.key))
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let ends = run.stageEndsAt {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let left = max(0, Int(ends.timeIntervalSince(context.date)))
                            Text(left > 0 ? L("descale.left", left / 60, left % 60) : L("descale.stageReady"))
                                .font(.largeTitle.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .accessibilityLabel(left > 0 ? L("descale.left.spoken", max(1, (left + 59) / 60)) : L("descale.stageReady"))
                        }
                    } else {
                        Button(L("descale.startTimer", stage.minutes)) { model.startDescaleTimer() }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    Button(run.stageIndex + 1 >= AppModel.descaleStages.count ? L("descale.complete") : L("descale.nextStage")) {
                        model.advanceDescale()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button(L("descale.cancel"), role: .destructive) { model.cancelDescale() }
                        .buttonStyle(TextLinkButtonStyle())
                } else {
                    Text(L("descale.run.intro"))
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                    Button(L("descale.begin")) {
                        Task { await NotificationManager.shared.requestPermission() }
                        model.startDescale()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle(L("descale.run.title"))
    }
}

// MARK: - Care forecast, shopping list and log

struct CareForecastCard: View {
    @Environment(AppModel.self) var model

    var body: some View {
        let forecast = model.forecast
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: L("forecast.title"))
            ForEach(forecast.items) { item in
                HStack(spacing: 12) {
                    Image(systemName: item.task.guide.symbol)
                        .foregroundStyle(item.isSoon ? Theme.warning : Theme.accent)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.task.title).font(.headline).foregroundStyle(Theme.textPrimary)
                        Text(item.daysLeft == 0 ? L("forecast.now") : L("forecast.inDays", item.daysLeft, item.due.formatted(date: .abbreviated, time: .omitted)))
                            .font(.subheadline)
                            .foregroundStyle(item.isSoon ? Theme.warning : Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
            Text(L("forecast.basis", String(format: "%.1f", forecast.cupsPerDay)))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            Toggle(L("forecast.filter"), isOn: Binding(get: { model.data.life.usesWaterFilter },
                                                       set: { value in model.updateData { $0.life.usesWaterFilter = value } }))
            Toggle(L("forecast.remind"), isOn: Binding(get: { model.settings.predictiveCareReminders },
                                                       set: { value in model.updateSettings { $0.predictiveCareReminders = value } }))
            NavigationLink { ShoppingListView() } label: {
                NavigationRowCard(title: L("shopping.title"), subtitle: L("shopping.subtitle"), symbol: "cart")
            }
            .buttonStyle(.plain)
            NavigationLink { MaintenanceLogView() } label: {
                NavigationRowCard(title: L("log.title"), subtitle: L("log.subtitle"), symbol: "list.bullet.clipboard")
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .card()
        .tint(Theme.accent)
    }
}

struct ShoppingListView: View {
    @Environment(AppModel.self) var model
    @State var message: String?

    var body: some View {
        let entries = ShoppingList.entries(forecast: model.forecast, beans: model.data.beanProfiles, profiles: model.data.profiles)
        List {
            if entries.isEmpty {
                Text(L("shopping.empty")).foregroundStyle(Theme.textSecondary)
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title).font(.headline)
                    Text(entry.reason).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            if !entries.isEmpty {
                Section {
                    ShareLink(item: ShoppingList.text(entries)) { Label(L("shopping.share"), systemImage: "square.and.arrow.up") }
                    Button { addToReminders(entries) } label: { Label(L("shopping.reminders"), systemImage: "checklist") }
                    if let message { Text(message).font(.footnote) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("shopping.title"))
    }

    private func addToReminders(_ entries: [ShoppingList.Entry]) {
        Task {
            let added = await RemindersWriter.add(entries.map(\.title), listTitle: L("shopping.title"))
            message = added > 0 ? L("shopping.added", added) : L("shopping.denied")
            Announcer.shared.announce(message ?? "")
        }
    }
}

struct MaintenanceLogView: View {
    @Environment(AppModel.self) var model
    @State var adding = false
    @State var task: CareTask = .milkCarafe

    var body: some View {
        List {
            Section {
                Picker(L("log.task"), selection: $task) {
                    ForEach(CareTask.allCases) { Text($0.title).tag($0) }
                }
                Button(L("log.addNow")) { model.logCare(task) }
            } header: {
                Text(L("log.add"))
            }
            Section(L("log.history")) {
                if model.data.life.maintenanceLog.isEmpty {
                    Text(L("log.empty")).foregroundStyle(Theme.textSecondary)
                }
                ForEach(model.data.life.maintenanceLog) { entry in
                    LabeledContent(entry.task.title, value: entry.date.formatted(date: .abbreviated, time: .shortened))
                }
                .onDelete { offsets in model.updateData { $0.life.maintenanceLog.remove(atOffsets: offsets) } }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("log.title"))
    }
}

// MARK: - What does this signal mean?

/// Search the machine's messages and lights by the words on the display or
/// by describing what you hear or see.
struct SignalLookupView: View {
    @State var query = ""

    struct Signal: Identifiable {
        let id: String
        let title: String
        let advice: String
        let guide: MaintenanceGuideID?
        let words: String
    }

    static var all: [Signal] {
        let alarms = MachineAlarm.allCases.map { alarm in
            Signal(id: alarm.rawValue, title: alarm.title, advice: alarm.advice, guide: alarm.maintenanceGuide,
                   words: L("signal.alarm.\(alarm.rawValue).words"))
        }
        let extras = (1...SignalLookupView.extraCount).map { index in
            Signal(id: "extra\(index)", title: L("signal.extra.\(index).title"), advice: L("signal.extra.\(index).advice"),
                   guide: nil, words: L("signal.extra.\(index).words"))
        }
        return alarms + extras
    }

    static let extraCount = 8

    private var results: [Signal] {
        let needle = DrinkQuery.normalize(query)
        guard !needle.isEmpty else { return Self.all }
        let words = needle.split(separator: " ").map(String.init)
        return Self.all.filter { signal in
            let haystack = DrinkQuery.normalize(signal.title + " " + signal.advice + " " + signal.words)
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    var body: some View {
        List(results) { signal in
            VStack(alignment: .leading, spacing: 6) {
                Text(signal.title).font(.headline)
                Text(signal.advice).font(.body).foregroundStyle(Theme.textSecondary)
                if let guide = signal.guide {
                    NavigationLink { GuideView(guide: guide) } label: { Text(L("action.openGuide", guide.title)) }
                }
            }
            .padding(.vertical, 4)
        }
        .searchable(text: $query, prompt: Text(L("signal.search")))
        .overlay { if results.isEmpty { Text(L("signal.none")).foregroundStyle(Theme.textSecondary) } }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("signal.title"))
    }
}

// MARK: - Spoken tour of the machine

/// Where everything is, part by part, in words.
struct MachineTourView: View {
    @State var index = 0
    @AccessibilityFocusState var focused: Bool
    static let parts = ["front", "display", "spout", "hotWater", "milk", "beans", "tank", "tray", "grounds", "unit", "power"]

    var body: some View {
        let part = Self.parts[index]
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L("tour.stepOf", index + 1, Self.parts.count))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text(L("tour.\(part).title"))
                    .font(.display(.title, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($focused)
                Text(L("tour.\(part).body"))
                    .font(.title3)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button(L("guide.previous")) { move(-1) }.buttonStyle(SecondaryButtonStyle()).disabled(index == 0)
                    Button(L("guide.next")) { move(1) }.buttonStyle(PrimaryButtonStyle()).disabled(index == Self.parts.count - 1)
                }
                Text(L("tour.note")).font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle(L("tour.title"))
        .onAppear { focused = true }
    }

    private func move(_ delta: Int) {
        index = max(0, min(Self.parts.count - 1, index + delta))
        focused = true
    }
}
