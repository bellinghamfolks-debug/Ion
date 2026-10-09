import LocalAuthentication
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Everything the app keeps, in one file the person owns.
struct BackupFile: Codable {
    var format = 1
    var createdAt = Date()
    var appVersion = AppVersion.full
    var data: AppData
    var settings: AppSettings
}

/// Backup and restore, the history as a spreadsheet.
struct BackupView: View {
    @Environment(AppModel.self) var model
    @State var importing = false
    @State var pending: BackupFile?
    @State var message: String?

    var body: some View {
        ProForm(title: L("screen.backup")) {
            Section {
                if let url = backupURL() {
                    ShareLink(item: url) { Label(L("backup.export"), systemImage: "square.and.arrow.up") }
                }
                Button { importing = true } label: { Label(L("backup.import"), systemImage: "square.and.arrow.down") }
                if let message { Text(message).font(.footnote) }
            } footer: { Text(L("backup.footer")) }
            Section {
                if let url = ExportWriter.write(HistoryExport.csv(data: model.data), name: "coffee-history.csv") {
                    ShareLink(item: url) { Label(L("csv.export"), systemImage: "tablecells") }
                }
            } footer: { Text(L("csv.footer")) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let file = try? JSONDecoder.coffee.decode(BackupFile.self, from: data),
                  file.data.profiles.count == AppData.profileCount else {
                message = L("backup.invalid")
                Announcer.shared.announce(L("backup.invalid"), priority: .high)
                return
            }
            pending = file
        }
        .confirmationDialog(L("backup.confirm"), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible, presenting: pending) { file in
            Button(L("backup.restore"), role: .destructive) { restore(file) }
            Button(L("action.cancel"), role: .cancel) { pending = nil }
        } message: { file in
            Text(L("backup.confirm.detail", file.createdAt.formatted(date: .abbreviated, time: .shortened), file.appVersion))
        }
    }

    private func backupURL() -> URL? {
        let file = BackupFile(data: model.data, settings: model.settings)
        guard let data = try? JSONEncoder.coffee.encode(file) else { return nil }
        let day = Date().formatted(.iso8601.year().month().day())
        return ExportWriter.write(data, name: "coffee-backup-\(day).json")
    }

    private func restore(_ file: BackupFile) {
        model.updateData { $0 = file.data }
        var settings = file.settings
        settings.hasCompletedOnboarding = true
        model.updateSettings { $0 = settings }
        pending = nil
        message = L("backup.restored")
        Announcer.shared.announce(L("backup.restored"))
    }
}

/// Fix the history: remove a cup recorded by mistake, or mark one spilled
/// so it no longer counts as caffeine.
struct HistoryEditorView: View {
    @Environment(AppModel.self) var model

    var body: some View {
        let history = model.activeProfile.history.prefix(200)
        let spilled = Set(model.data.life.pro.spilled)
        ProForm(title: L("screen.historyEditor")) {
            Section {
                ForEach(Array(history)) { record in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.recipe.displayName).font(.headline).strikethrough(spilled.contains(record.id))
                        Text([record.date.formatted(date: .abbreviated, time: .shortened),
                              record.completed ? "" : L("history.notFinished"),
                              spilled.contains(record.id) ? L("history.spilled") : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAction(named: Text(spilled.contains(record.id) ? L("history.unspill") : L("history.spill"))) { toggleSpilled(record) }
                    .accessibilityAction(named: Text(L("action.delete"))) { delete(record) }
                    .swipeActions {
                        Button(L("action.delete"), role: .destructive) { delete(record) }
                        Button(spilled.contains(record.id) ? L("history.unspill") : L("history.spill")) { toggleSpilled(record) }
                    }
                }
                if history.isEmpty { Text(L("history.empty")).foregroundStyle(Theme.textSecondary) }
            } footer: { Text(L("history.footer")) }
        }
    }

    private func toggleSpilled(_ record: BrewRecord) {
        model.updateData { data in
            if data.life.pro.spilled.contains(record.id) {
                data.life.pro.spilled.removeAll { $0 == record.id }
            } else {
                data.life.pro.spilled.append(record.id)
                if data.life.pro.spilled.count > 500 { data.life.pro.spilled.removeFirst(data.life.pro.spilled.count - 500) }
            }
        }
        Announcer.shared.announce(L("announce.saved"))
    }

    private func delete(_ record: BrewRecord) {
        model.updateData { data in
            var profile = data.activeProfile
            profile.history.removeAll { $0.id == record.id }
            data.activeProfile = profile
            data.life.ratings[record.id] = nil
            data.life.pro.spilled.removeAll { $0 == record.id }
        }
        Announcer.shared.announce(L("announce.deleted", record.recipe.displayName))
    }
}

/// What the app keeps and where, with buttons to delete it.
struct PrivacyDashboardView: View {
    @Environment(AppModel.self) var model
    @State var confirm: Wipe?

