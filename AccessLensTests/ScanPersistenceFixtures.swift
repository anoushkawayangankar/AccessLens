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

    static func passageFinding(
        id: UUID = UUID(),
        sessionID: AnalysisSessionID = AnalysisSessionID(),
        widthMeters: Double = 0.84
    ) -> AccessibilityFinding {
        AccessibilityFinding(
            id: id,
            category: .potentialNarrowPassage,
            title: "Potential narrow passage",
            explanation: "The visible clear opening may offer limited usable space.",
            evidenceSummary: "A similar opening was observed across three analyses with a median estimated width of 0.84 meters.",
            evidenceStrength: .moderate,
            region: NormalizedRegion(x: 0.2, y: 0.1, width: 0.4, height: 0.8),
            firstObservedTime: 1,
            lastObservedTime: 3,
            supportingFrameRange: FindingFrameRange(first: .init(rawValue: 1), last: .init(rawValue: 3)),
            supportingObservationCount: 3,
            sessionID: sessionID,
            sourceAnalyzerIDs: [.init(rawValue: "roomplan.passage.v1")],
            relevantText: nil,
            estimatedContrastRatio: nil,
            passageEvidence: PassageFindingEvidence(
                estimatedWidth: PassageWidth(meters: widthMeters),
                measurementMethod: .roomPlanLiDAR,
                measurementQuality: .usable
            )
        )
    }

    static func passageScan(id: UUID = UUID()) -> CompletedScan {
        let sessionID = AnalysisSessionID(rawValue: id)
        return CompletedScan(
            sessionID: id,
            startedAt: Date(timeIntervalSince1970: 300),
            completedAt: Date(timeIntervalSince1970: 330),
            findings: [passageFinding(sessionID: sessionID)]
        )
    }
}
