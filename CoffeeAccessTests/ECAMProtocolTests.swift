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
}
