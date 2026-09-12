import Foundation

/// Pure category rules. Locale-aware complete sentences are resolved when
/// guidance opens. Historical evidence stays unchanged as rule wording evolves.
nonisolated struct DeterministicAccessibilityGuidanceProvider: AccessibilityGuidanceProviding {
    func guidance(for finding: AccessibilityFinding) -> AccessibilityGuidance {
        switch finding.category {
        case .potentialLowContrastText:
            return lowContrastGuidance(for: finding)
        case .potentialNarrowPassage:
            return narrowPassageGuidance(for: finding)
        }
    }

    /// Safe boundary for a future caller with an unsupported category. M9's
    /// repository still rejects unknown stored meanings; it is not loosened here.
    func fallbackGuidance() -> AccessibilityGuidance {
        AccessibilityGuidance(
            ruleID: "general.review", ruleVersion: 1,
            title: String(localized: "Review this finding"),
            observation: GuidanceObservation(
                summary: String(localized: "This version of AccessLens cannot interpret this finding’s category."),
                recognizedText: nil, estimatedContrastRatio: nil
            ),
            interpretation: String(localized: "Review the environment directly before drawing a conclusion."),
            whyItMatters: String(localized: "The available information is not enough to explain this finding’s accessibility relevance."),
            whatToCheck: [GuidanceAction(id: .reviewDirectly, text: String(localized: "Review the original evidence and the environment directly."))],
            possibleImprovements: [],
            limitations: String(localized: "Category-specific suggestions are unavailable. No condition or improvement can be inferred from an unknown category."),
            evidenceStrength: nil,
            verificationNote: String(localized: "Direct review is needed.")
        )
    }

    private func lowContrastGuidance(for finding: AccessibilityFinding) -> AccessibilityGuidance {
        let text = finding.relevantText.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let ratio = finding.estimatedContrastRatio
        let summary = ratio == nil
            ? String(localized: "Camera observations surfaced a potential text/background contrast issue. A contrast estimate is not available in this finding.")
            : String(localized: "Camera observations produced a text/background contrast estimate for this area.")

        return AccessibilityGuidance(
            ruleID: "text.potential-low-contrast", ruleVersion: 1,
            title: String(localized: "Potential low contrast"),
            observation: GuidanceObservation(summary: summary, recognizedText: text, estimatedContrastRatio: ratio),
            interpretation: String(localized: "Text in this area may be difficult to distinguish from its background."),
            whyItMatters: String(localized: "Low visual contrast can make text harder to distinguish for people with low vision or in difficult lighting conditions."),
            whatToCheck: [
                GuidanceAction(id: .viewingPosition, text: String(localized: "View the sign from the position where people normally encounter it. Check whether the text is clearly distinguishable from its background.")),
                GuidanceAction(id: .representativeLighting, text: String(localized: "Check under representative lighting, including any glare or shadows that people may encounter.")),
                GuidanceAction(id: .confirmText, text: String(localized: "Compare the recognized text with the sign directly; camera recognition can misread or miss text."))
            ].filter { text != nil || $0.id != .confirmText },
            possibleImprovements: [
                GuidanceAction(id: .increaseContrast, text: String(localized: "Consider increasing the visual difference between the text and its background.")),
                GuidanceAction(id: .simplifyBackground, text: String(localized: "If the background is visually complex, consider placing important text on a plain background.")),
                GuidanceAction(id: .recheckLighting, text: String(localized: "After any change, re-check readability from the expected viewing position under representative lighting."))
            ],
            limitations: String(localized: "Lighting, glare, shadows, motion, camera angle, and camera processing can affect the estimate. It is not a direct measurement of the sign’s actual colors or a formal standards assessment."),
            evidenceStrength: finding.evidenceStrength,
            verificationNote: finding.evidenceStrength == .limited
                ? String(localized: "Evidence is limited. Verify the observation directly before deciding whether a change would help.")
                : String(localized: "Evidence strength describes the supporting camera observations, not certainty. Verify the environment directly before deciding whether a change would help.")
        )
    }

    private func narrowPassageGuidance(for finding: AccessibilityFinding) -> AccessibilityGuidance {
        let evidence = finding.passageEvidence
        let observation: String
        if let width = evidence?.estimatedWidth {
            observation = String(
                localized: "Repeated LiDAR-supported room observations produced an estimated opening width of \(width.measurement.formatted(.measurement(width: .abbreviated, usage: .asProvided)))."
            )
        } else {
            observation = String(localized: "Repeated room observations indicated a passage that may be narrow. A usable width estimate is not available.")
        }

        return AccessibilityGuidance(
            ruleID: "passage.potential-narrow", ruleVersion: 1,
            title: String(localized: "Potential narrow passage"),
            observation: GuidanceObservation(
                summary: observation,
                recognizedText: nil,
                estimatedContrastRatio: nil,
                passageEvidence: evidence
            ),
            interpretation: String(localized: "The visible clear opening may offer limited usable space for people moving through the passage."),
            whyItMatters: String(localized: "Narrow clear openings can make passage more difficult for people using mobility devices or moving with support."),
            whatToCheck: [
                GuidanceAction(id: .measureClearOpening, text: String(localized: "Measure the clear opening directly with a suitable physical measuring tool before making an accessibility decision.")),
                GuidanceAction(id: .inspectNarrowestPoint, text: String(localized: "Check the narrowest usable portion of the opening, including handles, trim, and objects that project into the path.")),
                GuidanceAction(id: .removeTemporaryObstructions, text: String(localized: "Inspect whether temporary objects are reducing the usable passage."))
            ],
            possibleImprovements: [
                GuidanceAction(id: .improveClearance, text: String(localized: "Where appropriate, consider rearranging removable objects to preserve the clearest usable route.")),
                GuidanceAction(id: .perpendicularRecapture, text: String(localized: "If using AccessLens to check again, keep the full opening in view and position the camera as squarely to it as practical."))
            ],
            limitations: String(localized: "The estimate uses RoomPlan geometry on a supported LiDAR device. Camera angle, incomplete capture, reflective surfaces, and room reconstruction can affect it. It is not a survey measurement or a formal standards assessment."),
            evidenceStrength: finding.evidenceStrength,
            verificationNote: finding.evidenceStrength == .limited
                ? String(localized: "Evidence is limited. Verify the opening directly and do not rely on the estimate alone.")
                : String(localized: "Evidence strength describes repeated camera and room-geometry observations, not measurement certainty. Verify the clear opening directly.")
        )
    }
}
