import Foundation

/// Pure mapping. Equivalent scan, locale/time-zone and guidance rules produce
/// equivalent content. Export time and random IDs never affect report content.
nonisolated struct AccessibilityReportGenerator: Sendable {
    let guidanceProvider: any AccessibilityGuidanceProviding
    let locale: Locale
    let timeZone: TimeZone

    init(guidanceProvider: any AccessibilityGuidanceProviding = DeterministicAccessibilityGuidanceProvider(),
         locale: Locale = .current, timeZone: TimeZone = .current) {
        self.guidanceProvider = guidanceProvider
        self.locale = locale
        self.timeZone = timeZone
    }

    func generate(from scan: CompletedScan) throws -> AccessibilityReport {
        try Task.checkCancellation()
        do { try ScanStorageMapper.validate(scan) }
        catch { throw ReportError.invalidReportData }
        let ordered = scan.findings.sorted {
            let lhs = categoryOrder($0.category), rhs = categoryOrder($1.category)
            if lhs != rhs { return lhs < rhs }
            let leftStrength = strengthOrder($0.evidenceStrength), rightStrength = strengthOrder($1.evidenceStrength)
            if leftStrength != rightStrength { return leftStrength < rightStrength }
            return $0.id.uuidString < $1.id.uuidString
        }
        let findings = try ordered.map { finding in
            try Task.checkCancellation()
            return reportFinding(guidance: guidanceProvider.guidance(for: finding))
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        let date = formatter.string(from: scan.completedAt)
        return AccessibilityReport(
            formatVersion: 1, title: ReportCopy.title, scanDate: scan.completedAt,
            scanDateText: String(localized: "Scan completed: \(date)"),
            introduction: ReportCopy.introduction,
            summary: summary(for: ordered),
            qualitySummary: scan.qualitySummary.map {
                String(localized: "Capture quality: \($0.state.displayName). \($0.summary)")
            },
            findings: findings,
            limitations: [scan.limitationsSummary, ReportCopy.guidanceProvenance, ReportCopy.disclaimer]
        )
    }

    /// The report boundary also renders the guidance provider's general
    /// fallback, without assuming every future finding has known measurements.
    func reportFinding(guidance: AccessibilityGuidance) -> AccessibilityReportFinding {
        var observation = [guidance.observation.summary]
        if let text = guidance.observation.recognizedText {
            observation.append(String(localized: "Recognized text: \(text)"))
        }
        var evidence: [String] = []
        if let strength = guidance.evidenceStrength { evidence.append(strength.guidanceLabel) }
        if let summary = guidance.evidenceSummary, !summary.isEmpty { evidence.append(summary) }
        if let quality = guidance.qualityContext {
            evidence.append(String(localized: "Supporting capture quality: \(quality.state.displayName). \(quality.summary)"))
        }
        if let ratio = guidance.observation.estimatedContrastRatio {
            let value = ratio.value.formatted(.number.locale(locale).precision(.fractionLength(1)))
            evidence.append(String(localized: "Estimated text/background contrast: \(value):1"))
        }
        if let passage = guidance.observation.passageEvidence,
           passage.measurementMethod == .roomPlanLiDAR,
           passage.measurementQuality == .usable,
           let width = passage.estimatedWidth {
            let value = width.measurement.formatted(.measurement(width: .abbreviated, usage: .general).locale(locale))
            evidence.append(String(localized: "Estimated opening width: \(value)"))
            evidence.append(String(localized: "Measurement method: RoomPlan with LiDAR"))
            evidence.append(String(localized: "Measurement quality: \(passage.measurementQuality.displayName)"))
        }
        evidence.append(guidance.verificationNote)
        var sections = [
            AccessibilityReportSection(title: ReportCopy.observed, paragraphs: observation),
            .init(title: ReportCopy.evidence, paragraphs: evidence),
            .init(title: ReportCopy.impact, paragraphs: [guidance.interpretation, guidance.whyItMatters]),
            .init(title: ReportCopy.checks, paragraphs: numbered(guidance.whatToCheck))
        ]
        if !guidance.possibleImprovements.isEmpty {
            sections.append(.init(title: ReportCopy.improvements, paragraphs: numbered(guidance.possibleImprovements)))
        }
        sections.append(.init(title: ReportCopy.limitations, paragraphs: [guidance.limitations]))
        return AccessibilityReportFinding(title: guidance.title, sections: sections)
    }

    private func numbered(_ actions: [GuidanceAction]) -> [String] {
        actions.enumerated().map { String(localized: "\($0.offset + 1). \($0.element.text)") }
    }

    private func categoryOrder(_ category: AccessibilityFindingCategory) -> Int {
        switch category { case .potentialLowContrastText: 0; case .potentialNarrowPassage: 1 }
    }

    private func strengthOrder(_ strength: FindingEvidenceStrength) -> Int {
        switch strength { case .strong: 0; case .moderate: 1; case .limited: 2 }
    }

    private func summary(for findings: [AccessibilityFinding]) -> String {
        guard !findings.isEmpty else { return ReportCopy.zeroFindings }
        let count = findings.count
        let main = count == 1 ? String(localized: "1 potential issue was identified.")
            : String(localized: "\(count) potential issues were identified.")
        let counts = [FindingEvidenceStrength.strong, .moderate, .limited].compactMap { strength -> String? in
            let count = findings.filter { $0.evidenceStrength == strength }.count
            return count == 0 ? nil : String(localized: "\(strength.guidanceLabel): \(count)")
        }
        return ([main] + counts).joined(separator: "\n")
    }
}
