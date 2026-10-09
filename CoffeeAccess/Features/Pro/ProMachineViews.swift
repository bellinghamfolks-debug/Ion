import SwiftUI
import UIKit
import Vision

/// Every alarm the machine raised, most frequent first, then by date.
struct AlarmHistoryView: View {
    @Environment(AppModel.self) var model

    var body: some View {
        let events = model.data.life.pro.alarmHistory
        let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())
        ProForm(title: L("screen.alarmHistory")) {
            Section(L("alarmHistory.month")) {
                let counts = AlarmStats.counts(events, since: monthAgo)
                if counts.isEmpty { Text(L("alarmHistory.none")).foregroundStyle(Theme.textSecondary) }
                ForEach(counts) { count in
                    LabeledContent(count.alarm.title, value: L("alarmHistory.times", count.count))
                }
            }
            Section(L("alarmHistory.recent")) {
                ForEach(events.prefix(50)) { event in
                    LabeledContent(event.alarm.title, value: event.date.formatted(date: .abbreviated, time: .shortened))
                }
            }
            if !events.isEmpty {
                Section {
                    Button(L("alarmHistory.clear"), role: .destructive) { model.updateData { $0.life.pro.alarmHistory = [] } }
                }
            }
        }
    }
}

/// A text report for the service centre, shared from the share sheet.
struct ServiceReportView: View {
    @Environment(AppModel.self) var model

    var body: some View {
        let text = ServiceReport.text(machine: model.data.life.activeMachine, counters: model.counters,
                                      log: model.data.life.maintenanceLog, alarms: model.data.life.pro.alarmHistory,
                                      appVersion: AppVersion.full)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("report.intro")).font(.body).foregroundStyle(Theme.textSecondary)
                ShareLink(item: text) { Label(L("report.share"), systemImage: "square.and.arrow.up") }
                    .buttonStyle(PrimaryButtonStyle())
                Text(text)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle(L("screen.serviceReport"))
        .task { await model.refreshCounters() }
    }
}

/// Before moving the machine or leaving it unused for a while.
struct TravelChecklistView: View {
    @State var done: Set<Int> = []

    var body: some View {
        ProForm(title: L("screen.travel")) {
            Section {
                ForEach(Array(TravelChecklist.items.enumerated()), id: \.offset) { index, item in
                    Button {
                        if done.contains(index) { done.remove(index) } else { done.insert(index) }
                        Announcer.shared.tick()
                    } label: {
                        HStack(alignment: .top) {
                            Image(systemName: done.contains(index) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(Theme.accent).accessibilityHidden(true)
                            Text(item).foregroundStyle(Theme.textPrimary)
                        }
                    }
                    .accessibilityAddTraits(done.contains(index) ? .isSelected : [])
                }
            } footer: { Text(L("travel.footer", done.count, TravelChecklist.count)) }
        }
    }
}

/// Descaler, filters and milk cleaner at home; used ones are subtracted
/// automatically when the care is logged.
struct SuppliesView: View {
    @Environment(AppModel.self) var model

    var body: some View {
        ProForm(title: L("screen.supplies")) {
            Section {
                Stepper(value: model.proBinding(\.supplies.descaler), in: 0...20) {
                    LabeledContent(L("supplies.descaler"), value: "\(model.data.life.pro.supplies.descaler)")
                }
                Stepper(value: model.proBinding(\.supplies.filters), in: 0...20) {
                    LabeledContent(L("supplies.filters"), value: "\(model.data.life.pro.supplies.filters)")
                }
                Stepper(value: model.proBinding(\.supplies.milkCleaner), in: 0...20) {
                    LabeledContent(L("supplies.milkCleaner"), value: "\(model.data.life.pro.supplies.milkCleaner)")
                }
            } footer: { Text(L("supplies.footer")) }
            Section {
                NavigationLink { ShoppingListView() } label: { Label(L("shopping.title"), systemImage: "cart") }
            }
        }
    }
}

/// The milk carton, the tank water and where the water comes from.
struct MilkAndWaterView: View {
    @Environment(AppModel.self) var model

