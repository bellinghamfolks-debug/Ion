import XCTest
@testable import CoffeeAccess

/// Packets captured from the official app and real machines (published by
/// asaf5767/barista and Arbuzov/home_assistant_delonghi_primadonna). Our
/// encoder and parser must reproduce them byte for byte.
final class ECAMProtocolTests: XCTestCase {
    private func bytes(_ hex: String) -> [UInt8] {
        hex.split(separator: " ").map { UInt8($0, radix: 16)! }
    }

    func testChecksumMatchesCapturedPackets() {
        let captured = [
            "0d 05 75 0f da 25",
            "0d 07 84 0f 02 01 55 12",
            "0d 08 83 f0 02 02 06 c4 b1",
            "d0 12 75 0f 01 05 00 00 00 07 00 00 00 00 00 00 00 9d 61",
            "d0 07 a9 f0 01 00 3b 3c",
        ]
        for packet in captured {
            XCTAssertTrue(ECAM.hasValidChecksum(bytes(packet)), packet)
        }
        XCTAssertFalse(ECAM.hasValidChecksum(bytes("0d 05 75 0f da 26")))
    }

    func testFixedCommandsMatchCapture() {
        XCTAssertEqual(ECAMCommands.monitor, bytes("0d 05 75 0f da 25"))
        XCTAssertEqual(ECAMCommands.powerOn, bytes("0d 07 84 0f 02 01 55 12"))
    }

    func testEspressoCommandMatchesCapture() throws {
        var recipe = Recipe.standard(.espresso)
        recipe.coffeeML = 40
        recipe.aroma = .normal
        recipe.temperature = .low
        XCTAssertEqual(try ECAMCommands.brew(recipe),
                       bytes("0d 11 83 f0 01 01 01 00 28 02 03 08 00 00 00 06 8f fc"))
    }

    func testCoffeeCommandMatchesCapture() throws {
        var recipe = Recipe.standard(.coffee)
        recipe.coffeeML = 103
        recipe.aroma = .mild
        recipe.temperature = .low
        // 103 is not on the 10 ml grid, so build the packet from ingredients
        // directly to compare with the capture.
        var payload: [UInt8] = [0x83, 0xF0, 0x02, 0x01]
        payload += ECAMCommands.encode(.coffee, 103) + ECAMCommands.encode(.taste, 2) + ECAMCommands.encode(.temperature, 0)
        payload.append(ECAMCommands.prepareTasteType)
        XCTAssertEqual(ECAM.packet(payload), bytes("0d 0f 83 f0 02 01 01 00 67 02 02 00 00 06 77 ff"))
    }

    func testAmericanoCommandMatchesCapture() throws {
        var recipe = Recipe.standard(.americano)
        recipe.coffeeML = 40
        recipe.waterML = 110
        recipe.aroma = .normal
        recipe.temperature = .low
        XCTAssertEqual(try ECAMCommands.brew(recipe),
                       bytes("0d 12 83 f0 06 01 01 00 28 02 03 0f 00 6e 00 00 06 47 8b"))
    }

    func testHotWaterCommandMatchesCapture() throws {
        var recipe = Recipe.standard(.hotWater)
        recipe.waterML = 250
        XCTAssertEqual(try ECAMCommands.brew(recipe), bytes("0d 0d 83 f0 10 01 0f 00 fa 1c 01 06 04 b4"))
    }

    func testStopCommandsMatchCapture() throws {
        XCTAssertEqual(try ECAMCommands.stop(.espresso), bytes("0d 08 83 f0 01 02 06 9d e1"))
        XCTAssertEqual(try ECAMCommands.stop(.americano), bytes("0d 08 83 f0 06 02 06 18 71"))
        XCTAssertEqual(try ECAMCommands.stop(.hotWater), bytes("0d 08 83 f0 10 02 06 e9 b2"))
    }

