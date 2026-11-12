import XCTest
@testable import BasirConvert

@MainActor
final class CollectionSettingsTests: XCTestCase {
    func testRetentionIsEnabledByDefaultAndOptOutPersists() {
        let name = "collection-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        XCTAssertTrue(settings.collectionEnabled)
        XCTAssertFalse(settings.collectionMetadataOnly)
        settings.collectionEnabled = false
        XCTAssertFalse(SettingsStore(defaults: defaults).collectionEnabled)
    }

    func testContentExclusionIsIndependentAndPersists() {
        let name = "collection-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        settings.collectionMetadataOnly = true
        let reopened = SettingsStore(defaults: defaults)
        XCTAssertTrue(reopened.collectionEnabled)
        XCTAssertTrue(reopened.collectionMetadataOnly)
    }
}
