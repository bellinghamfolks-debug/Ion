import XCTest
@testable import BasirConvert

final class ContractTests: XCTestCase {
    func testAcceptsStableContractField() {
        XCTAssertTrue(BasirAPIContract.accepts(apiContract: "api_contract_v3", capabilities: []))
    }

    func testAcceptsStableContractCapability() {
        XCTAssertTrue(BasirAPIContract.accepts(apiContract: "", capabilities: ["api_contract_v3"]))
    }

    func testRejectsInternalCapabilityListWithoutContract() {
        XCTAssertFalse(BasirAPIContract.accepts(
            apiContract: "",
            capabilities: ["source_geometry_tables", "adaptive_fidelity_repair"]
        ))
    }

    func testNaturalAccountingAcceptsSkippedBlankPage() {
        XCTAssertTrue(BasirAPIContract.naturalPageAccountingIsValid(
            expectedSelectedPages: 11,
            retained: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
            skippedBlank: [11],
            failed: []
        ))
    }

    func testNaturalAccountingAcceptsPartialResult() {
        XCTAssertTrue(BasirAPIContract.naturalPageAccountingIsValid(
            expectedSelectedPages: 11,
            retained: [1, 2, 3, 4, 5, 6, 7, 8, 9],
            skippedBlank: [10],
            failed: [11]
        ))
    }

    func testNaturalAccountingRejectsMissingPage() {
        XCTAssertFalse(BasirAPIContract.naturalPageAccountingIsValid(
            expectedSelectedPages: 11,
            retained: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
            skippedBlank: [],
            failed: []
        ))
    }

    func testNaturalAccountingRejectsOverlappingBuckets() {
        XCTAssertFalse(BasirAPIContract.naturalPageAccountingIsValid(
            expectedSelectedPages: 2,
            retained: [1],
            skippedBlank: [1],
            failed: []
        ))
    }
}
