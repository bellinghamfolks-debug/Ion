import SwiftUI
import UIKit

/// Machine check: scan, pick the machine, inspect, share the report.
struct DiagnosticsView: View {
    @Environment(AppModel.self) var model
    @State var diagnostics = BluetoothDiagnostics()
    @State var pausedLink = false

    var body: some View {
        List {
            Section {
                Text(L("diagnostics.intro"))
                    .font(.body)
                Button {
                    pauseLinkIfNeeded()
                    diagnostics.startScan()
                } label: {
                    Label(diagnostics.phase == .scanning ? L("diagnostics.scanning") : L("diagnostics.scan"),
                          systemImage: "dot.radiowaves.left.and.right")
                }
                .disabled(diagnostics.phase == .scanning || isInspecting)
            }

            if !statusText.isEmpty {
                Section(L("diagnostics.result")) {
                    Text(statusText)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                }
            }

            if !diagnostics.devices.isEmpty {
                Section(L("diagnostics.devices")) {
                    ForEach(diagnostics.sortedDevices) { device in
                        Button {
                            diagnostics.inspect(device)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(device.name).font(.headline).foregroundStyle(Theme.textPrimary)
                                Text(deviceDetail(device)).font(.footnote).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .disabled(isInspecting)
                        .accessibilityHint(L("diagnostics.inspect.hint"))
                    }
                }
            }

            if !diagnostics.services.isEmpty {
                Section(L("diagnostics.services")) {
                    ForEach(diagnostics.services, id: \.uuid) { service in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(service.uuid == ECAM.serviceUUID ? L("diagnostics.ecamService") : service.uuid)
                                .font(.subheadline.weight(.semibold))
                            ForEach(service.characteristics, id: \.uuid) { characteristic in
                                Text("\(characteristic.uuid) · \(characteristic.properties)\(characteristic.value.map { " · \($0)" } ?? "")")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            if model.settings.linkKind == .bluetooth, !model.traffic.isEmpty {
                Section(L("diagnostics.traffic")) {
                    ForEach(model.traffic.suffix(30).reversed()) { entry in
                        Text("\(entry.outgoing ? "→" : "←") \(ECAM.hex(entry.bytes))")
                            .font(.caption.monospaced())
                    }
                }
            }

            Section {
                ShareLink(item: fullReport) {
                    Label(L("diagnostics.share"), systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.string = fullReport
                    Announcer.shared.announce(L("diagnostics.copied"))
                } label: {
                    Label(L("diagnostics.copy"), systemImage: "doc.on.doc")
                }
                if pausedLink {
                    Button(L("action.reconnect")) {
                        pausedLink = false
                        model.reconnect()
                    }
                }
            }
        }
        .navigationTitle(L("diagnostics.title"))
        .onDisappear {
            diagnostics.stopScan()
            if pausedLink { model.reconnect() }
        }
    }

    private var isInspecting: Bool {
        if case .inspecting = diagnostics.phase { return true }
        return false
    }

    private var statusText: String {
        switch diagnostics.phase {
        case .idle: return ""
        case .scanning: return L("diagnostics.scanning")
        case .inspecting(let name): return L("diagnostics.inspecting", name)
        case .finished, .failed: return diagnostics.verdict
        }
    }

    private func deviceDetail(_ device: BluetoothDiagnostics.Device) -> String {
        var parts = [L("diagnostics.signal", device.rssi)]
        if device.advertisesECAM { parts.append(L("diagnostics.ecamAdvertised")) }
        else if device.likelyMachine { parts.append(L("diagnostics.likelyMachine")) }
        return parts.joined(separator: " · ")
    }

    private var fullReport: String {
        var text = diagnostics.report
        if !model.traffic.isEmpty {
            text += "\n\nLive link traffic:\n"
            text += model.traffic.suffix(60).map { "\($0.outgoing ? "->" : "<-") \(ECAM.hex($0.bytes))" }.joined(separator: "\n")
        }
        return text
    }

    /// The machine accepts one Bluetooth connection at a time.
    private func pauseLinkIfNeeded() {
        guard model.settings.linkKind == .bluetooth, !pausedLink else { return }
        model.link.disconnect()
        pausedLink = true
    }
}
