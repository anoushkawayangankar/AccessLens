import XCTest

final class AccessLensUITests: XCTestCase {
    @MainActor
    func testLaunchShowsAccessLensFoundationShell() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["accesslens-root-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["accesslens-product-statement"].exists)
    }
}