    var body: some View {
        let pro = model.data.life.pro
        ProForm(title: L("screen.milk")) {
            Section {
                Picker(L("milk.profileDefault"), selection: Binding(
                    get: { pro.profileMilk[model.activeProfile.id] ?? .whole },
                    set: { value in model.updateData { $0.life.pro.profileMilk[model.activeProfile.id] = value } })) {
                    ForEach(MilkType.allCases) { Text($0.title).tag($0) }
                }
                if let opened = pro.milkOpenedAt {
                    LabeledContent(L("milk.openedOn"), value: opened.formatted(date: .abbreviated, time: .omitted))
                    if let left = MilkFreshness.daysLeft(openedAt: opened, shelfDays: pro.milkShelfDays) {
                        Text(left < 0 ? L("milk.expired") : L("milk.daysLeft", left)).font(.footnote)
                    }
                }
                Stepper(value: model.proBinding(\.milkShelfDays), in: 1...14) {
                    LabeledContent(L("milk.shelf"), value: L("milk.days", pro.milkShelfDays))
                }
                Button(L("milk.openedToday")) { model.openedNewMilk() }
                TextField(L("milk.price"), value: model.proBinding(\.milkPricePerLitre), format: .number).keyboardType(.decimalPad)
            } header: { Text(L("milk.title")) } footer: { Text(L("milk.footer")) }

            Section {
                Picker(L("water.source"), selection: model.proBinding(\.waterSource)) {
                    ForEach(WaterSource.allCases) { Text($0.title).tag($0) }
                }
                if let filled = pro.tankFilledAt {
                    LabeledContent(L("tank.filledOn"), value: filled.formatted(date: .abbreviated, time: .shortened))
                }
                Button(L("tank.filledNow")) {
                    model.updateData { $0.life.pro.tankFilledAt = Date() }
                    Announcer.shared.announce(L("announce.saved"))
                }
                Toggle(L("tank.reminder"), isOn: model.binding(\.tankWaterReminder))
                Toggle(L("milkFridge.toggle"), isOn: model.binding(\.milkFridgeReminder))
            } header: { Text(L("water.title")) } footer: { Text(L("water.footer")) }
        }
    }
}

/// App profile names next to the machine's. Renaming on the machine is done
/// on its own screen; the app explains how rather than sending a command
/// that is not documented.
struct ProfileNamesView: View {
    @Environment(AppModel.self) var model
    @State var machineNames: [Int: String] = [:]
    @State var loading = false

    var body: some View {
        ProForm(title: L("screen.profileNames")) {
            Section {
                ForEach(ProfileNameCheck.rows(app: model.data.profiles, machine: machineNames)) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("profileNames.app", row.id, row.app)).font(.headline)
                        Text(row.machine.map { L("profileNames.machine", $0) } ?? L("profileNames.unknown"))
                            .font(.footnote).foregroundStyle(row.matches ? Theme.textSecondary : Theme.warning)
                        if !row.matches { Text(L("profileNames.differs")).font(.footnote.weight(.semibold)).foregroundStyle(Theme.warning) }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Section {
                Button(loading ? L("profileNames.reading") : L("profileNames.read")) {
                    loading = true
                    Task {
                        machineNames = await model.link.readProfileNames()
                        loading = false
                        Announcer.shared.announce(machineNames.isEmpty ? L("profileNames.none") : L("profileNames.done"))
                    }
                }
                .disabled(!model.connection.isConnected || loading)
                Button(L("profileNames.useMachine")) {
                    for (id, name) in machineNames { model.renameProfile(id, to: name) }
                    Announcer.shared.announce(L("announce.saved"))
                }
                .disabled(machineNames.isEmpty)
            } footer: { Text(L("profileNames.howTo")) }
        }
    }
}

/// Bluetooth signal in words with advice, when the link reports it.
struct SignalStrengthRow: View {
    let rssi: Int?

    var body: some View {
        if let rssi {
            let strength = SignalStrength(rssi: rssi)
            HStack(spacing: 12) {
                Image(systemName: "wifi", variableValue: Double(strength.bars) / 3)
                    .foregroundStyle(strength == .weak ? Theme.warning : Theme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("signal.strength.label", strength.title)).font(.headline).foregroundStyle(Theme.textPrimary)
                    if strength == .weak { Text(L("signal.strength.advice")).font(.footnote).foregroundStyle(Theme.textSecondary) }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(L("signal.dbm", rssi))
        }
    }
}

/// Experimental: a photo of the machine's touch screen with a finger near
/// it says which word is under the fingertip and what is around it.
struct TouchscreenGuideView: View {
    @State var picking = false
    @State var result: String?
    @State var working = false

