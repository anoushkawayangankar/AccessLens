import XCTest

@MainActor
final class AccessibilityIntelligenceUITests: XCTestCase {
    private let findingID = "22222222-2222-2222-2222-222222222222"

    func testLiveQualityGuidanceIsAccessibleAndCompletionShowsCategoricalSummary() {
        let app = launch(findings: "stable-low-contrast", quality: "limited")
        app.buttons["start-scan"].tap()
        let quality = app.descendants(matching: .any)["scan-quality-guidance"]
        XCTAssertTrue(quality.waitForExistence(timeout: 5))
        XCTAssertTrue(quality.label.contains("Capture guidance"))
        XCTAssertTrue(quality.label.contains("Hold the phone steady"))
        XCTAssertTrue(quality.label.contains("Limited"))

        let finish = app.buttons["finish-scan"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()
        let summary = app.staticTexts["scan-quality-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "Analysis quality: Limited")
    }

    func testFindingDetailShowsFusedEvidenceAndLowEvidenceWording() {
        let app = launch(findings: "fused-limited", quality: "limited")
        completeScan(app)
        let guidance = app.buttons["view-guidance-\(findingID)"]
        XCTAssertTrue(guidance.waitForExistence(timeout: 5))
        guidance.tap()

        XCTAssertTrue(app.staticTexts["Limited evidence"].waitForExistence(timeout: 5))
        let evidence = app.staticTexts["finding-evidence-summary"]
        XCTAssertTrue(evidence.waitForExistence(timeout: 5))
        XCTAssertTrue(evidence.label.contains("evidence was limited"))
        let context = app.staticTexts["finding-quality-context"]
        XCTAssertTrue(context.waitForExistence(timeout: 5))
        XCTAssertTrue(context.label.contains("limited sharpness"))
    }

    func testHistoricalFusedFindingRetainsQualityAndEvidenceExplanation() {
        let app = launch(history: "fused")
        app.buttons["scan-history"].tap()
        let row = app.buttons["history-open-33333333-3333-3333-3333-333333333333"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertEqual(app.staticTexts["scan-quality-summary"].label, "Analysis quality: Limited")
        let guidance = app.buttons["view-guidance-\(findingID)"]
        XCTAssertTrue(guidance.waitForExistence(timeout: 5))
        guidance.tap()
        XCTAssertTrue(app.staticTexts["finding-evidence-summary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["finding-quality-context"].exists)
    }

    private func completeScan(_ app: XCUIApplication) {
        app.buttons["start-scan"].tap()
        let finish = app.buttons["finish-scan"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()
        XCTAssertTrue(app.staticTexts["scan-review-heading"].waitForExistence(timeout: 5))
    }

    private func launch(
        history: String = "empty",
        findings: String? = nil,
        quality: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-accesslens-onboarding-state", "complete",
            "-accesslens-history", history,
            "-accesslens-camera-authorization", "authorized"
        ]
        if let findings { app.launchArguments += ["-accesslens-scan-findings", findings] }
        if let quality { app.launchArguments += ["-accesslens-scan-quality", quality] }
        app.launch()
        return app
    }
}