    func testMilkDrinkCarriesMilkAndInversion() throws {
        var recipe = Recipe.standard(.cappuccino)
        recipe.coffeeML = 65
        recipe.milkSeconds = 19
        recipe.milkFirst = true
        let packet = try ECAMCommands.brew(recipe)
        XCTAssertTrue(ECAM.hasValidChecksum(packet))
        XCTAssertEqual(Int(packet[1]), packet.count - 1)
        let ingredients = Array(packet[6..<(packet.count - 3)])
        XCTAssertEqual(Array(ingredients.prefix(6)), [0x01, 0x00, 65, 0x09, 0x00, 19])
        XCTAssertEqual(Array(ingredients.suffix(2)), [0x0C, 0x01])
    }

    func testDrinksWithoutKnownCodeAreRejectedOverBluetooth() {
        XCTAssertThrowsError(try ECAMCommands.brew(.standard(.icedCappuccino))) { error in
            XCTAssertEqual(error as? MachineError, .unsupportedOverBluetooth(.icedCappuccino))
        }
    }

    func testMonitorParsingFromRealMachines() {
        let ready = ECAMMonitor(packet: bytes("d0 12 75 0f 01 05 00 00 00 07 00 00 00 00 00 00 00 9d 61"))!
        XCTAssertEqual(ready.power, .ready)
        XCTAssertEqual(ready.alarms, [])

        let noTank = ECAMMonitor(packet: bytes("d0 12 75 0f 01 15 00 00 00 07 00 00 00 00 00 00 00 aa 31"))!
        XCTAssertEqual(noTank.alarms, [.waterTankMissing])

        let noGrounds = ECAMMonitor(packet: bytes("d0 12 75 0f 01 0d 00 00 00 07 00 00 00 00 00 00 00 86 c9"))!
        XCTAssertEqual(noGrounds.alarms, [.wasteContainerMissing])

        let off = ECAMMonitor(packet: bytes("d0 12 75 0f 01 01 00 00 00 00 03 00 00 00 00 00 00 8f 2f"))!
        XCTAssertEqual(off.power, .off)

        let heating = ECAMMonitor(packet: bytes("d0 12 75 0f 01 01 00 00 00 01 07 64 00 00 00 00 00 50 83"))!
        XCTAssertEqual(heating.power, .turningOn)

        let water = ECAMMonitor(packet: bytes("d0 12 75 0f 01 45 00 01 00 07 00 00 00 00 00 00 00 2f 64"))!
        XCTAssertEqual(water.alarms, [.waterTankEmpty])

        let hotWater = ECAMMonitor(packet: bytes("d0 12 75 0f 01 05 00 00 00 0b 03 07 00 00 00 00 00 9c 15"))!
        XCTAssertEqual(hotWater.power, .busy)
        XCTAssertEqual(hotWater.activity, .dispensingWater)
        XCTAssertEqual(hotWater.applying(to: MachineSnapshot()).progress, 7)

        let carafeClean = ECAMMonitor(packet: bytes("d0 12 75 0f 04 05 01 00 40 0c 03 0d 00 00 00 00 00 1a 51"))!
        XCTAssertEqual(carafeClean.activity, .cleaningMilk)
        XCTAssertTrue(carafeClean.alarms.contains(.milkCarafeNeedsCleaning))
    }

    func testAssemblerJoinsSplitPacketsAndSkipsNoise() {
        var assembler = ECAMAssembler()
        let packet = bytes("d0 12 75 0f 01 05 00 00 00 07 00 00 00 00 00 00 00 9d 61")
        XCTAssertEqual(assembler.append([0x00, 0xFF] + Array(packet[0..<7])), [])
        XCTAssertEqual(assembler.append(Array(packet[7...])), [packet])
        XCTAssertTrue(assembler.buffer.isEmpty)

        let profile = bytes("d0 07 a9 f0 01 00 3b 3c")
        XCTAssertEqual(assembler.append(packet + profile), [packet, profile])
    }

