import Foundation

/// Export allowlist: human-readable finalized content only. No scan/session,
/// analyzer, frame or geometry identity crosses into the report.
nonisolated struct AccessibilityReport: Equatable, Sendable {
    let formatVersion: Int
    let title: String
    let scanDate: Date
    let scanDateText: String
    let introduction: String
    let summary: String
    let qualitySummary: String?
    let findings: [AccessibilityReportFinding]
    let limitations: [String]

    var blocks: [AccessibilityReportBlock] {
        var result = [AccessibilityReportBlock(text: title, style: .title),
                      .init(text: scanDateText, style: .body),
                      .init(text: introduction, style: .body),
                      .init(text: ReportCopy.summary, style: .heading),
                      .init(text: summary, style: .body)]
        if let qualitySummary { result.append(.init(text: qualitySummary, style: .body)) }
        for (index, finding) in findings.enumerated() {
            result.append(.init(text: "\(index + 1). \(finding.title)", style: .findingHeading))
            for section in finding.sections {
                result.append(.init(text: section.title, style: .heading))
                result += section.paragraphs.map { .init(text: $0, style: .body) }
            }
        }
        result.append(.init(text: ReportCopy.limitations, style: .heading))
        result += limitations.map { .init(text: $0, style: .body) }
        return result
    }

    /// Also supplies an interoperable text representation without another
    /// export workflow or storing a second copy.
    var plainText: String { blocks.map(\.text).joined(separator: "\n\n") }
}

nonisolated struct AccessibilityReportFinding: Equatable, Sendable {
    let title: String
    let sections: [AccessibilityReportSection]
}

nonisolated struct AccessibilityReportSection: Equatable, Sendable {
    let title: String
    let paragraphs: [String]
}

nonisolated struct AccessibilityReportBlock: Equatable, Sendable {
    enum Style: Sendable { case title, findingHeading, heading, body }
    let text: String
    let style: Style
}

nonisolated enum ReportError: Error, Equatable, Sendable {
    case invalidReportData, renderingFailed, fileWriteFailed, exportUnavailable

    var message: String {
        switch self {
        case .invalidReportData:
            String(localized: "This scan’s report couldn’t be prepared. Return to the scan and try again.")
        case .renderingFailed, .fileWriteFailed, .exportUnavailable:
            String(localized: "The PDF couldn’t be prepared. Try again. Your saved scan is unchanged.")
        }
    }
}

nonisolated enum ReportCopy {
    static var title: String { String(localized: "AccessLens Accessibility Review") }
    static var summary: String { String(localized: "Summary") }
    static var observed: String { String(localized: "What AccessLens observed") }
    static var evidence: String { String(localized: "Evidence") }
    static var impact: String { String(localized: "Why it may matter") }
    static var checks: String { String(localized: "What to check") }
    static var improvements: String { String(localized: "Possible improvements") }
    static var limitations: String { String(localized: "Limitations") }
    static var introduction: String {
        String(localized: "AccessLens identifies potential accessibility barriers using on-device analysis. Findings are assistive observations and should be verified directly.")
    }
    static var disclaimer: String {
        String(localized: "AccessLens does not perform a formal accessibility inspection or certify compliance with accessibility standards.")
    }
    static var zeroFindings: String {
        String(localized: "No potential barriers were surfaced during this scan. This does not confirm that the environment is fully accessible.")
    }
    static var guidanceProvenance: String {
        String(localized: "Suggestions use AccessLens’s current guidance rules. They do not describe additional conditions detected during the scan.")
    }
    static var privacy: String {
        String(localized: "The report includes completed finding details and any recognized text retained in those findings. It contains no camera images or raw depth data. Sharing sends a copy only to the destination you choose.")
    }
}
