import XCTest

final class iDiagnosticsLaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDashboardLaunchesAndSystemTestIsReachable() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["فحص الآيفون"].waitForExistence(timeout: 8))
        let systemTest = app.staticTexts["النظام والبطارية"].firstMatch
        XCTAssertTrue(systemTest.waitForExistence(timeout: 5))
        systemTest.tap()
        XCTAssertTrue(app.navigationBars["النظام والبطارية"].waitForExistence(timeout: 5))
    }
}
