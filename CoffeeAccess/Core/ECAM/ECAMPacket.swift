import Foundation

/// The De'Longhi ECAM Bluetooth framing, as documented by the open-source
/// community (asaf5767/barista, MIT; Arbuzov/home_assistant_delonghi_primadonna,
/// Apache-2.0). Every packet travels over one GATT characteristic:
///
///     host → machine:  0x0D  length  command  flag  params…  CRC_hi CRC_lo
///     machine → host:  0xD0  length  command  flag  data…    CRC_hi CRC_lo
///
/// `length` counts every byte after itself, CRC included. The checksum is
/// CRC-16/CCITT (polynomial 0x1021) seeded with 0x1D0F, big-endian.
enum ECAM {
    static let serviceUUID = "00035B03-58E6-07DD-021A-08123A000300"
    static let characteristicUUID = "00035B03-58E6-07DD-021A-08123A000301"

    static let outboundStart: UInt8 = 0x0D
    static let inboundStart: UInt8 = 0xD0

    enum Command: UInt8 {
        case monitor = 0x75
        case beverage = 0x83
        case appControl = 0x84
        case parameterWrite = 0x90
        case statistics = 0xA2
        case profileNames = 0xA4
        case recipeRead = 0xA6
        case profileSelect = 0xA9
        case recipeMinMax = 0xB0
        case setTime = 0xE2
    }

    static func crc16(_ bytes: some Sequence<UInt8>) -> UInt16 {
        var crc: UInt16 = 0x1D0F
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return crc
    }

    /// Wraps a payload (command byte first) with start byte, length and CRC.
    static func packet(_ payload: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = [outboundStart, UInt8(truncatingIfNeeded: payload.count + 3)]
        bytes += payload
        let crc = crc16(bytes)
        bytes.append(UInt8(crc >> 8))
        bytes.append(UInt8(crc & 0xFF))
        return bytes
    }

    static func hasValidChecksum(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 4 else { return false }
        let crc = crc16(bytes.dropLast(2))
        return bytes[bytes.count - 2] == UInt8(crc >> 8) && bytes[bytes.count - 1] == UInt8(crc & 0xFF)
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}

/// Reassembles inbound packets. BLE indications may split one packet across
/// several notifications or carry stray bytes; the assembler resynchronises
/// on the 0xD0 start byte and only emits packets whose CRC is valid.
struct ECAMAssembler {
    private(set) var buffer: [UInt8] = []
    private(set) var rejectedPackets = 0

    mutating func append(_ chunk: [UInt8]) -> [[UInt8]] {
        buffer += chunk
        var packets: [[UInt8]] = []
        while true {
            guard let start = buffer.firstIndex(of: ECAM.inboundStart) else {
                buffer.removeAll()
                break
            }
            if start > 0 { buffer.removeFirst(start) }
            guard buffer.count >= 2 else { break }
            let total = Int(buffer[1]) + 1
            guard total >= 4 else {
                buffer.removeFirst()
                rejectedPackets += 1
                continue
            }
            guard buffer.count >= total else { break }
            let candidate = Array(buffer[0..<total])
            if ECAM.hasValidChecksum(candidate) {
                packets.append(candidate)
                buffer.removeFirst(total)
            } else {
                // Not a real packet boundary: skip this start byte and rescan.
                rejectedPackets += 1
                buffer.removeFirst()
            }
        }
        return packets
    }
}
