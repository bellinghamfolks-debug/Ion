import Foundation

/// Builds outbound ECAM commands. Byte layouts follow traffic captured from
/// the official app on real machines (see ECAMPacket.swift for sources); the
/// unit tests pin the captured packets byte for byte.
enum ECAMCommands {
    enum Ingredient: UInt8 {
        case temperature = 0x00
        case coffee = 0x01
        case taste = 0x02
        case dueXPer = 0x08
        case milk = 0x09
        case inversion = 0x0C
        case hotWater = 0x0F
        case accessory = 0x1C

        var isWide: Bool { self == .coffee || self == .milk || self == .hotWater }
    }

    /// Final byte of a beverage command. Captured app traffic always ends
    /// with 0x06 ("prepare"), with or without milk-first.
    static let prepareTasteType: UInt8 = 0x06

    static let monitor = ECAM.packet([ECAM.Command.monitor.rawValue, 0x0F])
    static let powerOn = ECAM.packet([ECAM.Command.appControl.rawValue, 0x0F, 0x02, 0x01])

    static func encode(_ ingredient: Ingredient, _ value: Int) -> [UInt8] {
        let clamped = max(0, min(value, ingredient.isWide ? 0xFFFF : 0xFF))
        if ingredient.isWide {
            return [ingredient.rawValue, UInt8(clamped >> 8), UInt8(clamped & 0xFF)]
        }
        return [ingredient.rawValue, UInt8(clamped)]
    }

    /// Ingredient list for a recipe, in the order the official app sends it.
    static func ingredients(for recipe: Recipe) -> [UInt8] {
        let recipe = recipe.normalized()
        var bytes: [UInt8] = []
        if let coffee = recipe.coffeeML { bytes += encode(.coffee, coffee) }
        if let milk = recipe.milkSeconds { bytes += encode(.milk, milk) }
        if let aroma = recipe.aroma { bytes += encode(.taste, aroma.rawValue) }
        if recipe.beverage == .espresso || recipe.double == true { bytes += encode(.dueXPer, recipe.double == true ? 1 : 0) }
        if let water = recipe.waterML { bytes += encode(.hotWater, water) }
        if recipe.beverage == .hotWater { bytes += encode(.accessory, 1) }
        if let temperature = recipe.temperature { bytes += encode(.temperature, temperature.rawValue) }
        if recipe.spec.supportsMilkFirst { bytes += encode(.inversion, recipe.milkFirst ? 1 : 0) }
        return bytes
    }

    static func brew(_ recipe: Recipe) throws -> [UInt8] {
        guard let code = recipe.spec.ecamCode else { throw MachineError.unsupportedOverBluetooth(recipe.beverage) }
        var payload: [UInt8] = [ECAM.Command.beverage.rawValue, 0xF0, code, 0x01]
        payload += ingredients(for: recipe)
        payload.append(prepareTasteType)
        return ECAM.packet(payload)
    }

    static func stop(_ beverage: BeverageID) throws -> [UInt8] {
        guard let code = beverage.spec.ecamCode else { throw MachineError.unsupportedOverBluetooth(beverage) }
        return ECAM.packet([ECAM.Command.beverage.rawValue, 0xF0, code, 0x02, prepareTasteType])
    }

    static func selectProfile(_ profile: Int) -> [UInt8] {
        ECAM.packet([ECAM.Command.profileSelect.rawValue, 0xF0, UInt8(max(1, min(profile, 4)))])
    }

    static func readRecipe(profile: Int, beverage: BeverageID) -> [UInt8]? {
        guard let code = beverage.spec.ecamCode else { return nil }
        return ECAM.packet([ECAM.Command.recipeRead.rawValue, 0xF0, UInt8(max(1, min(profile, 4))), code])
    }
}

/// Parsed MonitorV2 (0x75) status packet.
struct ECAMMonitor: Equatable {
    let accessoryCode: UInt8
    let switches: UInt16
    let alarmBits: UInt32
    let state: UInt8
    let subState: UInt8
    let progress: UInt8

    init?(packet: [UInt8]) {
        guard packet.count >= 14, packet[0] == ECAM.inboundStart, packet[2] == ECAM.Command.monitor.rawValue else { return nil }
        accessoryCode = packet[4]
        switches = UInt16(packet[5]) | UInt16(packet[6]) << 8
        alarmBits = UInt32(packet[7]) | UInt32(packet[8]) << 8 | UInt32(packet[12]) << 16 | UInt32(packet[13]) << 24
        state = packet[9]
        subState = packet[10]
        progress = packet[11]
    }

    var isDispensing: Bool { state == 5 || state == 10 || state == 11 || (state == 7 && subState != 0) }

    var power: MachinePower {
        switch state {
        case 0: return .off
        case 1, 3: return .turningOn
        case 2: return .rinsing
        case 4: return .descaling
        case 5, 6, 10, 11, 12: return .busy
        case 7: return subState == 0 ? .ready : .busy
        case 8: return .rinsing
        case 14: return .busy
        default: return .unknown
        }
    }

    var activity: MachineActivity {
        switch state {
        case 1, 3: return .heating
        case 2, 8: return .rinsing
        case 4: return .descaling
        case 5: return .steaming
        case 10: return .dispensingMilk
        case 11: return .dispensingWater
        case 12: return .cleaningMilk
        case 14: return .changingFilter
        case 6: return .brewingCoffee
        case 7 where subState != 0: return .brewingCoffee
        default: return .idle
        }
    }

    var accessory: MilkAccessory {
        switch accessoryCode {
        case 0: return .none
        case 1: return .hotWaterSpout
        case 2: return .carafe
        case 3, 4: return .carafeCleaning
        default: return .unknown
        }
    }

    /// Alarm bits plus the switch bits that mean "a part is missing".
    var alarms: [MachineAlarm] {
        var found = Set<MachineAlarm>()
        func bit(_ index: Int) -> Bool { alarmBits & (1 << UInt32(index)) != 0 }
        if bit(0) { found.insert(.waterTankEmpty) }
        if bit(1) { found.insert(.wasteContainerFull) }
        if bit(2) { found.insert(.descaleNeeded) }
        if bit(3) { found.insert(.replaceFilter) }
        if bit(4) { found.insert(.groundTooFine) }
        if bit(5) || bit(15) { found.insert(.beansEmpty) }
        if bit(6) { found.insert(.serviceNeeded) }
        if bit(7) || bit(9) || bit(10) || bit(12) || (21...27).contains(where: bit) { found.insert(.hardwareFault) }
        if bit(11) { found.insert(.dripTrayMissing) }
        if bit(17) { found.insert(.beanHopperMissing) }
        if switches & (1 << 3) != 0 { found.insert(.wasteContainerMissing) }
        if switches & (1 << 4) != 0 { found.insert(.waterTankMissing) }
        if switches & (1 << 13) != 0 { found.insert(.doorOpen) }
        if accessoryCode == 4 { found.insert(.milkCarafeNeedsCleaning) }
        return MachineAlarm.allCases.filter(found.contains)
    }

    func applying(to snapshot: MachineSnapshot) -> MachineSnapshot {
        var next = snapshot
        next.power = power
        next.activity = activity
        next.alarms = alarms
        next.accessory = accessory
        next.progress = isDispensing && progress <= 100 ? Int(progress) : nil
        next.updatedAt = Date()
        return next
    }
}