    func testAssemblerRejectsCorruptPacket() {
        var assembler = ECAMAssembler()
        var corrupt = bytes("d0 07 a9 f0 01 00 3b 3c")
        corrupt[5] = 0x09
        let good = bytes("d0 07 a9 f0 02 00 6e 6f")
        XCTAssertEqual(assembler.append(corrupt + good), [good])
        XCTAssertGreaterThan(assembler.rejectedPackets, 0)
    }

    func testSettingsCommandsMatchCapture() {
        XCTAssertEqual(ECAMCommands.writeParameter(.autoOff, value: 0), bytes("0d 0b 90 0f 00 3e 00 00 00 00 81 e3"))
        XCTAssertEqual(ECAMCommands.writeParameter(.waterTemperature, value: 0), bytes("0d 0b 90 0f 00 3d 00 00 00 00 6f 31"))
        XCTAssertEqual(ECAMCommands.selectProfile(1), bytes("0d 06 a9 f0 01 d7 c0"))
        XCTAssertEqual(ECAMCommands.readParameter(.switches), bytes("0d 08 95 0f 00 3f 01 2b 83"))
        XCTAssertEqual(ECAMCommands.statistics(start: 100, count: 10), bytes("0d 08 a2 0f 00 64 0a 23 97"))
    }

    func testSettingsBitmaskAndCommandList() {
        var settings = MachineSettings()
        settings.sounds = true
        settings.cupLight = false
        settings.energySaving = true
        XCTAssertEqual(settings.switchMask, 0x14)
        var copy = MachineSettings()
        copy.applySwitchMask(0x08)
        XCTAssertEqual([copy.sounds, copy.cupLight, copy.energySaving], [false, true, false])
        settings.waterHardness = 3
        let commands = ECAMCommands.commands(for: settings)
        XCTAssertEqual(commands.count, 4)
        XCTAssertTrue(commands.allSatisfy(ECAM.hasValidChecksum))
        XCTAssertEqual(commands[1][9], 2, "hardness level 3 is sent as index 2")
    }

    private func reply(_ payload: [UInt8]) -> [UInt8] {
        var packet: [UInt8] = [ECAM.inboundStart, UInt8(payload.count + 3)] + payload
        let crc = ECAM.crc16(packet)
        packet += [UInt8(crc >> 8), UInt8(crc & 0xFF)]
        return packet
    }

    func testStatisticsReplyParsing() {
        let packet = reply([0xA2, 0x0F, 0x00, 0x64, 0x00, 0x00, 0x00, 0x2A, 0x00, 0x69, 0x00, 0x00, 0x01, 0x00, 0x0B, 0xB8, 0x00, 0x00, 0x00, 0x07])
        XCTAssertTrue(ECAM.hasValidChecksum(packet))
        let values = ECAMReplies.statistics(packet)
        XCTAssertEqual(values, [100: 42, 105: 256, 3000: 7])
        var counters = MachineCounters()
        counters.merge(values)
        XCTAssertEqual(counters.totalCoffee, 7)
        XCTAssertEqual(counters.descaleCount, 256)
        XCTAssertNil(counters.tea)
    }

    func testParameterAndProfileNameReplies() {
        let parameter = reply([0x95, 0x0F, 0x00, 0x3F, 0x00, 0x00, 0x00, 0x1C])
        XCTAssertEqual(ECAMReplies.parameter(parameter)?.parameter, 0x3F)
        XCTAssertEqual(ECAMReplies.parameter(parameter)?.value, 0x1C)

        func slot(_ name: String) -> [UInt8] {
            var bytes = Array(name.data(using: .utf16BigEndian)!)
            bytes += Array(repeating: 0, count: 20 - bytes.count)
            return bytes + [0x00]
        }
        let names = reply([0xA4, 0xF0] + slot("Ali") + slot("") + slot("Sara") + slot("Guest"))
        XCTAssertEqual(ECAMReplies.profileNames(names), [1: "Ali", 3: "Sara", 4: "Guest"])
    }
}
