import SwiftUI

struct ScanHistoryView: View {
    @StateObject private var model: ScanHistoryViewModel
    @State private var pendingDeletion: SavedScanSummary?
    let onOpen: (UUID) -> Void
    let onStartScan: () -> Void

    init(repository: any CompletedScanRepository, onOpen: @escaping (UUID) -> Void, onStartScan: @escaping () -> Void) {
        _model = StateObject(wrappedValue: ScanHistoryViewModel(repository: repository))
        self.onOpen = onOpen
        self.onStartScan = onStartScan
    }

    var body: some View {
        List {
            switch model.state {
            case .loading:
                ProgressView("Loading saved scans…")
            case .failed:
                Text("Saved scans couldn’t be loaded.")
                Button("Retry") { Task { await model.load() } }
            case .loaded:
                if model.scans.isEmpty {
                    Text("No saved scans yet.")
                        .font(.headline)
                        .accessibilityIdentifier("history-empty")
                    Text("Complete a scan to see it here.")
                    Button("Start Scan", action: onStartScan)
                        .frame(minHeight: AppLayout.minimumTouchTarget)
                } else {
                    ForEach(model.scans) { scan in
                        VStack(alignment: .leading, spacing: AppSpacing.small) {
                            Button { onOpen(scan.id) } label: {
                                VStack(alignment: .leading, spacing: AppSpacing.small) {
                                    Text(scan.completedAt, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                                        .font(.headline)
                                    Text(scan.findingCountDescription).font(.body)
                                }
                                .frame(maxWidth: .infinity, minHeight: AppLayout.minimumTouchTarget, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityHint("Opens this saved scan for review.")
                            .accessibilityIdentifier("history-open-\(scan.id.uuidString)")

                            Button(role: .destructive) { pendingDeletion = scan } label: {
                                Text("Delete Scan")
                                    .frame(minHeight: AppLayout.minimumTouchTarget)
                                    .contentShape(Rectangle())
                            }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Delete Scan from \(scan.completedAt.formatted(date: .abbreviated, time: .shortened))")
                                .accessibilityIdentifier("history-delete-\(scan.id.uuidString)")
                                .disabled(model.deletingID != nil)
                        }
                    }
                }
                if model.deleteFailed {
                    Text("This scan couldn’t be deleted. Try Delete Scan again.")
                        .accessibilityIdentifier("history-delete-failed")
                }
                Text("Saved scans contain completed finding details, which may include recognized sign text. Camera images and raw text streams are not saved.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Scan History")
        .task { await model.load() }
        .alert("Delete Scan?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
            Button("Delete", role: .destructive) {
                guard let id = pendingDeletion?.id else { return }
                pendingDeletion = nil
                Task { await model.delete(id: id) }
            }
        } message: {
            Text("This permanently removes this saved scan from AccessLens.")
        }
    }
}
