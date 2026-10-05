import SwiftUI

/// The machine's own settings menu, reachable without its touchscreen.
/// Every change is sent to the machine straight away when connected.
struct MachineSettingsView: View {
    @Environment(AppModel.self) var model
    @State var confirmStandby = false

    private var settings: MachineSettings { model.machineSettings }

    var body: some View {
        Form {
            if !model.connection.isConnected {
                Section {
                    Label(L("machineSettings.offline"), systemImage: "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(Theme.warning)
                }
            }

            Section {
                Picker(L("machineSettings.hardness"), selection: binding(\.waterHardness)) {
                    ForEach(MachineSettings.hardnessRange, id: \.self) { level in
                        Text(WaterHardness.title(level)).tag(level)
                    }
                }
                NavigationLink(L("machineSettings.hardness.test")) { GuideView(guide: .waterHardness) }
            } header: {
                Text(L("machineSettings.water"))
            } footer: {
                Text(L("machineSettings.hardness.footer"))
            }

            Section(L("machineSettings.temperature")) {
                Picker(L("machineSettings.temperature"), selection: binding(\.waterTemperature)) {
                    ForEach(MachineSettings.waterTemperatureRange, id: \.self) { level in
                        Text(WaterTemperatureLevel.title(level)).tag(level)
                    }
                }
            }

            Section {
                Picker(L("machineSettings.autoOff"), selection: binding(\.autoOff)) {
                    ForEach(MachineSettings.AutoOff.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Toggle(L("machineSettings.energySaving"), isOn: binding(\.energySaving))
            } header: {
                Text(L("machineSettings.power"))
            } footer: {
                Text(L("machineSettings.energySaving.footer"))
            }

            Section(L("machineSettings.comfort")) {
                Toggle(L("machineSettings.cupLight"), isOn: binding(\.cupLight))
                Toggle(L("machineSettings.sounds"), isOn: binding(\.sounds))
            }

            Section {
                Button(L("machineSettings.syncClock")) {
                    Task {
                        try? await model.link.setClock(Date())
                        Announcer.shared.announce(L("announce.clockSet"))
                    }
                }
                .disabled(!model.connection.isConnected)
                Button(L("machineSettings.importNames")) {
                    Task {
                        let count = await model.importProfileNames()
                        Announcer.shared.announce(count > 0 ? L("announce.namesImported", count) : L("announce.namesNone"))
                    }
                }
                .disabled(!model.connection.isConnected)
                Button(L("machineSettings.standby"), role: .destructive) { confirmStandby = true }
                    .disabled(!model.connection.isConnected || model.snapshot.power == .off)
            } header: {
                Text(L("machineSettings.tools"))
            } footer: {
                Text(L("machineSettings.standby.footer"))
            }
        }
        .tint(Theme.accent)
        .navigationTitle(L("machineSettings.title"))
        .task { await model.syncMachineSettings() }
        .confirmationDialog(L("machineSettings.standby.confirm"), isPresented: $confirmStandby, titleVisibility: .visible) {
            Button(L("machineSettings.standby"), role: .destructive) { Task { await model.powerOff() } }
            Button(L("action.cancel"), role: .cancel) {}
        }
    }

    private func binding<Value: Equatable>(_ keyPath: WritableKeyPath<MachineSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.machineSettings[keyPath: keyPath] },
            set: { value in model.updateMachineSettings { $0[keyPath: keyPath] = value } }
        )
    }
}