    enum Wipe: String, Identifiable { case history, location, everything; var id: String { rawValue } }

    var body: some View {
        let data = model.data
        let cups = data.profiles.reduce(0) { $0 + $1.history.count }
        let placed = data.life.machines.filter { $0.latitude != nil }.count
        ProForm(title: L("screen.privacy")) {
            Section {
                LabeledContent(L("privacy.cups"), value: "\(cups)")
                LabeledContent(L("privacy.favorites"), value: "\(data.profiles.reduce(0) { $0 + $1.favorites.count })")
                LabeledContent(L("privacy.beans"), value: "\(data.beanProfiles.count)")
                LabeledContent(L("privacy.household"), value: "\(data.life.household.count)")
                LabeledContent(L("privacy.notes"), value: "\(data.life.ratings.values.filter { !$0.note.isEmpty }.count)")
            } header: { Text(L("privacy.onDevice")) } footer: { Text(L("privacy.onDevice.footer")) }
            Section {
                LabeledContent(L("privacy.icloud"), value: model.settings.iCloudSync ? L("privacy.on") : L("privacy.off"))
                LabeledContent(L("privacy.health"), value: model.settings.writeCaffeineToHealth ? L("privacy.on") : L("privacy.off"))
                LabeledContent(L("privacy.location"), value: model.settings.locationSwitch ? L("privacy.locationOn", placed) : L("privacy.off"))
                LabeledContent(L("privacy.camera"), value: L("privacy.cameraValue"))
                LabeledContent(L("privacy.servers"), value: L("privacy.serversValue"))
            } header: { Text(L("privacy.sharing")) } footer: { Text(L("privacy.sharing.footer")) }
            Section {
                Button(L("privacy.wipeHistory"), role: .destructive) { confirm = .history }
                Button(L("privacy.wipeLocation"), role: .destructive) { confirm = .location }.disabled(placed == 0)
                Button(L("privacy.wipeAll"), role: .destructive) { confirm = .everything }
            }
        }
        .confirmationDialog(L("privacy.confirm"), isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible, presenting: confirm) { wipe in
            Button(L("privacy.delete"), role: .destructive) { perform(wipe) }
            Button(L("action.cancel"), role: .cancel) { confirm = nil }
        }
    }

    private func perform(_ wipe: Wipe) {
        model.updateData { data in
            switch wipe {
            case .history:
                for index in data.profiles.indices { data.profiles[index].history = [] }
                data.life.ratings = [:]
                data.life.pro.spilled = []
                data.life.pro.memberCups = []
            case .location:
                for index in data.life.machines.indices {
                    data.life.machines[index].latitude = nil
                    data.life.machines[index].longitude = nil
                }
            case .everything:
                data = AppData.initial(names: (1...AppData.profileCount).map { L("profile.default.name", $0) })
            }
        }
        if wipe == .location { model.updateSettings { $0.locationSwitch = false } }
        confirm = nil
        Announcer.shared.announce(L("privacy.deleted"))
    }
}

/// Settings behind Face ID, Touch ID or the passcode, so children cannot
/// change them.
struct SettingsLockGate<Content: View>: View {
    @Environment(AppModel.self) var model
    @Environment(\.scenePhase) var scenePhase
    @State var unlocked = false
    @State var failed = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        if !model.settings.settingsLock || unlocked {
            content()
                .onChange(of: scenePhase) { _, phase in if phase == .background { unlocked = false } }
        } else {
            VStack(spacing: 20) {
                Image(systemName: "lock.fill").font(.system(size: 48)).foregroundStyle(Theme.accent).accessibilityHidden(true)
                Text(L("settingsLock.title")).font(.display(.title2, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Text(L("settingsLock.body")).multilineTextAlignment(.center).foregroundStyle(Theme.textSecondary)
                Button(L("settingsLock.unlock")) { unlock() }.buttonStyle(PrimaryButtonStyle())
                if failed { Text(L("settingsLock.failed")).font(.footnote).foregroundStyle(Theme.danger) }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .screenBackground()
        }
    }

    private func unlock() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode on the device: nothing to check against.
            unlocked = true
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: L("settingsLock.reason")) { success, _ in
            Task { @MainActor in
                unlocked = success
                failed = !success
            }
        }
    }
}
