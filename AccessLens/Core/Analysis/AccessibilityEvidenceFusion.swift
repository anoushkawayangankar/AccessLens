import Foundation
import OSLog

/// Stable, future-safe analyzer provenance. Unknown identifiers remain
/// explicit instead of being guessed as a known analyzer type.
nonisolated enum AccessibilityAnalyzerSource: String, CaseIterable, Equatable, Sendable, Hashable {
    case text
    case contrast
    case passage
    case unknown

    static func source(for identifier: AnalyzerIdentifier) -> AccessibilityAnalyzerSource {
        if identifier.rawValue.hasPrefix("vision.text.") { return .text }
        if identifier.rawValue.hasPrefix("vision.visual-contrast.") { return .contrast }
        if identifier.rawValue.hasPrefix("roomplan.passage.") { return .passage }
        return .unknown
    }
}

/// Analyzer-specific confidence bands are used only to weight repeated
/// evidence. They are never displayed as probability or certainty.
nonisolated enum NormalizedEvidenceConfidence: String, Equatable, Sendable, Hashable {
    case weak
    case moderate
    case strong
}

nonisolated struct AnalyzerConfidenceNormalizationPolicy: Equatable, Sendable {
    func confidence(for candidate: FindingCandidate) -> NormalizedEvidenceConfidence? {
        switch candidate.category {
        case .potentialLowContrastText, .contrastLikelyAdequate:
            guard candidate.contrastEvidenceQuality == .usable,
                  let confidence = candidate.rawFrameworkConfidence,
                  confidence.isFinite, confidence >= 0.35 else { return nil }
            // OCR confidence is used only as recognition-quality evidence. The
            // contrast estimate and spatial relation remain separate inputs.
            if confidence >= 0.75 { return .strong }
            if confidence >= 0.55 { return .moderate }
            return .weak
        case .potentialNarrowPassage:
            guard candidate.passageEvidence?.measurementMethod == .roomPlanLiDAR,
                  candidate.passageEvidence?.measurementQuality == .usable,
                  candidate.passageEvidence?.estimatedWidth != nil else { return nil }
            return .strong
        case .environmentalSignage, .unclassified:
            return nil
        }
    }
}

nonisolated enum AccessibilityEvidencePolarity: String, Equatable, Sendable, Hashable {
    case supportsFinding
    case conflictsWithFinding
}

/// Compact quality context retained with a finalized finding. It is safe for
/// persistence and historical display and contains no frame-level metrics.
nonisolated struct FindingQualityContext: Equatable, Sendable, Hashable {
    let state: ScanQualityState
    let summary: String
}

/// Central framework-independent evidence shape. It represents stabilized
/// analyzer support before a user-facing finding is finalized.
nonisolated struct AccessibilityEvidence: Identifiable, Equatable, Sendable, Hashable {
    let id: UUID
    let sessionID: AnalysisSessionID
    let category: AccessibilityFindingCategory
    let analyzerSources: Set<AccessibilityAnalyzerSource>
    let sourceAnalyzerIDs: [AnalyzerIdentifier]
    let firstObservedTime: TimeInterval
    let lastObservedTime: TimeInterval
    let supportingFrameRange: FindingFrameRange
    let region: NormalizedRegion?
    let strength: FindingEvidenceStrength
    let normalizedConfidence: NormalizedEvidenceConfidence
    let qualityContext: FindingQualityContext
    let supportingObservationCount: Int
    let polarity: AccessibilityEvidencePolarity
    let sourceSummary: String
    let title: String
    let explanation: String
    let relevantText: String?
    let estimatedContrastRatio: ContrastRatio?
    let passageEvidence: PassageFindingEvidence?

    init(
        id: UUID = UUID(),
        sessionID: AnalysisSessionID,
        category: AccessibilityFindingCategory,
        analyzerSources: Set<AccessibilityAnalyzerSource>,
        sourceAnalyzerIDs: [AnalyzerIdentifier],
        firstObservedTime: TimeInterval,
        lastObservedTime: TimeInterval,
        supportingFrameRange: FindingFrameRange,
        region: NormalizedRegion?,
        strength: FindingEvidenceStrength,
        normalizedConfidence: NormalizedEvidenceConfidence? = nil,
        qualityContext: FindingQualityContext,
        supportingObservationCount: Int,
        polarity: AccessibilityEvidencePolarity = .supportsFinding,
        sourceSummary: String,
        title: String,
        explanation: String,
        relevantText: String?,
        estimatedContrastRatio: ContrastRatio?,
        passageEvidence: PassageFindingEvidence?
    ) {
        self.id = id
        self.sessionID = sessionID
        self.category = category
        self.analyzerSources = analyzerSources
        self.sourceAnalyzerIDs = Array(Set(sourceAnalyzerIDs)).sorted { $0.rawValue < $1.rawValue }
        self.firstObservedTime = firstObservedTime
        self.lastObservedTime = lastObservedTime
        self.supportingFrameRange = supportingFrameRange
        self.region = region
        self.strength = strength
        self.normalizedConfidence = normalizedConfidence ?? {
            switch strength {
            case .limited: .weak
            case .moderate: .moderate
            case .strong: .strong
            }
        }()
        self.qualityContext = qualityContext
        self.supportingObservationCount = supportingObservationCount
        self.polarity = polarity
        self.sourceSummary = sourceSummary
        self.title = title
        self.explanation = explanation
        self.relevantText = relevantText
        self.estimatedContrastRatio = estimatedContrastRatio
        self.passageEvidence = passageEvidence
    }
}

