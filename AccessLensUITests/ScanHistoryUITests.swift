import XCTest

@MainActor
final class ScanHistoryUITests: XCTestCase {
    private let newerID = "33333333-3333-3333-3333-333333333333"
    private let olderID = "44444444-4444-4444-4444-444444444444"

    func testEmptyHistoryHasAccessibleExplanation() {
        let app = launch(history: "empty")
        app.buttons["scan-history"].tap()
        XCTAssertTrue(app.staticTexts["history-empty"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Complete a scan to see it here."].exists)
        XCTAssertTrue(app.buttons["Start Scan"].exists)
    }

    func testSavedHistoryShowsNewestFirstAndZeroFindingRow() {
        let app = launch(history: "seeded")
        app.buttons["scan-history"].tap()
        let rows = historyRows(app)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.element(boundBy: 0).identifier, "history-open-\(newerID)")
        XCTAssertEqual(rows.element(boundBy: 1).identifier, "history-open-\(olderID)")
        XCTAssertTrue(rows.element(boundBy: 1).label.contains("No potential findings"))
    }

    func testHistoricalReviewReusesFindingPresentationAndReturnsToHistory() {
        let app = launch(history: "seeded")
        app.buttons["scan-history"].tap()
        let row = app.buttons["history-open-\(newerID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.staticTexts["scan-review-heading"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["EXIT"].exists)
        XCTAssertTrue(app.staticTexts["Potential low contrast"].exists)
        XCTAssertFalse(app.staticTexts["scan-saved"].exists)
        app.buttons["scan-review-done"].tap()
        XCTAssertTrue(app.buttons["history-open-\(newerID)"].waitForExistence(timeout: 5))
    }

    func testDeleteRequiresConfirmationAndRemovesOnlySelectedScan() {
        let app = launch(history: "seeded")
        app.buttons["scan-history"].tap()
        let delete = app.buttons["history-delete-\(newerID)"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(app.alerts["Delete Scan?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["history-open-\(newerID)"].exists)
        delete.tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["history-open-\(newerID)"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["history-open-\(olderID)"].exists)
        app.buttons["history-delete-\(olderID)"].tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["history-empty"].waitForExistence(timeout: 5))
    }

    func testCompleteScanAutomaticallyAppearsInHistory() {
        let app = launch(history: "empty", scanFindings: "stable-low-contrast")
        app.buttons["start-scan"].tap()
        XCTAssertTrue(app.buttons["finish-scan"].waitForExistence(timeout: 5))
        app.buttons["finish-scan"].tap()
        XCTAssertTrue(app.staticTexts["scan-saved"].waitForExistence(timeout: 5))
        app.buttons["scan-review-done"].tap()
        XCTAssertTrue(app.buttons["scan-history"].waitForExistence(timeout: 5))
        app.buttons["scan-history"].tap()
        let rows = historyRows(app)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows.firstMatch.label.contains("1 potential finding"))
        rows.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["EXIT"].waitForExistence(timeout: 5))
    }

    private func historyRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history-open-"))
    }

    private func launch(history: String, scanFindings: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-accesslens-onboarding-state", "complete", "-accesslens-history", history,
                               "-accesslens-camera-authorization", "authorized"]
        if let scanFindings { app.launchArguments += ["-accesslens-scan-findings", scanFindings] }
        app.launch()
        return app
    }
}
