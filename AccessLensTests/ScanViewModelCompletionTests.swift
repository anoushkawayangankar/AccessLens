import XCTest
@testable import AccessLens

@MainActor
final class ScanViewModelCompletionTests: XCTestCase {
    func testFinishStopsLiveAnalysisAndReturnsOneSnapshot() throws {
        let viewModel = makeViewModel(initialFindings: [finding()])
        viewModel.appear()

        let snapshot = try XCTUnwrap(viewModel.finishScan())

        XCTAssertEqual(snapshot.findingCount, 1)
        XCTAssertEqual(viewModel.scanLifecycleState, .completed)
        XCTAssertFalse(viewModel.isAnalyzingEnvironment)
        XCTAssertNil(viewModel.activeAnalysisSessionID)
        XCTAssertTrue(viewModel.activeFindings.isEmpty)
        XCTAssertNil(viewModel.finishScan())
    }

    func testLateResultAfterCompletionCannotAlterSnapshotOrLiveState() throws {
        let viewModel = makeViewModel(initialFindings: [finding()])
        viewModel.appear()
        let analysisSessionID = try XCTUnwrap(viewModel.activeAnalysisSessionID)
        let snapshot = try XCTUnwrap(viewModel.finishScan())

        viewModel.receive(StabilizedAnalysisResult(
            sessionID: analysisSessionID,
            frameSequence: AnalysisFrameSequence(rawValue: 99),
            findings: [finding()],
            newlyPromotedFindingIDs: [],
            failures: []
        ))

        XCTAssertEqual(snapshot.findingCount, 1)
        XCTAssertTrue(viewModel.activeFindings.isEmpty)
        XCTAssertEqual(viewModel.scanLifecycleState, .completed)
    }

    func testDiscardStopsAnalysisWithoutProducingACompletedSnapshot() {
        let viewModel = makeViewModel(initialFindings: [finding()])
        viewModel.appear()

        viewModel.discardScan()

        XCTAssertEqual(viewModel.scanLifecycleState, .discarded)
        XCTAssertFalse(viewModel.isAnalyzingEnvironment)
        XCTAssertNil(viewModel.activeAnalysisSessionID)
        XCTAssertNil(viewModel.finishScan())
    }

    private func makeViewModel(initialFindings: [AccessibilityFinding]) -> ScanViewModel {
        ScanViewModel(
            authorizationService: InMemoryCameraAuthorizationService(authorization: .authorized),
            sessionController: CameraSessionController(),
            analysisCoordinator: AnalysisCoordinator(),
            initialFindings: initialFindings,
            forceAnalysisPresentation: true,
            clock: FixedScanSessionClock(date: Date(timeIntervalSince1970: 100))
        )
    }

    private func finding() -> AccessibilityFinding {
        AccessibilityFinding(
            category: .potentialLowContrastText,
            title: "Potential low contrast",
            explanation: "Text in this area may be difficult to distinguish from its background.",
            evidenceSummary: "Test evidence.",
            evidenceStrength: .moderate,
            region: nil,
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
            estimatedContrastRatio: nil
        )
    }
}

private struct FixedScanSessionClock: ScanSessionTimeProviding {
    let date: Date

    func now() -> Date { date }
}
