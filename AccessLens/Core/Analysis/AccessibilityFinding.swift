import Foundation

/// A session-scoped, framework-independent finding supported by bounded,
/// repeated evidence. It is not a persisted record and makes no compliance or
/// legal claim.
nonisolated struct AccessibilityFinding: Identifiable, Equatable, Sendable, Hashable {
    let id: UUID
    let category: AccessibilityFindingCategory
    let title: String
    let explanation: String
    let evidenceSummary: String
    let evidenceStrength: FindingEvidenceStrength
    let region: NormalizedRegion?
    let firstObservedTime: TimeInterval
    let lastObservedTime: TimeInterval
    let supportingFrameRange: FindingFrameRange
    let supportingObservationCount: Int
    let sessionID: AnalysisSessionID
    let sourceAnalyzerIDs: [AnalyzerIdentifier]
    let lifecycleState: FindingLifecycleState
    let relevantText: String?
    let estimatedContrastRatio: ContrastRatio?

    init(
        id: UUID = UUID(),
        category: AccessibilityFindingCategory,
        title: String,
        explanation: String,
        evidenceSummary: String,
        evidenceStrength: FindingEvidenceStrength,
        region: NormalizedRegion?,
        firstObservedTime: TimeInterval,
        lastObservedTime: TimeInterval,
        supportingFrameRange: FindingFrameRange,
        supportingObservationCount: Int,
        sessionID: AnalysisSessionID,
        sourceAnalyzerIDs: [AnalyzerIdentifier],
        lifecycleState: FindingLifecycleState = .active,
        relevantText: String?,
        estimatedContrastRatio: ContrastRatio?
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.explanation = explanation
        self.evidenceSummary = evidenceSummary
        self.evidenceStrength = evidenceStrength
        self.region = region
        self.firstObservedTime = firstObservedTime
        self.lastObservedTime = lastObservedTime
        self.supportingFrameRange = supportingFrameRange
        self.supportingObservationCount = supportingObservationCount
        self.sessionID = sessionID
        self.sourceAnalyzerIDs = sourceAnalyzerIDs.sorted { $0.rawValue < $1.rawValue }
        self.lifecycleState = lifecycleState
        self.relevantText = relevantText
        self.estimatedContrastRatio = estimatedContrastRatio
    }
}

/// Only categories backed by currently implemented analyzers belong here.
nonisolated enum AccessibilityFindingCategory: String, CaseIterable, Equatable, Sendable, Hashable {
    case potentialLowContrastText = "potentialLowContrastText"
}

/// Evidence strength communicates repeatability and usable evidence, not a
/// probability, legal conclusion, or raw Vision confidence.
nonisolated enum FindingEvidenceStrength: String, Equatable, Sendable, Hashable {
    case limited = "limited"
    case moderate = "moderate"
    case strong = "strong"
}

nonisolated enum FindingLifecycleState: String, Equatable, Sendable, Hashable {
    case active = "active"
}

nonisolated struct FindingFrameRange: Equatable, Sendable, Hashable {
    let first: AnalysisFrameSequence
    let last: AnalysisFrameSequence
}

/// Compact, UI-safe output from the analysis coordinator. It contains only
/// stabilized values; raw analyzer observations and camera buffers remain
/// inside the analysis subsystem.
nonisolated struct StabilizedAnalysisResult: Equatable, Sendable {
    let sessionID: AnalysisSessionID
    let frameSequence: AnalysisFrameSequence
    let findings: [AccessibilityFinding]
    let newlyPromotedFindingIDs: Set<UUID>
    let failures: [AnalysisFailure]
}

/// Geometry helpers intentionally operate in AccessLens's top-left normalized
/// region space. Invalid or non-overlapping regions never associate.
nonisolated enum NormalizedRegionAssociation {
    static func intersectionOverUnion(_ lhs: NormalizedRegion, _ rhs: NormalizedRegion) -> Double {
        guard isValid(lhs), isValid(rhs) else { return 0 }
        let left = max(lhs.x, rhs.x)
        let top = max(lhs.y, rhs.y)
        let right = min(lhs.x + lhs.width, rhs.x + rhs.width)
        let bottom = min(lhs.y + lhs.height, rhs.y + rhs.height)
        let intersection = max(0, right - left) * max(0, bottom - top)
        let union = lhs.width * lhs.height + rhs.width * rhs.height - intersection
        return union > 0 ? intersection / union : 0
    }

    static func isValid(_ region: NormalizedRegion) -> Bool {
        region.x.isFinite && region.y.isFinite && region.width.isFinite && region.height.isFinite
            && region.width > 0 && region.height > 0
    }
}

nonisolated enum FindingTextAssociation {
    /// Case and diacritic folding deliberately preserves words and spacing;
    /// this is identity matching, not fuzzy semantic matching.
    static func normalizedIdentity(_ text: String?) -> String? {
        guard let text else { return nil }
        let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return collapsed.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}