nonisolated enum AccessibilityFusionDecision: String, Equatable, Sendable {
    case rejected
    case provisional
    case surfaced
}

nonisolated struct AccessibilityFusionResult: Equatable, Sendable {
    let findings: [AccessibilityFinding]
    let decisions: [UUID: AccessibilityFusionDecision]
}

nonisolated struct AccessibilityEvidenceFusionPolicy: Equatable, Sendable {
    let maximumEvidence: Int
    let maximumFindings: Int
    let temporalAssociationWindow: TimeInterval
    let maximumFrameSequenceDistance: UInt64
    let minimumRegionIntersectionOverUnion: Double
    let minimumEffectiveSupport: Double
    let maximumConflictFraction: Double

    init(
        maximumEvidence: Int = 12,
        maximumFindings: Int = 6,
        temporalAssociationWindow: TimeInterval = 5,
        maximumFrameSequenceDistance: UInt64 = 600,
        minimumRegionIntersectionOverUnion: Double = 0.5,
        minimumEffectiveSupport: Double = 3,
        maximumConflictFraction: Double = 0.5
    ) {
        self.maximumEvidence = maximumEvidence
        self.maximumFindings = maximumFindings
        self.temporalAssociationWindow = temporalAssociationWindow
        self.maximumFrameSequenceDistance = maximumFrameSequenceDistance
        self.minimumRegionIntersectionOverUnion = minimumRegionIntersectionOverUnion
        self.minimumEffectiveSupport = minimumEffectiveSupport
        self.maximumConflictFraction = maximumConflictFraction
    }
}

