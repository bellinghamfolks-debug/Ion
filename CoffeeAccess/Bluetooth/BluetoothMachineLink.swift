import CoreBluetooth
import Foundation

/// Talks to the machine over the ECAM Bluetooth protocol.
///
/// Connection: scan for the ECAM service (falling back to De'Longhi-looking
/// names), subscribe to the control characteristic, then poll the status
/// every couple of seconds. Commands are written one at a time.
@MainActor
final class BluetoothMachineLink: NSObject, MachineLink {
    let kind: MachineLinkKind = .bluetooth
    var onSnapshot: ((MachineSnapshot) -> Void)?
    var onConnection: ((ConnectionState) -> Void)?
    /// Every raw packet in and out, for the diagnostics log.
    var onTraffic: ((TrafficEntry) -> Void)?

    struct TrafficEntry: Identifiable, Equatable {
        let id = UUID()
        let date = Date()
        let outgoing: Bool
        let bytes: [UInt8]
    }

    static let rememberedPeripheralKey = "bluetooth.rememberedPeripheral"
    private let serviceID = CBUUID(string: ECAM.serviceUUID)
    private let characteristicID = CBUUID(string: ECAM.characteristicUUID)

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var assembler = ECAMAssembler()
    private var snapshot = MachineSnapshot()
    private var pollTask: Task<Void, Never>?
    private var scanFallbackTask: Task<Void, Never>?
    private var waiters: [UInt8: CheckedContinuation<[UInt8], Error>] = [:]
    private var writeChain: Task<Void, Never>?
    private var wantsConnection = false

    func connect() {
        wantsConnection = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else {
            startConnecting()
        }
    }

    func disconnect() {
        wantsConnection = false
        pollTask?.cancel()
        scanFallbackTask?.cancel()
        central?.stopScan()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        characteristic = nil
        failWaiters()
        onConnection?(.disconnected)
    }

    func forgetMachine() {
        UserDefaults.standard.removeObject(forKey: Self.rememberedPeripheralKey)
        disconnect()
    }

    func refresh() {
        Task { try? await send(ECAMCommands.monitor, expecting: ECAM.Command.monitor.rawValue) }
    }

    func powerOn() async throws {
        try await send(ECAMCommands.powerOn, expecting: nil)
        refreshSoon()
    }

    func brew(_ recipe: Recipe) async throws {
        let packet = try ECAMCommands.brew(recipe)
        if snapshot.power == .off { throw MachineError.notReady([]) }
        let blocking = snapshot.blockingAlarms
        guard blocking.isEmpty else { throw MachineError.notReady(blocking) }
        try await send(packet, expecting: nil)
        refreshSoon()
    }

    func stop(_ beverage: BeverageID) async throws {
        try await send(try ECAMCommands.stop(beverage), expecting: nil)
        refreshSoon()
    }

    func powerOff() async throws {
        try await send(ECAMCommands.powerOff, expecting: nil)
        refreshSoon()
    }

    func apply(_ settings: MachineSettings) async throws {
        for command in ECAMCommands.commands(for: settings) {
            try await send(command, expecting: nil)
        }
    }

    func readSettings(into settings: MachineSettings) async -> MachineSettings? {
        guard let reply = try? await send(ECAMCommands.readParameter(.switches), expecting: 0x95),
              let parameter = ECAMReplies.parameter(reply) else { return nil }
        var updated = settings
        updated.applySwitchMask(parameter.value)
        return updated
    }

    func readCounters() async -> MachineCounters {
        var counters = MachineCounters()
        for range in MachineCounters.requestRanges {
            let command = ECAMCommands.statistics(start: range.start, count: range.count)
            if let reply = try? await send(command, expecting: ECAM.Command.statistics.rawValue) {
                counters.merge(ECAMReplies.statistics(reply))
            }
        }
        return counters
    }

    func readProfileNames() async -> [Int: String] {
        guard let reply = try? await send(ECAMCommands.profileNames, expecting: ECAM.Command.profileNames.rawValue) else { return [:] }
        return ECAMReplies.profileNames(reply)
    }

    func setClock(_ date: Date) async throws {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        try await send(ECAMCommands.setClock(hour: parts.hour ?? 0, minute: parts.minute ?? 0), expecting: nil)
    }

    func selectProfile(_ profile: Int) async throws {
        try await send(ECAMCommands.selectProfile(profile), expecting: nil)
        snapshot.activeProfile = profile
        onSnapshot?(snapshot)
    }

    // MARK: Sending

    /// Writes a packet; when `expecting` is set, waits for the reply with
    /// that command id (3 s timeout).
    @discardableResult
    private func send(_ packet: [UInt8], expecting responseID: UInt8?) async throws -> [UInt8] {
        guard let peripheral, let characteristic, peripheral.state == .connected else { throw MachineError.notConnected }
        let previous = writeChain
        let write = Task { @MainActor in
            await previous?.value
            onTraffic?(TrafficEntry(outgoing: true, bytes: packet))
            let type: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
            peripheral.writeValue(Data(packet), for: characteristic, type: type)
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        writeChain = write
        guard let responseID else {
            await write.value
            return []
        }
        if let stale = waiters.removeValue(forKey: responseID) { stale.resume(throwing: MachineError.noResponse) }
        return try await withCheckedThrowingContinuation { continuation in
            waiters[responseID] = continuation
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if let waiter = self.waiters.removeValue(forKey: responseID) {
                    waiter.resume(throwing: MachineError.noResponse)
                }
            }
        }
    }

