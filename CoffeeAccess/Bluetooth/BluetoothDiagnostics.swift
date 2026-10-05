import CoreBluetooth
import Foundation
import Observation
import UIKit

/// The "machine check": finds nearby Bluetooth devices, inspects the one the
/// learner picks (services, characteristics, readable values) and, when the
/// ECAM service is present, asks the machine for its status. The result is a
/// plain-text report that can be shared, so the protocol of a new model can
/// be confirmed without guessing.
@MainActor
@Observable
final class BluetoothDiagnostics: NSObject {
    struct Device: Identifiable, Equatable {
        let id: UUID
        var name: String
        var rssi: Int
        var serviceUUIDs: [String]
        var manufacturerData: String
        var connectable: Bool
        var advertisesECAM: Bool { serviceUUIDs.contains(ECAM.serviceUUID) }
        var likelyMachine: Bool { advertisesECAM || MachineNameHeuristics.looksLikeDeLonghi(name) }
    }

    struct CharacteristicInfo: Equatable {
        let uuid: String
        let properties: String
        var value: String?
    }

    struct ServiceInfo: Equatable {
        let uuid: String
        var characteristics: [CharacteristicInfo]
    }

    enum Phase: Equatable {
        case idle, scanning, inspecting(String), finished, failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var devices: [Device] = []
    private(set) var services: [ServiceInfo] = []
    private(set) var inspectedName: String?
    private(set) var ecamStatus: String?
    private(set) var log: [String] = []

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var target: CBPeripheral?
    @ObservationIgnored private var pendingServices = 0
    @ObservationIgnored private var pendingReads = 0
    @ObservationIgnored private var assembler = ECAMAssembler()
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var wantsScan = false
    @ObservationIgnored private var ecamProbeStarted = false

    var sortedDevices: [Device] {
        devices.sorted { lhs, rhs in
            if lhs.likelyMachine != rhs.likelyMachine { return lhs.likelyMachine }
            return lhs.rssi > rhs.rssi
        }
    }

    func startScan(seconds: Double = 12) {
        devices = []
        services = []
        ecamStatus = nil
        inspectedName = nil
        log = []
        wantsScan = true
        phase = .scanning
        note("scan.start")
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else if central?.state == .poweredOn {
            beginScanning()
        }
        scanTask?.cancel()
        scanTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, self.phase == .scanning else { return }
            self.stopScan()
        }
    }

    func stopScan() {
        wantsScan = false
        central?.stopScan()
        if phase == .scanning { phase = .finished }
        note("scan.stop devices=\(devices.count)")
    }

    func inspect(_ device: Device) {
        guard let peripheral = peripherals[device.id], let central else { return }
        stopScan()
        services = []
        ecamStatus = nil
        inspectedName = device.name
        target = peripheral
        ecamProbeStarted = false
        pendingServices = 0
        pendingReads = 0
        peripheral.delegate = self
        phase = .inspecting(device.name)
        note("connect \(device.name)")
        central.connect(peripheral)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            if case .inspecting = self.phase { self.finishInspection(error: L("diagnostics.timeout")) }
        }
    }

    // MARK: Report

    var report: String {
        var lines: [String] = []
        let info = Bundle.main.infoDictionary
        lines.append("Coffee Access diagnostics")
        lines.append("App \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?")), iOS \(UIDevice.current.systemVersion), \(UIDevice.current.model)")
        lines.append("Date \(Date().formatted(.iso8601))")
        lines.append("")
        lines.append("Devices found: \(devices.count)")
        for device in sortedDevices {
            var line = "- \(device.name) rssi=\(device.rssi) connectable=\(device.connectable)"
            if !device.serviceUUIDs.isEmpty { line += " services=\(device.serviceUUIDs.joined(separator: ","))" }
            if !device.manufacturerData.isEmpty { line += " mfr=\(device.manufacturerData)" }
            if device.likelyMachine { line += " [likely machine]" }
            lines.append(line)
        }
        if let inspectedName {
            lines.append("")
            lines.append("Inspected: \(inspectedName)")
            for service in services {
                lines.append("  service \(service.uuid)\(service.uuid == ECAM.serviceUUID ? " [ECAM]" : "")")
                for characteristic in service.characteristics {
                    var line = "    char \(characteristic.uuid) [\(characteristic.properties)]"
                    if let value = characteristic.value { line += " = \(value)" }
                    lines.append(line)
                }
            }
            lines.append("ECAM status: \(ecamStatus ?? "not available")")
        }
        lines.append("")
        lines.append("Log:")
        lines.append(contentsOf: log.suffix(80))
        return lines.joined(separator: "\n")
    }

    /// One-sentence verdict for the screen and VoiceOver.
    var verdict: String {
        if let ecamStatus, !ecamStatus.isEmpty, ecamStatus != "no reply" { return L("diagnostics.verdict.ecamWorks") }
        if services.contains(where: { $0.uuid == ECAM.serviceUUID }) { return L("diagnostics.verdict.ecamSilent") }
        if inspectedName != nil, phase == .finished { return L("diagnostics.verdict.noEcam") }
        if case .failed(let reason) = phase { return reason }
        if phase == .finished, devices.isEmpty { return L("diagnostics.verdict.nothingFound") }
        if phase == .finished, !devices.contains(where: \.likelyMachine) { return L("diagnostics.verdict.noMachineName") }
        return ""
    }

    // MARK: Internals

    private func beginScanning() {
        guard wantsScan, let central else { return }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func note(_ text: String) {
        log.append("\(Date().formatted(.dateTime.hour().minute().second())) \(text)")
    }

    private func finishInspection(error: String? = nil) {
        if let target { central?.cancelPeripheralConnection(target) }
        target = nil
        if let error {
            note("error \(error)")
            phase = .failed(error)
        } else {
            phase = .finished
        }
        Announcer.shared.announce(verdict.isEmpty ? L("diagnostics.done") : verdict, priority: .high)
    }

    private func checkInspectionComplete(_ peripheral: CBPeripheral) {
        guard pendingServices == 0, pendingReads == 0, !ecamProbeStarted else { return }
        ecamProbeStarted = true
        if let ecam = peripheral.services?.first(where: { $0.uuid == CBUUID(string: ECAM.serviceUUID) })?
            .characteristics?.first(where: { $0.uuid == CBUUID(string: ECAM.characteristicUUID) }) {
            note("ecam.subscribe")
            peripheral.setNotifyValue(true, for: ecam)
            let packet = ECAMCommands.monitor
            note("tx \(ECAM.hex(packet))")
            peripheral.writeValue(Data(packet), for: ecam, type: ecam.properties.contains(.write) ? .withResponse : .withoutResponse)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard case .inspecting = self.phase else { return }
                if self.ecamStatus == nil { self.ecamStatus = "no reply" }
                self.finishInspection()
            }
        } else {
            finishInspection()
        }
    }

    private static func describe(_ properties: CBCharacteristicProperties) -> String {
        var names: [String] = []
        if properties.contains(.read) { names.append("read") }
        if properties.contains(.write) { names.append("write") }
        if properties.contains(.writeWithoutResponse) { names.append("writeNoResp") }
        if properties.contains(.notify) { names.append("notify") }
        if properties.contains(.indicate) { names.append("indicate") }
        return names.joined(separator: ",")
    }

    private static func describe(_ data: Data) -> String {
        let bytes = [UInt8](data)
        let hex = ECAM.hex(bytes)
        if let text = String(data: data, encoding: .utf8),
           !text.isEmpty, text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7F }) {
            return "\"\(text)\" (\(hex))"
        }
        return hex
    }
}

