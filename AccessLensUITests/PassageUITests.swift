import XCTest

@MainActor
final class PassageUITests: XCTestCase {
    private let findingID = "22222222-2222-2222-2222-222222222222"

    func testCompletedScanPresentsPassageFindingAndEstimatedWidth() {
        let app = launch()
        app.buttons["start-scan"].tap()
        let finish = app.buttons["finish-scan"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()

        XCTAssertTrue(app.staticTexts["scan-review-heading"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Potential narrow passage"].exists)
        XCTAssertTrue(app.staticTexts["passage-estimated-width"].exists)
        XCTAssertTrue(app.buttons["view-guidance-\(findingID)"].exists)
    }

    func testPassageGuidanceExplainsEvidenceChecksImprovementsAndLimits() {
        let app = launch()
        app.buttons["start-scan"].tap()
        let finish = app.buttons["finish-scan"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()
        let guidance = app.buttons["view-guidance-\(findingID)"]
        XCTAssertTrue(guidance.waitForExistence(timeout: 5))
        guidance.tap()

        XCTAssertEqual(app.staticTexts["guidance-title"].label, "Potential narrow passage")
        for identifier in ["guidance-observation", "guidance-why", "guidance-checks", "guidance-improvements", "guidance-evidence", "guidance-limitations"] {
            XCTAssertTrue(app.staticTexts[identifier].exists)
        }
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'violation' OR label CONTAINS[c] 'compliant'")).firstMatch.exists)
    }

    func testHistoricalPassageFindingOpensSameGuidance() {
        let app = launch(history: "passage")
        app.buttons["scan-history"].tap()
        let row = app.buttons["history-open-33333333-3333-3333-3333-333333333333"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let guidance = app.buttons["view-guidance-\(findingID)"]
        XCTAssertTrue(guidance.waitForExistence(timeout: 5))
        guidance.tap()
        XCTAssertEqual(app.staticTexts["guidance-title"].label, "Potential narrow passage")
        XCTAssertTrue(app.staticTexts["guidance-observation"].exists)
        app.buttons["guidance-back"].tap()
        XCTAssertTrue(app.staticTexts["scan-review-heading"].waitForExistence(timeout: 5))
    }

    private func launch(history: String = "empty") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-accesslens-onboarding-state", "complete",
            "-accesslens-history", history,
            "-accesslens-camera-authorization", "authorized",
            "-accesslens-scan-findings", "stable-passage"
        ]
        app.launch()
        return app
    }
}
