import Foundation
@testable import AccessLens

enum ScanPersistenceFixtures {
    static func scan(id: UUID = UUID(), completedAt: TimeInterval = 200, findingCount: Int = 1) -> CompletedScan {
        let analysisID = AnalysisSessionID()
        let findings = (0..<findingCount).map { index in
            AccessibilityFinding(
                category: .potentialLowContrastText, title: "Potential low contrast",
                explanation: "Text may be difficult to distinguish from its background.",
                evidenceSummary: "Repeated usable evidence from three analyses.",
                evidenceStrength: index == 0 ? .moderate : .strong,
                region: NormalizedRegion(x: 0.1, y: 0.2, width: 0.3, height: 0.1),
                firstObservedTime: 1.25, lastObservedTime: 3.5,
                supportingFrameRange: FindingFrameRange(first: .init(rawValue: 20), last: .init(rawValue: UInt64.max)),
                supportingObservationCount: 3, sessionID: analysisID,
                sourceAnalyzerIDs: [.init(rawValue: "vision.text.v1"), .init(rawValue: "vision.visual-contrast.v1")],
                relevantText: index == 0 ? "EXIT" : "ELEVATOR",
                estimatedContrastRatio: ContrastRatio(lighterLuminance: 0.09, darkerLuminance: 0.02)
            )
        }
        return CompletedScan(sessionID: id, startedAt: Date(timeIntervalSince1970: completedAt - 30),
                             completedAt: Date(timeIntervalSince1970: completedAt), findings: findings)
    }
}
