import XCTest

final class AccessLensUITests: XCTestCase {
    @MainActor
    func testFirstRunCompletesOnboardingAndShowsHome() throws {
        let app = launchApp(onboardingState: "incomplete")

        XCTAssertTrue(app.staticTexts["onboarding-heading"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["onboarding-heading"].label, "Welcome to AccessLens")
        XCTAssertEqual(app.staticTexts["onboarding-progress"].label, "Step 1 of 4")
        XCTAssertFalse(app.alerts["AccessLens Would Like to Access the Camera"].exists)

        for expectedStep in 2...4 {
            app.buttons["Continue"].tap()
            XCTAssertTrue(app.staticTexts["onboarding-progress"].waitForExistence(timeout: 2))
            XCTAssertEqual(app.staticTexts["onboarding-progress"].label, "Step \(expectedStep) of 4")
        }

        app.buttons["Continue to AccessLens"].tap()
        XCTAssertTrue(app.staticTexts["accesslens-root-title"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testReturningUserLaunchesDirectlyIntoHome() throws {
        let app = launchApp(onboardingState: "complete")

        XCTAssertTrue(app.staticTexts["accesslens-root-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["accesslens-product-statement"].exists)
        XCTAssertFalse(app.staticTexts["onboarding-heading"].exists)
    }

    @MainActor
    private func launchApp(onboardingState: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-accesslens-onboarding-state", onboardingState]
        app.launch()
        return app
    }
}