/// Stateless finalization of a bounded stabilized-evidence snapshot. It merges
/// only category-compatible, spatially and temporally related evidence.
nonisolated struct AccessibilityEvidenceFusionEngine: Sendable {
    private struct Group {
        var evidence: [AccessibilityEvidence]
    }

    let policy: AccessibilityEvidenceFusionPolicy

    init(policy: AccessibilityEvidenceFusionPolicy = AccessibilityEvidenceFusionPolicy()) {
        self.policy = policy
    }

    func fuse(_ input: [AccessibilityEvidence], sessionID: AnalysisSessionID) -> AccessibilityFusionResult {
        let bounded = input
            .filter {
                $0.sessionID == sessionID
                    && $0.qualityContext.state != .unusable
                    && isDefensible($0)
            }
            .sorted {
                if $0.lastObservedTime != $1.lastObservedTime { return $0.lastObservedTime < $1.lastObservedTime }
                return $0.id.uuidString < $1.id.uuidString
            }
            .suffix(policy.maximumEvidence)

        var groups: [Group] = []
        for evidence in bounded {
            if let index = groups.firstIndex(where: { associates(evidence, with: $0.evidence) }) {
                groups[index].evidence.append(evidence)
                AppLog.analysis.debug("Merged duplicate stabilized evidence")
            } else {
                groups.append(Group(evidence: [evidence]))
            }
        }

        var decisions: [UUID: AccessibilityFusionDecision] = [:]
        var findings: [AccessibilityFinding] = []
        for group in groups {
            let decision = decision(for: group.evidence)
            for evidence in group.evidence { decisions[evidence.id] = decision }
            guard decision == .surfaced, let finding = makeFinding(from: group.evidence) else {
                if decision == .rejected { AppLog.analysis.debug("Evidence rejected by fusion policy") }
                continue
            }
            findings.append(finding)
            AppLog.analysis.info("Fused finding surfaced")
        }
        if findings.count > policy.maximumFindings {
            findings.removeFirst(findings.count - policy.maximumFindings)
        }
        return AccessibilityFusionResult(findings: findings, decisions: decisions)
    }

    private func associates(_ candidate: AccessibilityEvidence, with group: [AccessibilityEvidence]) -> Bool {
        guard let latest = group.last, latest.category == candidate.category else { return false }
        guard abs(candidate.firstObservedTime - latest.lastObservedTime) <= policy.temporalAssociationWindow else {
            return false
        }
        let candidateSequence = candidate.supportingFrameRange.first.rawValue
        let latestSequence = latest.supportingFrameRange.last.rawValue
        let sequenceDistance = candidateSequence >= latestSequence
            ? candidateSequence - latestSequence
            : latestSequence - candidateSequence
        guard sequenceDistance <= policy.maximumFrameSequenceDistance else { return false }
        if candidate.id == latest.id { return true }
        guard let lhs = latest.region, let rhs = candidate.region,
              NormalizedRegionAssociation.intersectionOverUnion(lhs, rhs) >= policy.minimumRegionIntersectionOverUnion else {
            return false
        }
        if candidate.category == .potentialLowContrastText {
            return FindingTextAssociation.normalizedIdentity(candidate.relevantText)
                == FindingTextAssociation.normalizedIdentity(latest.relevantText)
        }
        return true
    }

    private func isDefensible(_ evidence: AccessibilityEvidence) -> Bool {
        guard evidence.supportingObservationCount > 0,
              evidence.firstObservedTime.isFinite,
              evidence.lastObservedTime.isFinite,
              evidence.lastObservedTime >= evidence.firstObservedTime else { return false }
        switch evidence.category {
        case .potentialLowContrastText:
            return evidence.analyzerSources.contains(.text)
                && evidence.analyzerSources.contains(.contrast)
                && FindingTextAssociation.normalizedIdentity(evidence.relevantText) != nil
                && evidence.estimatedContrastRatio != nil
                && evidence.passageEvidence == nil
        case .potentialNarrowPassage:
            return evidence.analyzerSources.contains(.passage)
                && evidence.passageEvidence?.measurementMethod == .roomPlanLiDAR
                && evidence.passageEvidence?.measurementQuality == .usable
                && evidence.passageEvidence?.estimatedWidth != nil
                && evidence.estimatedContrastRatio == nil
        }
    }

    private func decision(for group: [AccessibilityEvidence]) -> AccessibilityFusionDecision {
        let support = group.filter { $0.polarity == .supportsFinding }
        guard !support.isEmpty else { return .rejected }
        let supportWeight = min(6, support.reduce(0) { result, evidence in
            result + Double(min(6, evidence.supportingObservationCount))
                * ((evidence.qualityContext.state == .good && evidence.normalizedConfidence != .weak) ? 1 : 0.5)
        })
        let conflictWeight = min(6, group
            .filter { $0.polarity == .conflictsWithFinding }
            .reduce(0) { $0 + Double(min(6, $1.supportingObservationCount)) })
        guard supportWeight >= policy.minimumEffectiveSupport else { return .provisional }
        if conflictWeight > supportWeight * policy.maximumConflictFraction { return .rejected }
        return .surfaced
    }

    private func makeFinding(from group: [AccessibilityEvidence]) -> AccessibilityFinding? {
        let support = group.filter { $0.polarity == .supportsFinding }
        guard let base = support.min(by: {
            if $0.firstObservedTime != $1.firstObservedTime { return $0.firstObservedTime < $1.firstObservedTime }
            return $0.id.uuidString < $1.id.uuidString
        }) else { return nil }
        let allSources = Array(Set(support.flatMap(\.sourceAnalyzerIDs))).sorted { $0.rawValue < $1.rawValue }
        let count = min(6, support.reduce(0) { $0 + $1.supportingObservationCount })
        let goodCaptureSupport = min(count, support.filter { $0.qualityContext.state == .good }
            .reduce(0) { $0 + $1.supportingObservationCount })
        let reliableSupport = min(count, support.filter {
            $0.qualityContext.state == .good && $0.normalizedConfidence != .weak
        }.reduce(0) { $0 + $1.supportingObservationCount })
        let limitedCaptureSupport = max(0, count - goodCaptureSupport)
        let conflicts = min(6, group.filter { $0.polarity == .conflictsWithFinding }
            .reduce(0) { $0 + $1.supportingObservationCount })
        let proposedStrength: FindingEvidenceStrength
        if count >= 5, reliableSupport >= 5, conflicts <= 1 {
            proposedStrength = .strong
        } else if reliableSupport >= 3 {
            proposedStrength = .moderate
        } else {
            proposedStrength = .limited
        }
        // Fusion may corroborate support, but duplicate grouping must never
        // upgrade beyond the strongest stabilized input assessment.
        let strength = cappedStrength(proposedStrength, by: support.map(\.strength))
        let quality = FindingQualityContext(
            state: goodCaptureSupport >= 3 && goodCaptureSupport >= limitedCaptureSupport ? .good : .limited,
            summary: goodCaptureSupport >= 3 && goodCaptureSupport >= limitedCaptureSupport
                ? String(localized: "Capture quality was adequate across the supporting observations.")
                : String(localized: "Some supporting observations had limited sharpness, exposure, or framing. Check this possible issue directly.")
        )
        let summary: String
        switch base.category {
        case .potentialLowContrastText:
            summary = strength == .limited
                ? String(localized: "AccessLens observed a possible low-contrast area, but evidence was limited. Check the area directly.")
                : String(localized: "Recognized signage and low-contrast evidence overlapped in a consistent image region across repeated observations.")
        case .potentialNarrowPassage:
            summary = strength == .limited
                ? String(localized: "AccessLens observed a possible narrow passage, but capture evidence was limited. Verify the opening directly.")
                : String(localized: "Repeated usable LiDAR-supported geometry referred to a consistent passage region; inconsistent measurements were excluded.")
        }
        return AccessibilityFinding(
            id: base.id,
            category: base.category,
            title: base.title,
            explanation: base.explanation,
            evidenceSummary: summary,
            evidenceStrength: strength,
            region: base.region,
            firstObservedTime: support.map(\.firstObservedTime).min() ?? base.firstObservedTime,
            lastObservedTime: support.map(\.lastObservedTime).max() ?? base.lastObservedTime,
            supportingFrameRange: FindingFrameRange(
                first: support.map(\.supportingFrameRange.first).min() ?? base.supportingFrameRange.first,
                last: support.map(\.supportingFrameRange.last).max() ?? base.supportingFrameRange.last
            ),
            supportingObservationCount: count,
            sessionID: base.sessionID,
            sourceAnalyzerIDs: allSources,
            relevantText: base.relevantText,
            estimatedContrastRatio: base.estimatedContrastRatio,
            passageEvidence: base.passageEvidence,
            qualityContext: quality
        )
    }

    private func cappedStrength(
        _ proposed: FindingEvidenceStrength,
        by input: [FindingEvidenceStrength]
    ) -> FindingEvidenceStrength {
        let maximum: FindingEvidenceStrength
        if input.contains(.strong) {
            maximum = .strong
        } else if input.contains(.moderate) {
            maximum = .moderate
        } else {
            maximum = .limited
        }
        switch (proposed, maximum) {
        case (.strong, .moderate): return .moderate
        case (.strong, .limited), (.moderate, .limited): return .limited
        default: return proposed
        }
    }
}