    var body: some View {
        ProForm(title: L("screen.touchGuide")) {
            Section {
                Text(L("touchGuide.intro"))
                Button { picking = true } label: { Label(L("touchGuide.take"), systemImage: "hand.point.up.left") }
                if working { ProgressView() }
                if let result { Text(result).font(.headline) }
            } footer: { Text(L("experimental.footer")) }
        }
        .sheet(isPresented: $picking) {
            ImagePicker { image in
                picking = false
                guard let image else { return }
                working = true
                Task {
                    let text = await TouchscreenReader.describe(image)
                    working = false
                    result = text
                    Announcer.shared.announce(text, priority: .high)
                }
            }
            .ignoresSafeArea()
        }
    }
}

enum TouchscreenReader {
    struct Word: Equatable {
        var text: String
        var center: CGPoint
    }

    /// The fingertip from hand pose, the words from text recognition, both
    /// in Vision's normalized coordinates (origin bottom-left).
    static func describe(_ image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return L("touchGuide.failed") }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let text = VNRecognizeTextRequest()
                text.recognitionLevel = .accurate
                text.automaticallyDetectsLanguage = true
                let hand = VNDetectHumanHandPoseRequest()
                hand.maximumHandCount = 1
                do {
                    try VNImageRequestHandler(cgImage: cgImage, orientation: .up).perform([text, hand])
                } catch {
                    continuation.resume(returning: L("touchGuide.failed"))
                    return
                }
                let words = (text.results ?? []).compactMap { observation -> Word? in
                    guard let string = observation.topCandidates(1).first?.string else { return nil }
                    let box = observation.boundingBox
                    return Word(text: string, center: CGPoint(x: box.midX, y: box.midY))
                }
                let tip = (try? hand.results?.first?.recognizedPoint(.indexTip)).flatMap { $0.confidence > 0.3 ? $0.location : nil }
                continuation.resume(returning: sentence(words: words, fingertip: tip))
            }
        }
    }

    static func sentence(words: [Word], fingertip: CGPoint?) -> String {
        guard !words.isEmpty else { return L("touchGuide.noText") }
        guard let tip = fingertip else {
            return L("touchGuide.noFinger", words.prefix(6).map(\.text).joined(separator: L("list.separator")))
        }
        func distance(_ word: Word) -> CGFloat { hypot(word.center.x - tip.x, word.center.y - tip.y) }
        let sorted = words.sorted { distance($0) < distance($1) }
        let under = sorted[0]
        var parts = [L("touchGuide.under", under.text)]
        for neighbour in sorted.dropFirst().prefix(3) {
            let dx = neighbour.center.x - under.center.x, dy = neighbour.center.y - under.center.y
            let direction: String
            if abs(dx) > abs(dy) {
                direction = dx > 0 ? L("direction.right") : L("direction.left")
            } else {
                direction = dy > 0 ? L("direction.up") : L("direction.down")
            }
            parts.append(L("touchGuide.neighbour", neighbour.text, direction))
        }
        return parts.joined(separator: L("sentence.separator"))
    }
}

/// "Use my location for this machine", for switching machines on arrival.
struct MachineLocationRow: View {
    @Binding var machine: MachineRecord
    @State var working = false

    var body: some View {
        Section {
            if machine.latitude != nil {
                Text(L("location.saved")).font(.footnote)
                Button(L("location.clear"), role: .destructive) { machine.latitude = nil; machine.longitude = nil }
            }
            Button(working ? L("location.reading") : L("location.useHere")) {
                working = true
                Task {
                    if let here = await LocationSwitcher.shared.currentLocation() {
                        machine.latitude = here.coordinate.latitude
                        machine.longitude = here.coordinate.longitude
                        Announcer.shared.announce(L("location.done"))
                    } else {
                        Announcer.shared.announce(L("location.denied"), priority: .high)
                    }
                    working = false
                }
            }
            .disabled(working)
        } footer: { Text(L("location.footer")) }
    }
}