extension BluetoothDiagnostics: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            note("bt.state \(central.state.rawValue)")
            switch central.state {
            case .poweredOn: beginScanning()
            case .poweredOff: phase = .failed(L("bluetooth.off"))
            case .unauthorized: phase = .failed(L("bluetooth.unauthorized"))
            case .unsupported: phase = .failed(L("bluetooth.unsupported"))
            default: break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? L("diagnostics.unnamed")
            let uuids = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString)
            let manufacturer = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data).map { ECAM.hex([UInt8]($0)) } ?? ""
            let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? false
            peripherals[peripheral.identifier] = peripheral
            let device = Device(id: peripheral.identifier, name: name, rssi: RSSI.intValue, serviceUUIDs: uuids,
                                manufacturerData: manufacturer, connectable: connectable)
            if let index = devices.firstIndex(where: { $0.id == device.id }) {
                devices[index] = device
            } else {
                devices.append(device)
                if device.likelyMachine {
                    note("found likely machine \(name)")
                    Announcer.shared.announce(L("diagnostics.foundMachine", name))
                }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            note("connected")
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            finishInspection(error: error?.localizedDescription ?? L("bluetooth.connect.failed"))
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            let found = peripheral.services ?? []
            note("services \(found.count)")
            services = found.map { ServiceInfo(uuid: $0.uuid.uuidString, characteristics: []) }
            pendingServices = found.count
            if found.isEmpty { finishInspection() }
            found.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            let characteristics = service.characteristics ?? []
            if let index = services.firstIndex(where: { $0.uuid == service.uuid.uuidString }) {
                services[index].characteristics = characteristics.map {
                    CharacteristicInfo(uuid: $0.uuid.uuidString, properties: Self.describe($0.properties))
                }
            }
            for characteristic in characteristics where characteristic.properties.contains(.read)
                && characteristic.uuid != CBUUID(string: ECAM.characteristicUUID) && pendingReads < 24 {
                pendingReads += 1
                peripheral.readValue(for: characteristic)
            }
            pendingServices -= 1
            checkInspectionComplete(peripheral)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            if characteristic.uuid == CBUUID(string: ECAM.characteristicUUID) {
                guard let data = characteristic.value else { return }
                note("rx \(ECAM.hex([UInt8](data)))")
                for packet in assembler.append([UInt8](data)) {
                    if let monitor = ECAMMonitor(packet: packet) {
                        let snapshot = monitor.applying(to: MachineSnapshot())
                        let alarms = snapshot.alarms.map(\.rawValue).joined(separator: ",")
                        ecamStatus = "state=\(monitor.state) sub=\(monitor.subState) power=\(snapshot.power.rawValue) alarms=[\(alarms)] raw=\(ECAM.hex(packet))"
                        finishInspection()
                    } else {
                        ecamStatus = "packet \(ECAM.hex(packet))"
                    }
                }
                return
            }
            let value = characteristic.value.map(Self.describe) ?? (error.map { "error: \($0.localizedDescription)" } ?? "")
            for serviceIndex in services.indices {
                if let index = services[serviceIndex].characteristics.firstIndex(where: { $0.uuid == characteristic.uuid.uuidString }) {
                    services[serviceIndex].characteristics[index].value = value
                }
            }
            pendingReads = max(0, pendingReads - 1)
            checkInspectionComplete(peripheral)
        }
    }
}
