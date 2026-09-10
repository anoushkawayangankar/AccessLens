import Foundation

nonisolated enum ScanReviewContext: Sendable { case newlyCompleted, historical }

/// Presentation-only transformation of an immutable completed scan. It has no
/// camera, analyzer, persistence, or navigation dependency.
nonisolated struct ScanReviewViewModel: Sendable {
    let completedScan: CompletedScan

    var summary: String {
        switch completedScan.findingCount {
        case 0:
            "No potential issues were identified during this scan."
        case 1:
            "1 potential issue identified during this scan."
        default:
            "\(completedScan.findingCount) potential issues identified during this scan."
        }
    }

    var isZeroFindingScan: Bool {
        completedScan.findings.isEmpty
    }

    var reviewIntroduction: String {
        "These results are based on camera observations and should be reviewed directly."
    }
}
