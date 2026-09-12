import Foundation

/// Explicit mapping plus size/integrity validation. Unknown meanings are never
/// coerced into supported findings. Their records remain available for deletion.
nonisolated enum ScanStorageMapper {
    static let maximumFindings = 100
    static let maximumTextLength = 8_192

    static func validate(_ scan: CompletedScan) throws {
        guard scan.startedAt.timeIntervalSince1970.isFinite,
              scan.completedAt.timeIntervalSince1970.isFinite,
              scan.completedAt >= scan.startedAt,
              scan.findings.count <= maximumFindings,
              Set(scan.findings.map(\.id)).count == scan.findings.count,
              scan.limitationsSummary.count <= maximumTextLength else {
            throw ScanRepositoryError.invalidRecord
        }
        for finding in scan.findings {
            let strings = [finding.title, finding.explanation, finding.evidenceSummary, finding.relevantText ?? ""]
            guard strings.allSatisfy({ $0.count <= maximumTextLength }),
                  finding.firstObservedTime.isFinite, finding.lastObservedTime.isFinite,
                  finding.lastObservedTime >= finding.firstObservedTime,
                  finding.supportingObservationCount > 0,
                  finding.supportingFrameRange.last >= finding.supportingFrameRange.first,
                  finding.sourceAnalyzerIDs.count <= 32,
                  finding.sourceAnalyzerIDs.allSatisfy({ !$0.rawValue.isEmpty && $0.rawValue.count <= 256 }) else {
                throw ScanRepositoryError.invalidRecord
            }
            if let region = finding.region {
                guard NormalizedRegionAssociation.isValid(region), region.x >= 0, region.y >= 0,
                      region.x + region.width <= 1.000001, region.y + region.height <= 1.000001 else {
                    throw ScanRepositoryError.invalidRecord
                }
            }
            if let ratio = finding.estimatedContrastRatio {
                guard ratio.value.isFinite, (1...21).contains(ratio.value) else {
                    throw ScanRepositoryError.invalidRecord
                }
            }
            switch finding.category {
            case .potentialLowContrastText:
                guard finding.passageEvidence == nil else { throw ScanRepositoryError.invalidRecord }
            case .potentialNarrowPassage:
                guard finding.estimatedContrastRatio == nil,
                      let evidence = finding.passageEvidence,
                      let width = evidence.estimatedWidth,
                      width.meters.isFinite,
                      evidence.measurementMethod == .roomPlanLiDAR,
                      evidence.measurementQuality == .usable else {
                    throw ScanRepositoryError.invalidRecord
                }
            }
        }
    }

    static func stored(_ scan: CompletedScan) throws -> ScanStorageSchemaV2.StoredScan {
        try validate(scan)
        return ScanStorageSchemaV2.StoredScan(
            id: scan.id, startedAt: scan.startedAt, completedAt: scan.completedAt,
            limitations: scan.limitationsSummary,
            findings: scan.findings.enumerated().map { ScanStorageSchemaV2.StoredFinding($0.element, position: $0.offset) }
        )
    }

    static func domain(_ stored: ScanStorageSchemaV2.StoredScan) throws -> CompletedScan {
        guard stored.recordVersion == 1 || stored.recordVersion == 2 else {
            throw ScanRepositoryError.unsupportedRecord
        }
        guard stored.findings.count <= maximumFindings,
              stored.findingCount == stored.findings.count else { throw ScanRepositoryError.invalidRecord }
        let ordered = stored.findings.sorted { $0.position < $1.position }
        guard ordered.enumerated().allSatisfy({ $0.offset == $0.element.position }) else {
            throw ScanRepositoryError.invalidRecord
        }
        let scan = CompletedScan(
            sessionID: stored.id, startedAt: stored.startedAt, completedAt: stored.completedAt,
            findings: try ordered.map(domain), limitationsSummary: stored.limitations
        )
        try validate(scan)
        return scan
    }

    private static func domain(_ stored: ScanStorageSchemaV2.StoredFinding) throws -> AccessibilityFinding {
        guard let category = AccessibilityFindingCategory(rawValue: stored.category),
              let strength = FindingEvidenceStrength(rawValue: stored.evidenceStrength),
              let lifecycle = FindingLifecycleState(rawValue: stored.lifecycle) else {
            throw ScanRepositoryError.unsupportedRecord
        }
        guard let first = UInt64(stored.firstSequence), let last = UInt64(stored.lastSequence) else {
            throw ScanRepositoryError.invalidRecord
        }
        let coordinates = [stored.regionX, stored.regionY, stored.regionWidth, stored.regionHeight]
        var region: NormalizedRegion?
        if coordinates.contains(where: { $0 != nil }) {
            guard let x = stored.regionX, let y = stored.regionY,
                  let width = stored.regionWidth, let height = stored.regionHeight else {
                throw ScanRepositoryError.invalidRecord
            }
            region = NormalizedRegion(x: x, y: y, width: width, height: height)
        }
        let ratio: ContrastRatio?
        if let value = stored.estimatedContrast {
            guard let valid = ContrastRatio(estimatedValue: value) else { throw ScanRepositoryError.invalidRecord }
            ratio = valid
        } else { ratio = nil }
        let passageValues: [Any?] = [
            stored.passageWidthMeters,
            stored.passageMeasurementMethod,
            stored.passageMeasurementQuality
        ]
        let passageEvidence: PassageFindingEvidence?
        if passageValues.contains(where: { $0 != nil }) {
            guard let meters = stored.passageWidthMeters,
                  let width = PassageWidth(meters: meters),
                  let methodRaw = stored.passageMeasurementMethod,
                  let method = PassageMeasurementMethod(rawValue: methodRaw),
                  let qualityRaw = stored.passageMeasurementQuality,
                  let quality = PassageMeasurementQuality(rawValue: qualityRaw) else {
                throw ScanRepositoryError.invalidRecord
            }
            passageEvidence = PassageFindingEvidence(
                estimatedWidth: width,
                measurementMethod: method,
                measurementQuality: quality
            )
        } else {
            passageEvidence = nil
        }
        return AccessibilityFinding(
            id: stored.id, category: category, title: stored.title,
            explanation: stored.explanation, evidenceSummary: stored.evidenceSummary,
            evidenceStrength: strength, region: region,
            firstObservedTime: stored.firstObservedTime, lastObservedTime: stored.lastObservedTime,
            supportingFrameRange: FindingFrameRange(first: .init(rawValue: first), last: .init(rawValue: last)),
            supportingObservationCount: stored.supportingObservationCount,
            sessionID: AnalysisSessionID(rawValue: stored.analysisSessionID),
            sourceAnalyzerIDs: stored.sourceAnalyzerIDs.map { AnalyzerIdentifier(rawValue: $0) },
            lifecycleState: lifecycle, relevantText: stored.relevantText,
            estimatedContrastRatio: ratio, passageEvidence: passageEvidence
        )
    }
}
