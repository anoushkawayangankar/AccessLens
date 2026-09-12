import OSLog
import SwiftUI

struct ScanReviewView: View {
    let viewModel: ScanReviewViewModel
    let onDone: () -> Void
    let context: ScanReviewContext
    private let saveStatus: AnyView

    init(completedScan: CompletedScan, context: ScanReviewContext = .newlyCompleted, onDone: @escaping () -> Void) {
        self.init(completedScan: completedScan, context: context, onDone: onDone) { EmptyView() }
    }

    init<Status: View>(completedScan: CompletedScan, context: ScanReviewContext = .newlyCompleted,
                      onDone: @escaping () -> Void, @ViewBuilder saveStatus: () -> Status) {
        viewModel = ScanReviewViewModel(completedScan: completedScan)
        self.onDone = onDone
        self.context = context
        self.saveStatus = AnyView(saveStatus())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                Text("Scan Review")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("scan-review-heading")

                summarySection
                saveStatus
                findingsSection
                limitationsSection

                Button {
                    onDone()
                } label: {
                    Text(context == .historical ? "Back to History" : "Done")
                        .frame(maxWidth: .infinity, minHeight: AppLayout.minimumTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint(context == .historical ? "Returns to Scan History." : "Returns to the AccessLens home screen.")
                .accessibilityIdentifier("scan-review-done")
            }
            .frame(maxWidth: AppLayout.maximumReadableWidth, alignment: .leading)
            .padding(AppSpacing.page)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Scan Review")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            AppLog.lifecycle.info("Scan review opened")
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Label(context == .historical ? "Saved scan" : "Completed scan", systemImage: "checkmark.circle")
                .font(.headline)
            Text(viewModel.completedScan.completedAt, format: .dateTime.year().month().day().hour().minute())
                .font(.subheadline)
            Text(viewModel.summary)
                .font(.body.weight(.semibold))
                .accessibilityIdentifier("scan-review-summary")
            Text(viewModel.reviewIntroduction)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var findingsSection: some View {
        if viewModel.isZeroFindingScan {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text("No potential issues were identified during this scan.")
                    .font(.headline)
                    .accessibilityIdentifier("scan-review-zero-findings")
                Text("This does not guarantee that the environment is fully accessible.")
                    .font(.body)
            }
            .padding(AppSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text("Potential findings")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                ForEach(viewModel.completedScan.findings) { finding in
                    findingCard(finding)
                }
            }
        }
    }

    private func findingCard(_ finding: AccessibilityFinding) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Label(finding.title, systemImage: "exclamationmark.magnifyingglass")
                .font(.headline)
            if let text = finding.relevantText {
                Text(text)
                    .font(.body.weight(.semibold))
            }
            if let width = finding.passageEvidence?.estimatedWidth {
                Text("Estimated opening width: \(width.measurement.formatted(.measurement(width: .abbreviated, usage: .asProvided)))")
                    .font(.body.weight(.semibold))
                    .accessibilityIdentifier("passage-estimated-width")
            }
            Text(finding.explanation)
                .font(.body)
            Text(finding.evidenceStrength.guidanceLabel)
                .font(.subheadline)
            Text("Potential issue estimated from camera observations.")
                .font(.footnote)
            NavigationLink(value: AppRoute.findingDetail(finding)) {
                Text("View Guidance")
                    .frame(minHeight: AppLayout.minimumTouchTarget)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(Text("View Guidance for \(finding.relevantText ?? finding.title)"))
            .accessibilityIdentifier("view-guidance-\(finding.id.uuidString)")
        }
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scan-review-finding-\(finding.id.uuidString)")
    }

    private var limitationsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Label("Limitations", systemImage: "info.circle")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(viewModel.completedScan.limitationsSummary)
                .font(.body)
        }
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
struct ScanReviewView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ScanReviewView(
                completedScan: CompletedScan(
                    sessionID: UUID(),
                    startedAt: .now.addingTimeInterval(-30),
                    completedAt: .now,
                    findings: []
                ),
                onDone: {}
            )
        }
    }
}
#endif