    private func failWaiters() {
        let pending = waiters
        waiters.removeAll()
        pending.values.forEach { $0.resume(throwing: MachineError.notConnected) }
    }

    private func refreshSoon() {
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            refresh()
        }
    }

    private func handle(packet: [UInt8]) {
        onTraffic?(TrafficEntry(outgoing: false, bytes: packet))
        let id = packet[2]
        if let monitor = ECAMMonitor(packet: packet) {
            snapshot = monitor.applying(to: snapshot)
            onSnapshot?(snapshot)
        }
        if let waiter = waiters.removeValue(forKey: id) { waiter.resume(returning: packet) }
    }

    // MARK: Connecting

    private func startConnecting() {
        guard wantsConnection, let central, central.state == .poweredOn else { return }
        if let remembered = UserDefaults.standard.string(forKey: Self.rememberedPeripheralKey),
           let uuid = UUID(uuidString: remembered),
           let known = central.retrievePeripherals(withIdentifiers: [uuid]).first {
            connect(to: known)
            return
        }
        if let alreadyConnected = central.retrieveConnectedPeripherals(withServices: [serviceID]).first {
            connect(to: alreadyConnected)
            return
        }
        onConnection?(.searching)
        central.scanForPeripherals(withServices: [serviceID])
        // Some machines do not advertise the service; widen the search.
        scanFallbackTask?.cancel()
        scanFallbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled, self.peripheral == nil, central.isScanning else { return }
            central.stopScan()
            central.scanForPeripherals(withServices: nil)
        }
    }

    private func connect(to peripheral: CBPeripheral) {
        central?.stopScan()
        scanFallbackTask?.cancel()
        self.peripheral = peripheral
        peripheral.delegate = self
        onConnection?(.connecting(peripheral.name ?? L("machine.generic.name")))
        central?.connect(peripheral)
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await self.send(ECAMCommands.monitor, expecting: ECAM.Command.monitor.rawValue)
                // Signal strength for the diagnostics and "move closer" advice.
                if self.peripheral?.state == .connected { self.peripheral?.readRSSI() }
                let interval: UInt64 = self.snapshot.power == .busy ? 1_000_000_000 : 2_500_000_000
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }
}

extension BluetoothMachineLink: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            switch central.state {
            case .poweredOn: startConnecting()
            case .poweredOff: onConnection?(.failed(L("bluetooth.off")))
            case .unauthorized: onConnection?(.failed(L("bluetooth.unauthorized")))
            case .unsupported: onConnection?(.failed(L("bluetooth.unsupported")))
            default: break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
            let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            guard services.contains(serviceID) || MachineNameHeuristics.looksLikeDeLonghi(name) else { return }
            connect(to: peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            peripheral.discoverServices([serviceID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            self.peripheral = nil
            onConnection?(.failed(error?.localizedDescription ?? L("bluetooth.connect.failed")))
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            pollTask?.cancel()
            characteristic = nil
            failWaiters()
            onConnection?(.disconnected)
            if wantsConnection {
                // Try again quietly; the machine may have gone to sleep.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if self.wantsConnection, let known = self.peripheral { self.connect(to: known) }
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard let service = peripheral.services?.first(where: { $0.uuid == serviceID }) else {
                onConnection?(.failed(L("bluetooth.no.ecam.service")))
                central?.cancelPeripheralConnection(peripheral)
                self.peripheral = nil
                return
            }
            peripheral.discoverCharacteristics([characteristicID], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            guard let characteristic = service.characteristics?.first(where: { $0.uuid == characteristicID }) else {
                onConnection?(.failed(L("bluetooth.no.ecam.service")))
                return
            }
            self.characteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
            UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.rememberedPeripheralKey)
            onConnection?(.connected(peripheral.name ?? L("machine.generic.name")))
            startPolling()
            // Keep the machine's clock right, as the official app does.
            Task { try? await self.setClock(Date()) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        let value = RSSI.intValue
        MainActor.assumeIsolated {
            // 127 means "not available".
            guard error == nil, value != 127, snapshot.rssi != value else { return }
            snapshot.rssi = value
            onSnapshot?(snapshot)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard let data = characteristic.value else { return }
            for packet in assembler.append([UInt8](data)) { handle(packet: packet) }
        }
    }
}

enum MachineNameHeuristics {
    /// De'Longhi machines usually advertise as "D…" model codes or "ECAM…".
    static func looksLikeDeLonghi(_ name: String?) -> Bool {
        guard let name = name?.lowercased(), !name.isEmpty else { return false }
        let markers = ["ecam", "delonghi", "de'longhi", "eletta", "dinamica", "primadonna", "magnifica", "rivelia", "perfetto"]
        if markers.contains(where: name.contains) { return true }
        // Model-code style names such as "D1541234".
        return name.count >= 6 && name.hasPrefix("d") && name.dropFirst().allSatisfy(\.isNumber)
    }
}
