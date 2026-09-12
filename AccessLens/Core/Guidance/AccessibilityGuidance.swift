import Foundation

/// Current application advice derived from finalized evidence. Never persisted
/// as if it were an observation, and never owns camera or storage resources.
nonisolated struct AccessibilityGuidance: Equatable, Sendable {
    let ruleID: String
    let ruleVersion: Int
    let title: String
    let observation: GuidanceObservation
    let interpretation: String
    let whyItMatters: String
    let whatToCheck: [GuidanceAction]
    let possibleImprovements: [GuidanceAction]
    let limitations: String
    let evidenceStrength: FindingEvidenceStrength?
    let verificationNote: String
}

nonisolated struct GuidanceObservation: Equatable, Sendable {
    let summary: String
    let recognizedText: String?
    let estimatedContrastRatio: ContrastRatio?
    let passageEvidence: PassageFindingEvidence?

    init(
        summary: String,
        recognizedText: String?,
        estimatedContrastRatio: ContrastRatio?,
        passageEvidence: PassageFindingEvidence? = nil
    ) {
        self.summary = summary
        self.recognizedText = recognizedText
        self.estimatedContrastRatio = estimatedContrastRatio
        self.passageEvidence = passageEvidence
    }
}

/// Semantic IDs keep action identity independent of translated display text.
nonisolated struct GuidanceAction: Identifiable, Equatable, Sendable {
    enum ID: String, Sendable {
        case viewingPosition, representativeLighting, confirmText
        case increaseContrast, simplifyBackground, recheckLighting, reviewDirectly
        case measureClearOpening, inspectNarrowestPoint, removeTemporaryObstructions
        case improveClearance, perpendicularRecapture
    }
    let id: ID
    let text: String
}

nonisolated protocol AccessibilityGuidanceProviding: Sendable {
    func guidance(for finding: AccessibilityFinding) -> AccessibilityGuidance
}
