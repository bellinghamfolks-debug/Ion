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

    func testLegacyModelSelectionsMigrateToCurrentProductionModel() {
        XCTAssertEqual(AIModelChoice.pro.serverModelID, "gemini-3.7-flash")
        XCTAssertEqual(AIModelChoice.economy.serverModelID, "gemini-3.7-flash")
        XCTAssertEqual(AIModelChoice.flash.serverModelID, "gemini-3.7-flash")
        XCTAssertEqual(AIModelChoice.allCases, [.automatic, .flash])
    }

    func testConversionDefaultsToThreeParallelPagesAndMigratesSavedModel() {
        let options = ConversionOptions(
            operation: .convert,
            outputMode: .full,
            targetLanguage: nil,
            embedVisuals: true,
            includeMath: false,
            interfaceLanguage: .arabic,
            preferredModel: "gemini-3.1-pro-preview"
        )
        XCTAssertEqual(options.concurrentPages, 3)
        XCTAssertEqual(options.effectivePreferredModel, "gemini-3.7-flash")
        XCTAssertTrue(options.encodedMode.contains("parallel:3"))
    }

    func testResultDownloadSeparatesLocalFileFailuresFromNetworkFailures() {
        XCTAssertTrue(BackgroundTransferCoordinator.isLocalFileFailure(URLError(.cannotCreateFile)))
        XCTAssertTrue(BackgroundTransferCoordinator.isLocalFileFailure(URLError(.cannotOpenFile)))
        XCTAssertTrue(BackgroundTransferCoordinator.isLocalFileFailure(URLError(.fileDoesNotExist)))
        XCTAssertTrue(BackgroundTransferCoordinator.isLocalFileFailure(URLError(.noPermissionsToReadFile)))

        XCTAssertFalse(BackgroundTransferCoordinator.isLocalFileFailure(URLError(.notConnectedToInternet)))
        XCTAssertFalse(BackgroundTransferCoordinator.isLocalFileFailure(URLError(.networkConnectionLost)))
        XCTAssertFalse(BackgroundTransferCoordinator.isLocalFileFailure(URLError(.timedOut)))
    }

    @MainActor
    func testSettingsStoreMigratesPersistedLegacyModelAndUsesThreePageDefault() {
        let suite = "BasirContractTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Unable to create isolated UserDefaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("gemini-3.1-pro-preview", forKey: "ai_preferred_model")

        let store = SettingsStore(
            defaults: defaults,
            configuration: ServerConfiguration(baseURL: "https://example.invalid", clientToken: "test")
        )

        XCTAssertEqual(store.preferredModel, .flash)
        XCTAssertEqual(store.concurrentPages, 3)
        XCTAssertEqual(defaults.string(forKey: "ai_preferred_model"), "gemini-3.7-flash")
    }
}
