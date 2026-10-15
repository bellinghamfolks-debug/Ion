import XCTest
@testable import BasirConvert

/// Hybrid PDF reading is an explicit choice: off unless the person picks it.
@MainActor
final class HybridOptionTests: XCTestCase {
    func testTheCurrentModeStaysTheDefault() {
        let defaults = UserDefaults(suiteName: "hybrid-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.pdfReading, .full)
        let options = ConversionOptions(operation: .convert, outputMode: .full, targetLanguage: nil,
                                        embedVisuals: true, includeMath: false, interfaceLanguage: .arabic)
        XCTAssertFalse(options.encodedMode.contains("|hybrid"))
    }

    func testChoosingHybridSendsItAndIsRemembered() {
        let name = "hybrid-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let settings = SettingsStore(defaults: defaults)
        settings.pdfReading = .hybrid
        settings.save(defaults: defaults)
        XCTAssertEqual(SettingsStore(defaults: UserDefaults(suiteName: name)!).pdfReading, .hybrid)
        let options = ConversionOptions(operation: .convert, outputMode: .full, targetLanguage: nil,
                                        embedVisuals: true, includeMath: false, interfaceLanguage: .arabic,
                                        hybridPDF: true)
        XCTAssertTrue(options.encodedMode.hasSuffix("|hybrid"))
    }

    func testOlderSavedTasksStillDecode() throws {
        let options = ConversionOptions(operation: .convert, outputMode: .full, targetLanguage: nil,
                                        embedVisuals: true, includeMath: false, interfaceLanguage: .arabic)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(options)) as? [String: Any])
        json.removeValue(forKey: "hybridPDF")
        let decoded = try JSONDecoder().decode(ConversionOptions.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.hybridPDF)
        XCTAssertFalse(decoded.encodedMode.contains("|hybrid"))
    }
}
