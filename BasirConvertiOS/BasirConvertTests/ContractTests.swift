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
}

