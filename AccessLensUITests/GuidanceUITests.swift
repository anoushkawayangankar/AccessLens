import XCTest

@MainActor
final class GuidanceUITests: XCTestCase {
    private let firstID = "22222222-2222-2222-2222-222222222222"
    private let secondID = "11111111-1111-1111-1111-111111111111"

    func testCompletionReviewOpensGuidanceAndBackReturnsToSameReview() {
        let app = launch()
        completeScan(app)
        openGuidance(firstID, app: app)
        XCTAssertEqual(app.staticTexts["guidance-recognized-text"].label, "Recognized text: EXIT")
        for id in ["guidance-observation", "guidance-why", "guidance-checks", "guidance-improvements", "guidance-evidence", "guidance-limitations"] {
            reveal(app.staticTexts[id], in: app)
            XCTAssertTrue(app.staticTexts[id].isHittable)
        }
        app.buttons["guidance-back"].tap()
        XCTAssertTrue(app.staticTexts["scan-review-heading"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["EXIT"].exists)
        XCTAssertTrue(app.staticTexts["scan-saved"].exists)
    }

    func testHistoricalReviewOpensSameGuidanceAndBackKeepsHistoryContext() {
        let app = launch(history: "seeded")
        app.buttons["scan-history"].tap()
        let row = app.buttons["history-open-33333333-3333-3333-3333-333333333333"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        openGuidance(firstID, app: app)
        XCTAssertEqual(app.staticTexts["guidance-recognized-text"].label, "Recognized text: EXIT")
        app.buttons["guidance-back"].tap()
        XCTAssertTrue(app.staticTexts["scan-review-heading"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["scan-saved"].exists)
        app.buttons["scan-review-done"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    func testMultipleFindingsKeepIndependentTextAndEvidence() {
        // Only one finding category is supported; exercise two distinct entities
        // and strengths without inventing another detector/category for a test.
        let app = launch(findings: "multiple-low-contrast")
        completeScan(app)
        for (id, text, strength) in [(firstID, "EXIT", "Moderate"), (secondID, "ELEVATOR", "Limited")] {
            openGuidance(id, app: app)
            XCTAssertEqual(app.staticTexts["guidance-recognized-text"].label, "Recognized text: \(text)")
            let evidence = app.staticTexts["Evidence strength: \(strength)"]
            reveal(evidence, in: app)
            XCTAssertTrue(evidence.isHittable)
            app.buttons["guidance-back"].tap()
            XCTAssertTrue(app.staticTexts["scan-review-heading"].waitForExistence(timeout: 5))
        }
    }

    func testGuidanceAtLargestDynamicTypeInLandscapeKeepsContentAndBackReachable() {
        // Establish orientation before launch so XCTest's gesture coordinates
        // and the Simulator surface agree throughout this layout test.
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(accessibilitySize: true)
        completeScan(app)
        openGuidance(firstID, app: app)
        reveal(app.staticTexts["guidance-limitations"], in: app)
        if !app.staticTexts["guidance-limitations"].isHittable {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertTrue(app.staticTexts["guidance-limitations"].isHittable, app.debugDescription)
        reveal(app.staticTexts["guidance-provenance"], in: app)
        XCTAssertTrue(app.staticTexts["guidance-provenance"].isHittable)
        let layout = XCTAttachment(screenshot: app.screenshot())
        layout.name = "Guidance at maximum text size in landscape"
        layout.lifetime = .keepAlways
        add(layout)
        XCTAssertTrue(app.buttons["guidance-back"].isHittable)
        app.buttons["guidance-back"].tap()
        XCTAssertTrue(app.staticTexts["scan-review-heading"].waitForExistence(timeout: 5))
    }

    private func completeScan(_ app: XCUIApplication) {
        app.buttons["start-scan"].tap()
        let finish = app.buttons["finish-scan"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()
        XCTAssertTrue(app.staticTexts["scan-review-heading"].waitForExistence(timeout: 5))
    }

    private func openGuidance(_ id: String, app: XCUIApplication) {
        let button = app.buttons["view-guidance-\(id)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        // XCTest scrolls this semantic control into view before activation.
        button.tap()
        XCTAssertTrue(app.staticTexts["guidance-title"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        // Use XCTest's native scroll-to-element behavior. Synthetic whole-view
        // swipes fail to move this Simulator's landscape scroll surface.
        // Callers still assert the actual text is visible/hittable afterward.
        if !element.isHittable { element.tap() }
    }

    private func launch(history: String = "empty", findings: String = "stable-low-contrast",
                        accessibilitySize: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-accesslens-onboarding-state", "complete", "-accesslens-history", history,
            "-accesslens-camera-authorization", "authorized", "-accesslens-scan-findings", findings]
        if accessibilitySize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        return app
    }
}
