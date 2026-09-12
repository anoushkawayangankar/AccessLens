import SwiftUI

/// Both live-completion and historical review use this immutable presentation.
/// The route carries finalized evidence only; opening it performs no I/O.
struct FindingDetailView: View {
    let guidance: AccessibilityGuidance
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                Text(guidance.title)
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("guidance-title")

                section("What AccessLens observed", id: "guidance-observation") {
                    Text(guidance.observation.summary)
                    if let text = guidance.observation.recognizedText {
                        Text("Recognized text: \(text)")
                            .accessibilityIdentifier("guidance-recognized-text")
                    }
                }
                section("Why it may matter", id: "guidance-why") {
                    Text(guidance.interpretation)
                    Text(guidance.whyItMatters)
                }
                section("What to check", id: "guidance-checks") {
                    actions(guidance.whatToCheck)
                }
                if !guidance.possibleImprovements.isEmpty {
                    section("Possible improvements", id: "guidance-improvements") {
                        actions(guidance.possibleImprovements)
                    }
                }
                section("Evidence", id: "guidance-evidence") {
                    if let strength = guidance.evidenceStrength {
                        Text(strength.guidanceLabel)
                    }
                    if let ratio = guidance.observation.estimatedContrastRatio {
                        Text("Estimated text/background contrast: \(ratio.value, format: .number.precision(.fractionLength(1))):1")
                    }
                    Text("Estimated from camera observations.")
                    Text(guidance.verificationNote)
                }
                section("Limitations", id: "guidance-limitations") {
                    Text(guidance.limitations)
                    Text("Suggestions come from AccessLens’s current guidance rules for this finding type. They do not describe additional conditions detected in the environment.")
                        .accessibilityIdentifier("guidance-provenance")
                }
            }
            .font(.body)
            .foregroundStyle(.primary)
            .frame(maxWidth: AppLayout.maximumReadableWidth, alignment: .leading)
            .padding(AppSpacing.page)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("Finding Guidance")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onBack) {
                    Text("Back")
                        .frame(minWidth: AppLayout.minimumTouchTarget, minHeight: AppLayout.minimumTouchTarget)
                }
                .accessibilityHint("Returns to this scan’s review.")
                .accessibilityIdentifier("guidance-back")
            }
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, id: String,
                                       @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(id)
            content()
        }
    }

    private func actions(_ values: [GuidanceAction]) -> some View {
        ForEach(Array(values.enumerated()), id: \.element.id) { index, action in
            // Whole localized sentence includes position for nonvisual list context.
            Text("\(index + 1). \(action.text)")
                .accessibilityLabel(Text("Item \(index + 1) of \(values.count). \(action.text)"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension FindingEvidenceStrength {
    var guidanceLabel: String {
        switch self {
        case .limited: String(localized: "Evidence strength: Limited")
        case .moderate: String(localized: "Evidence strength: Moderate")
        case .strong: String(localized: "Evidence strength: Strong")
        }
    }
}
