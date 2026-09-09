import XCTest
@testable import AccessLens

final class ScanReviewViewModelTests: XCTestCase {
    func testZeroFindingPresentationUsesTruthfulSummary() {
        let viewModel = ScanReviewViewModel(completedScan: completedScan(findings: []))

        XCTAssertEqual(viewModel.summary, "No potential issues were identified during this scan.")
        XCTAssertTrue(viewModel.isZeroFindingScan)
        XCTAssertTrue(viewModel.reviewIntroduction.contains("reviewed directly"))
    }

    func testOneAndMultipleFindingPresentationUseEvidenceCounts() {
        XCTAssertEqual(
            ScanReviewViewModel(completedScan: completedScan(findings: [finding()])).summary,
            "1 potential issue identified during this scan."
        )
        XCTAssertEqual(
            ScanReviewViewModel(completedScan: completedScan(findings: [finding(), finding()])).summary,
            "2 potential issues identified during this scan."
        )
    }

    private func completedScan(findings: [AccessibilityFinding]) -> CompletedScan {
        CompletedScan(
            sessionID: UUID(),
            startedAt: Date(timeIntervalSince1970: 1),
            completedAt: Date(timeIntervalSince1970: 2),
            findings: findings
        )
    }

    private func finding() -> AccessibilityFinding {
        AccessibilityFinding(
            category: .potentialLowContrastText,
            title: "Potential low contrast",
            explanation: "Text in this area may be difficult to distinguish from its background.",
            evidenceSummary: "Test evidence.",
            evidenceStrength: .strong,
            region: nil,
            firstObservedTime: 1,
            lastObservedTime: 3,
            supportingFrameRange: FindingFrameRange(
                first: AnalysisFrameSequence(rawValue: 1),
                last: AnalysisFrameSequence(rawValue: 3)
            ),
            supportingObservationCount: 5,
            sessionID: AnalysisSessionID(),
            sourceAnalyzerIDs: [AnalyzerIdentifier(rawValue: "vision.visual-contrast.v1")],
            relevantText: "EXIT",
            estimatedContrastRatio: nil
        )
    }
}
