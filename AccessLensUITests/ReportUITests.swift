import XCTest

@MainActor
final class ReportUITests: XCTestCase {
    func testCompletedScanOpensReportWithMultipleFindingsAndBack() {
        let app = launch(findings: "multiple-low-contrast")
        complete(app)
        openReport(app)
        XCTAssertTrue(app.staticTexts["report-summary"].label.contains("2 potential issues"))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Report preview portrait"
        attachment.lifetime = .keepAlways
        add(attachment)
        reveal(app.staticTexts["report-finding-0"], in: app)
        reveal(app.staticTexts["report-finding-1"], in: app)
        app.buttons["report-back"].tap()
        XCTAssertTrue(app.staticTexts["scan-review-heading"].waitForExistence(timeout: 5))
    }

    func testHistoryUsesSameReportWithFusedEvidenceAndQuality() {
        let app = launch(history: "fused")
        app.buttons["scan-history"].tap()
        let row = app.buttons["history-open-33333333-3333-3333-3333-333333333333"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        openReport(app)
        XCTAssertTrue(app.staticTexts["report-quality"].label.contains("Limited"))
        reveal(app.staticTexts["AccessLens observed a possible low-contrast area, but evidence was limited. Check the area directly."], in: app)
        app.buttons["report-back"].tap()
        app.buttons["scan-review-done"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    func testZeroFindingsReportHasLimitationsAndCanPrepareShareablePDF() {
        let app = launch(findings: "analyzing-empty")
        complete(app)
        openReport(app)
        XCTAssertTrue(app.staticTexts["report-summary"].label.contains("does not confirm"))
        XCTAssertFalse(app.staticTexts["report-finding-0"].exists)
        let prepare = app.buttons["report-export"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 5))
        prepare.tap()
        XCTAssertTrue(app.buttons["report-share"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["report-share"].label, "Share Report")
        // Do not invoke an external destination. Native share availability is
        // exercised here after a real local PDF has been prepared.
    }

    func testExportFailureOffersAccessibleRetryAndKeepsReport() {
        let app = launch(failure: true)
        complete(app)
        openReport(app)
        app.buttons["report-export"].tap()
        XCTAssertTrue(app.staticTexts["report-export-error"].waitForExistence(timeout: 5))
        let retry = app.buttons["report-export-retry"]
        XCTAssertTrue(retry.isHittable)
        retry.tap()
        XCTAssertTrue(app.staticTexts["report-export-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["report-title"].exists)
        XCTAssertFalse(app.buttons["report-share"].exists)
    }

    func testReportAtLargestDynamicTypeInLandscapeKeepsActionsAndEndReachable() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(largeText: true)
        complete(app)
        openReport(app)
        app.buttons["report-export"].tap()
        XCTAssertTrue(app.buttons["report-share"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["report-share"].isHittable)
        reveal(app.staticTexts["report-limitations"], in: app)
        XCTAssertTrue(app.buttons["report-back"].isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Report maximum Dynamic Type landscape"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testReportAccessibilityAuditForVisibleContent() throws {
        let app = launch()
        complete(app)
        openReport(app)
        try app.performAccessibilityAudit(for: [.contrast, .sufficientElementDescription, .dynamicType, .textClipped])
    }

    private func complete(_ app: XCUIApplication) {
        app.buttons["start-scan"].tap()
        XCTAssertTrue(app.buttons["finish-scan"].waitForExistence(timeout: 5))
        app.buttons["finish-scan"].tap()
        XCTAssertTrue(app.staticTexts["scan-review-heading"].waitForExistence(timeout: 5))
    }

    private func openReport(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["view-report"].waitForExistence(timeout: 5))
        app.buttons["view-report"].tap()
        XCTAssertTrue(app.staticTexts["report-title"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        // A lazy card does not exist in the AX tree until scrolling admits it.
        // Once present, native scroll-to-element also handles large text and
        // the second layout pass as estimated lazy heights become real heights.
        for _ in 0..<20 where !element.exists { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(element.exists)
        guard element.exists else { return }
        for _ in 0..<3 where !element.isHittable { element.tap() }
        XCTAssertTrue(element.isHittable)
    }

    private func launch(history: String = "empty", findings: String = "stable-low-contrast",
                        failure: Bool = false, largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-accesslens-onboarding-state", "complete", "-accesslens-history", history,
            "-accesslens-camera-authorization", "authorized", "-accesslens-scan-findings", findings]
        if failure { app.launchArguments += ["-accesslens-export-failure"] }
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        return app
    }
}
