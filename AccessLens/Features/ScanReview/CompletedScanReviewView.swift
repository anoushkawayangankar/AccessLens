import SwiftUI

/// Starts saving only after the live session has stopped and a completed value
/// exists. Review remains available after failure, with the same retryable value.
struct CompletedScanReviewView: View {
    @StateObject private var model: CompletedScanSaveViewModel
    let onDone: () -> Void

    init(scan: CompletedScan, repository: any CompletedScanRepository, onDone: @escaping () -> Void) {
        _model = StateObject(wrappedValue: CompletedScanSaveViewModel(scan: scan, repository: repository))
        self.onDone = onDone
    }

    var body: some View {
        Group {
            if model.state == .pending || model.state == .saving {
                ProgressView("Saving completed scan…")
            } else {
                review
            }
        }
        .navigationTitle("Scan Review")
        .navigationBarBackButtonHidden(true)
        .task { await model.save() }
    }

    private var review: some View {
        ScanReviewView(completedScan: model.scan, onDone: onDone) {
            switch model.state {
            case .pending, .saving:
                ProgressView("Saving scan…")
            case .saved:
                Text("Saved to Scan History. Only completed finding details are stored; no camera images are saved.")
                    .font(.footnote)
                    .accessibilityIdentifier("scan-saved")
            case .failed:
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("Scan completed, but it couldn’t be saved. You can still review it here. Leaving this review will discard the unsaved scan.")
                        .accessibilityIdentifier("scan-save-failed")
                    Button { Task { await model.save(retry: true) } } label: {
                        Text("Retry Save").frame(minHeight: AppLayout.minimumTouchTarget)
                    }
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}
