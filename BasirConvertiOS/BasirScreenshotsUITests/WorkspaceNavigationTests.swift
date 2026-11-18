import XCTest

/// Critical user paths are asserted, rather than silently skipped by the screenshot tour.
final class WorkspaceNavigationTests: XCTestCase {
    func testHomeComposerAndGroupedSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-interface_language", "ar", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA",
                               "-onboarding_completed_v3_1", "YES", "-video_launch_seen_v1", "YES",
                               "-completion_notifications", "NO"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["الرئيسية"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.tabBars.buttons.count, 3)
        let compose = app.buttons["تحويل جديد"].firstMatch
        XCTAssertTrue(compose.waitForExistence(timeout: 5))
        compose.tap()
        XCTAssertTrue(app.staticTexts["اختر الملفات"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["التالي"].isEnabled, "Cannot advance without a file")
        capture("composer-choose-files")
        app.tabBars.buttons["الإعدادات"].tap()
        let appearance = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "المظهر واللغة")).firstMatch
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        // Root settings show destinations, not the entire form.
        XCTAssertFalse(app.switches["رفع الملفات عبر Wi‑Fi فقط"].exists)
        capture("settings-categories")
        appearance.tap()
        XCTAssertTrue(app.staticTexts["لغة التطبيق"].waitForExistence(timeout: 5))
        capture("settings-appearance")
        app.navigationBars.buttons.firstMatch.tap()
        let connection = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "الاتصال والاستئناف")).firstMatch
        XCTAssertTrue(connection.waitForExistence(timeout: 5))
        connection.tap()
        XCTAssertTrue(app.switches["رفع الملفات عبر Wi‑Fi فقط"].waitForExistence(timeout: 5))
        app.tabBars.buttons["ملفاتي"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        capture("my-files")
    }

    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
