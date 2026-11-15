import XCTest
@testable import BasirConvert

final class ReadyResultRetryTests: XCTestCase {
    func testTransientDeliveryErrorsRetryAndAuthenticationCancellationDoNot() {
        XCTAssertTrue(ReadyResultRetry.shouldRetry(URLError(.networkConnectionLost), status: nil))
        XCTAssertTrue(ReadyResultRetry.shouldRetry(BasirError.checksumMismatch, status: 200))
        XCTAssertTrue(ReadyResultRetry.shouldRetry(URLError(.badServerResponse), status: 503))
        XCTAssertFalse(ReadyResultRetry.shouldRetry(URLError(.userAuthenticationRequired), status: 401))
        XCTAssertFalse(ReadyResultRetry.shouldRetry(CancellationError(), status: 503))
        XCTAssertFalse(ReadyResultRetry.shouldRetry(URLError(.cancelled), status: nil))
    }

    func testBackoffRespectsRetryAfterAndRemainsBounded() {
        XCTAssertEqual(ReadyResultRetry.delay(attempt: 0, retryAfter: nil), 2)
        XCTAssertEqual(ReadyResultRetry.delay(attempt: 2, retryAfter: nil), 8)
        XCTAssertEqual(ReadyResultRetry.delay(attempt: 0, retryAfter: 9), 9)
        XCTAssertEqual(ReadyResultRetry.delay(attempt: 100, retryAfter: 1000), 30)
    }

    func testOptimizationIsOptInAndOldSavedOptionsStillDecode() throws {
        let options = ConversionOptions(operation: .convert, outputMode: .full,
                                        targetLanguage: nil, embedVisuals: true,
                                        includeMath: false, interfaceLanguage: .arabic)
        XCTAssertFalse(options.encodedMode.contains("pdf_optimize"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(options)) as? [String: Any])
        object.removeValue(forKey: "optimizePDF")
        let older = try JSONDecoder().decode(ConversionOptions.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(older.optimizePDF)
        object["optimizePDF"] = true
        let selected = try JSONDecoder().decode(ConversionOptions.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(selected.encodedMode.contains("|pdf_optimize"))
    }

    @MainActor
    func testOptimizationDefaultsOffAndPersistsExplicitChoice() throws {
        let name = "ReadyResultRetryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        XCTAssertFalse(settings.optimizePDF)
        settings.optimizePDF = true
        settings.save(defaults: defaults)
        XCTAssertTrue(SettingsStore(defaults: defaults).optimizePDF)
    }
}
