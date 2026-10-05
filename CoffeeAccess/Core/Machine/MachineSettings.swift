import Foundation

/// The machine's own settings menu, mirrored in the app.
struct MachineSettings: Codable, Equatable {
    enum AutoOff: Int, CaseIterable, Codable, Identifiable {
        case fifteenMinutes = 0, thirtyMinutes, oneHour, twoHours, threeHours
        var id: Int { rawValue }
    }

    /// 1 (soft) … 4 (very hard), from the test strip supplied with the machine.
    var waterHardness = 4
    var autoOff: AutoOff = .thirtyMinutes
    var energySaving = true
    var cupLight = true
    var sounds = true
    /// Boiler water temperature, 0 (low) … 3 (highest).
    var waterTemperature = 1

    static let hardnessRange = 1...4
    static let waterTemperatureRange = 0...3

    /// Bitmask of parameter 0x3F (sounds, cup light, energy saving).
    var switchMask: UInt8 {
        var mask: UInt8 = 0
        if sounds { mask |= 0x04 }
        if cupLight { mask |= 0x08 }
        if energySaving { mask |= 0x10 }
        return mask
    }

    mutating func applySwitchMask(_ mask: UInt8) {
        sounds = mask & 0x04 != 0
        cupLight = mask & 0x08 != 0
        energySaving = mask & 0x10 != 0
    }
}

/// Lifetime counters read from the machine (statistics parameters).
struct MachineCounters: Equatable {
    var values: [Int: Int] = [:]

    static let requestRanges: [(start: Int, count: Int)] = [(100, 10), (110, 10), (3000, 10), (3017, 10), (3077, 4)]

    var isEmpty: Bool { values.isEmpty }
    var totalCoffee: Int? { sum(3000, 3077) }
    var milkDrinks: Int? { sum(3001, 3003) }
    var coldMilk: Int? { values[3017] }
    var tea: Int? { values[3025] }
    var descaleCount: Int? { values[105] }
    var filterReplacements: Int? { values[108] }
    var milkCleanings: Int? { values[111] }
    /// The machine counts water in half-millilitres.
    var waterLitres: Double? { values[106].map { Double($0) / 2000 } }

    private func sum(_ a: Int, _ b: Int) -> Int? {
        guard values[a] != nil || values[b] != nil else { return nil }
        return (values[a] ?? 0) + (values[b] ?? 0)
    }

    mutating func merge(_ other: [Int: Int]) {
        values.merge(other) { _, new in new }
    }
}

extension ECAMCommands {
    enum Parameter: UInt8 {
        case waterHardness = 0x32
        case waterTemperature = 0x3D
        case autoOff = 0x3E
        case switches = 0x3F
    }

    static func writeParameter(_ parameter: Parameter, value: UInt8) -> [UInt8] {
        ECAM.packet([ECAM.Command.parameterWrite.rawValue, 0x0F, 0x00, parameter.rawValue, 0x00, 0x00, 0x00, value])
    }

    static func readParameter(_ parameter: Parameter) -> [UInt8] {
        ECAM.packet([0x95, 0x0F, 0x00, parameter.rawValue, 0x01])
    }

    static func statistics(start: Int, count: Int) -> [UInt8] {
        ECAM.packet([ECAM.Command.statistics.rawValue, 0x0F, UInt8((start >> 8) & 0xFF), UInt8(start & 0xFF), UInt8(count)])
    }

    static func setClock(hour: Int, minute: Int) -> [UInt8] {
        ECAM.packet([ECAM.Command.setTime.rawValue, 0xF0, UInt8(max(0, min(hour, 23))), UInt8(max(0, min(minute, 59)))])
    }

    /// Standby. Found by the community through probing; not every model
    /// accepts it, so the app reports when the machine stays on.
    static let powerOff = ECAM.packet([ECAM.Command.appControl.rawValue, 0x0F, 0x01, 0x01])

    static let profileNames = ECAM.packet([ECAM.Command.profileNames.rawValue, 0xF0, 0x01, 0x06])

    static func commands(for settings: MachineSettings) -> [[UInt8]] {
        [
            writeParameter(.switches, value: settings.switchMask),
            writeParameter(.waterHardness, value: UInt8(max(1, min(settings.waterHardness, 4)) - 1)),
            writeParameter(.autoOff, value: UInt8(settings.autoOff.rawValue)),
            writeParameter(.waterTemperature, value: UInt8(max(0, min(settings.waterTemperature, 3)))),
        ]
    }
}

/// Parsers for replies other than the status monitor.
enum ECAMReplies {
    /// Statistics (0xA2): first value is implicit at bytes 4-9, then blocks of
    /// [id (2 bytes), value (4 bytes)] until the checksum.
    static func statistics(_ packet: [UInt8]) -> [Int: Int] {
        guard packet.count >= 12, packet[0] == ECAM.inboundStart, packet[2] == ECAM.Command.statistics.rawValue else { return [:] }
        func int32(_ offset: Int) -> Int {
            Int(packet[offset]) << 24 | Int(packet[offset + 1]) << 16 | Int(packet[offset + 2]) << 8 | Int(packet[offset + 3])
        }
        var values: [Int: Int] = [Int(packet[4]) << 8 | Int(packet[5]): int32(6)]
        var offset = 10
        while offset + 6 <= packet.count - 2 {
            values[Int(packet[offset]) << 8 | Int(packet[offset + 1])] = int32(offset + 2)
            offset += 6
        }
        return values
    }

    /// Parameter read (0x95): parameter id at bytes 4-5, value at byte 9.
    static func parameter(_ packet: [UInt8]) -> (parameter: Int, value: UInt8)? {
        guard packet.count >= 12, packet[0] == ECAM.inboundStart, packet[2] == 0x95 else { return nil }
        return (Int(packet[4]) << 8 | Int(packet[5]), packet[9])
    }

    /// Profile names (0xA4): 20-byte UTF-16BE slots, one spacer byte apart.
    static func profileNames(_ packet: [UInt8], count: Int = AppData.profileCount) -> [Int: String] {
        guard packet.count > 6, packet[0] == ECAM.inboundStart, packet[2] == ECAM.Command.profileNames.rawValue else { return [:] }
        var names: [Int: String] = [:]
        var index = 4
        for profile in 1...count {
            guard index + 20 <= packet.count - 2 else { break }
            var slot = Array(packet[index..<(index + 20)])
            if let end = stride(from: 0, to: slot.count - 1, by: 2).first(where: { slot[$0] == 0 && slot[$0 + 1] == 0 }) {
                slot = Array(slot[0..<end])
            }
            let name = String(bytes: slot, encoding: .utf16BigEndian)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !name.isEmpty { names[profile] = name }
            index += 21
        }
        return names
    }
}
