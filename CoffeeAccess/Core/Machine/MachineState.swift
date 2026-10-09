import Foundation

enum MachinePower: String, Codable, Equatable {
    case off, turningOn, shuttingDown, ready, busy, descaling, rinsing, unknown
}

/// What the machine is doing right now, beyond on/off.
enum MachineActivity: String, Codable, Equatable {
    case idle, grinding, brewingCoffee, dispensingMilk, dispensingWater, steaming
    case rinsing, cleaningMilk, descaling, heating, changingFilter
}

/// Conditions the learner should hear about. Ordered by how urgently they
/// block a drink, most urgent first.
enum MachineAlarm: String, CaseIterable, Codable, Identifiable {
    case waterTankMissing, waterTankEmpty, wasteContainerMissing, wasteContainerFull
    case dripTrayMissing, beansEmpty, beanHopperMissing, groundTooFine, doorOpen
    case descaleNeeded, replaceFilter, milkCarafeNeedsCleaning, serviceNeeded, hardwareFault

    var id: String { rawValue }

    /// Alarms that stop any drink until the learner acts.
    var blocksBrewing: Bool {
        switch self {
        case .descaleNeeded, .replaceFilter, .milkCarafeNeedsCleaning: return false
        default: return true
        }
    }

    var maintenanceGuide: MaintenanceGuideID? {
        switch self {
        case .descaleNeeded: return .descaling
        case .replaceFilter: return .waterFilter
        case .milkCarafeNeedsCleaning: return .milkCarafe
        case .wasteContainerFull, .wasteContainerMissing, .dripTrayMissing: return .emptyContainers
        case .waterTankEmpty, .waterTankMissing: return .fillWater
        case .beansEmpty, .beanHopperMissing: return .fillBeans
        default: return nil
        }
    }
}

enum MilkAccessory: String, Codable, Equatable {
    case none, carafe, carafeCleaning, hotWaterSpout, unknown
}

struct MachineSnapshot: Equatable {
    var power: MachinePower = .unknown
    var activity: MachineActivity = .idle
    var alarms: [MachineAlarm] = []
    var accessory: MilkAccessory = .unknown
    /// Dispensing progress 0...100 when the machine reports it.
    var progress: Int?
    var activeProfile: Int = 1
    var updatedAt = Date()
    /// Bluetooth signal strength (dBm) when the link reports it.
    var rssi: Int?

    var isReadyToBrew: Bool { power == .ready && !alarms.contains(where: \.blocksBrewing) }
    var blockingAlarms: [MachineAlarm] { alarms.filter(\.blocksBrewing) }
}

enum ConnectionState: Equatable {
    case disconnected
    case searching
    case connecting(String)
    case connected(String)
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

enum MachineLinkKind: String, Codable, CaseIterable, Identifiable {
    case bluetooth, demo
    var id: String { rawValue }
}

enum MachineError: Error, Equatable {
    case notConnected
    case notReady([MachineAlarm])
    case unsupportedOverBluetooth(BeverageID)
    case noResponse
    case bluetoothUnavailable(String)
}
