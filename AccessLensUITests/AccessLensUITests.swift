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
    func testDeniedCameraShowsAccessibleSettingsGuidance() throws {
        let app = launchApp(onboardingState: "complete", cameraAuthorization: "denied")

        app.buttons["Start Scan"].tap()

        XCTAssertTrue(app.staticTexts["scan-heading"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["camera-denied-state"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Open Settings"].exists)
    }

    @MainActor
    func testAuthorizedLaunchEntersScanShellWithoutPretendingCameraWorksInSimulator() throws {
        let app = launchApp(onboardingState: "complete", cameraAuthorization: "authorized")

        app.buttons["Start Scan"].tap()

        XCTAssertTrue(app.staticTexts["scan-heading"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["scan-foundation-message"].exists)
    }

    @MainActor
    func testAnalyzingScanWithNoStableFindingsDoesNotClaimAccessibility() throws {
        let app = launchApp(
            onboardingState: "complete",
            cameraAuthorization: "authorized",
            scanFindings: "analyzing-empty"
        )

        app.buttons["Start Scan"].tap()
        XCTAssertTrue(app.staticTexts["scan-heading"].waitForExistence(timeout: 5))
        let emptyState = app.staticTexts["no-potential-findings"]
        XCTAssertTrue(emptyState.waitForExistence(timeout: 5), emptyState.debugDescription)
        XCTAssertTrue(emptyState.label.contains("No potential issues identified yet."))
        XCTAssertFalse(app.staticTexts["Environment is accessible"].exists)
    }

    @MainActor
    func testDeterministicStableFindingIsPresentedWithUncertainty() throws {
        let app = launchApp(
            onboardingState: "complete",
            cameraAuthorization: "authorized",
            scanFindings: "stable-low-contrast"
        )

        app.buttons["Start Scan"].tap()

        XCTAssertTrue(app.staticTexts["Potential low contrast"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Text in this area may be difficult to distinguish from its background."].exists)
        XCTAssertTrue(app.staticTexts["EXIT"].exists)
        XCTAssertFalse(app.staticTexts["WCAG FAIL"].exists)
    }

    @MainActor
    private func launchApp(
        onboardingState: String,
        cameraAuthorization: String? = nil,
        scanFindings: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-accesslens-onboarding-state", onboardingState]
        if let cameraAuthorization {
            app.launchArguments += ["-accesslens-camera-authorization", cameraAuthorization]
        }
        if let scanFindings {
            app.launchArguments += ["-accesslens-scan-findings", scanFindings]
        }
        app.launch()
        return app
    }
}
