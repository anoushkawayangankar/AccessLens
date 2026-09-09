import XCTest
@testable import AccessLens

final class ScanSessionWorkflowTests: XCTestCase {
    func testCompletionCreatesImmutableSnapshotWithExpectedFindings() throws {
        let startedAt = Date(timeIntervalSince1970: 100)
        let completedAt = Date(timeIntervalSince1970: 130)
        var workflow = ScanSessionWorkflow()
        let session = try XCTUnwrap(workflow.start(at: startedAt))
        XCTAssertEqual(workflow.lifecycleState, .scanning)

        XCTAssertNotNil(workflow.beginCompletion())
        let snapshot = try XCTUnwrap(workflow.complete(with: [finding()], at: completedAt))

        XCTAssertEqual(snapshot.sessionID, session.id)
        XCTAssertEqual(snapshot.startedAt, startedAt)
        XCTAssertEqual(snapshot.completedAt, completedAt)
        XCTAssertEqual(snapshot.findingCount, 1)
        XCTAssertEqual(workflow.lifecycleState, .completed)
    }

    func testZeroFindingScanCreatesAValidReviewSnapshot() throws {
        var workflow = ScanSessionWorkflow()
        _ = workflow.start(at: Date(timeIntervalSince1970: 10))
        _ = workflow.beginCompletion()

        let snapshot = try XCTUnwrap(workflow.complete(with: [], at: Date(timeIntervalSince1970: 20)))

        XCTAssertEqual(snapshot.findingCount, 0)
        XCTAssertTrue(snapshot.findings.isEmpty)
    }

    func testCompletionIsIdempotent() throws {
        var workflow = ScanSessionWorkflow()
        _ = workflow.start(at: Date(timeIntervalSince1970: 10))

        XCTAssertNotNil(workflow.beginCompletion())
        let first = try XCTUnwrap(workflow.complete(with: [finding()], at: Date(timeIntervalSince1970: 20)))
        XCTAssertNil(workflow.beginCompletion())
        XCTAssertNil(workflow.complete(with: [finding()], at: Date(timeIntervalSince1970: 30)))
        XCTAssertEqual(workflow.session?.id, first.sessionID)
    }

    func testDiscardDoesNotCreateCompletedSnapshot() {
        var workflow = ScanSessionWorkflow()
        _ = workflow.start(at: Date(timeIntervalSince1970: 10))
        workflow.discard()

        XCTAssertEqual(workflow.lifecycleState, .discarded)
        XCTAssertNil(workflow.beginCompletion())
    }

    func testNewScanAfterDiscardHasFreshIdentity() throws {
        var workflow = ScanSessionWorkflow()
        let first = try XCTUnwrap(workflow.start(at: Date(timeIntervalSince1970: 10)))
        workflow.discard()
        let second = try XCTUnwrap(workflow.start(at: Date(timeIntervalSince1970: 20)))

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(workflow.lifecycleState, .scanning)
    }

    func testSnapshotDoesNotChangeWhenSourceCollectionChanges() throws {
        var findings = [finding()]
        var workflow = ScanSessionWorkflow()
        _ = workflow.start(at: Date(timeIntervalSince1970: 10))
        _ = workflow.beginCompletion()
        let snapshot = try XCTUnwrap(workflow.complete(with: findings, at: Date(timeIntervalSince1970: 20)))

        findings.removeAll()

        XCTAssertEqual(snapshot.findingCount, 1)
    }

    private func finding() -> AccessibilityFinding {
        AccessibilityFinding(
            category: .potentialLowContrastText,
            title: "Potential low contrast",
            explanation: "Text in this area may be difficult to distinguish from its background.",
            evidenceSummary: "Repeated usable test evidence.",
            evidenceStrength: .moderate,
            region: NormalizedRegion(x: 0.1, y: 0.1, width: 0.2, height: 0.1),
            firstObservedTime: 1,
            lastObservedTime: 3,
            supportingFrameRange: FindingFrameRange(
                first: AnalysisFrameSequence(rawValue: 1),
                last: AnalysisFrameSequence(rawValue: 3)
            ),
            supportingObservationCount: 3,
            sessionID: AnalysisSessionID(),
            sourceAnalyzerIDs: [AnalyzerIdentifier(rawValue: "vision.visual-contrast.v1")],
            relevantText: "EXIT",
            estimatedContrastRatio: ContrastRatio(lighterLuminance: 0.2, darkerLuminance: 0.02)
        )
    }
}
