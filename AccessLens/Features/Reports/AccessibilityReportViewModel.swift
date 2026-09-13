import Combine
import Foundation

@MainActor
final class AccessibilityReportViewModel: ObservableObject {
    enum PreviewState: Equatable { case loading, ready(AccessibilityReport), failed(ReportError) }
    enum ExportState: Equatable { case idle, generating, ready(URL), failed(ReportError) }
    @Published private(set) var preview: PreviewState = .loading
    @Published private(set) var exportState: ExportState = .idle
    private let scan: CompletedScan
    private let exporter: any AccessibilityReportExporting

    init(scan: CompletedScan, exporter: any AccessibilityReportExporting) {
        self.scan = scan
        self.exporter = exporter
    }

    /// SwiftUI owns the calling task; cancellation never publishes late state.
    func load() async {
        guard case .loading = preview else { return }
        do {
            let report = try await exporter.report(for: scan)
            try Task.checkCancellation()
            preview = .ready(report)
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled else { return }
            preview = .failed((error as? ReportError) ?? .invalidReportData)
        }
    }

    func retryPreview() { preview = .loading }

    func prepareExport() async {
        guard case let .ready(report) = preview, exportState != .generating else { return }
        if case .ready = exportState { return }
        exportState = .generating
        do {
            let url = try await exporter.export(report)
            try Task.checkCancellation()
            exportState = .ready(url)
        } catch is CancellationError {
            exportState = .idle
        } catch {
            guard !Task.isCancelled else { exportState = .idle; return }
            exportState = .failed((error as? ReportError) ?? .exportUnavailable)
        }
    }
}
