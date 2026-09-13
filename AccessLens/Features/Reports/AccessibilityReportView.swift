import SwiftUI

/// Readable preview does not generate a PDF. Explicit preparation and native
/// ShareLink are separate actions, both reachable without gestures or color.
struct AccessibilityReportView: View {
    @StateObject private var model: AccessibilityReportViewModel
    @State private var previewRequest = 0
    @State private var exportRequest = 0
    let onBack: () -> Void

    init(scan: CompletedScan, exporter: any AccessibilityReportExporting, onBack: @escaping () -> Void) {
        _model = StateObject(wrappedValue: AccessibilityReportViewModel(scan: scan, exporter: exporter))
        self.onBack = onBack
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                switch model.preview {
                case .loading:
                    ProgressView("Preparing report…")
                case let .failed(error):
                    Text(error.message).accessibilityIdentifier("report-preview-error")
                    Button("Retry Report") {
                        model.retryPreview()
                        previewRequest += 1
                    }.frame(minHeight: AppLayout.minimumTouchTarget)
                case let .ready(report):
                    preview(report)
                }
            }
            .font(.body)
            .foregroundStyle(.primary)
            .frame(maxWidth: AppLayout.maximumReadableWidth, alignment: .leading)
            .padding(AppSpacing.page)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("Accessibility Report")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .top) {
            HStack {
                Button(action: onBack) {
                    Text("Back").font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minWidth: AppLayout.minimumTouchTarget, minHeight: AppLayout.minimumTouchTarget)
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.primary)
                .accessibilityHint("Returns to this scan’s review.")
                .accessibilityIdentifier("report-back")
                Spacer()
            }
            .padding(.horizontal, AppSpacing.page)
            .background(Color(uiColor: .systemBackground))
        }
        .task(id: previewRequest) { await model.load() }
        .task(id: exportRequest) {
            if exportRequest > 0 { await model.prepareExport() }
        }
    }

    private func preview(_ report: AccessibilityReport) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            Text(report.title).font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("report-title")
            Text(report.scanDateText)
            Text(report.introduction)
            heading(ReportCopy.summary)
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                ForEach(Array(report.summary.components(separatedBy: "\n").enumerated()), id: \.offset) { index, line in
                    Text(line).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(index == 0 ? "report-summary" : "report-summary-evidence-\(index)")
                }
            }
            if let quality = report.qualitySummary { Text(quality).accessibilityIdentifier("report-quality") }
            exportControls
            // Normal scans contain at most six findings. Eager layout keeps
            // their accessibility headings stable during Dynamic Type changes.
            // Larger historical reports retain bounded lazy card layout.
            if report.findings.count <= 6 {
                VStack(alignment: .leading, spacing: AppSpacing.large) { findings(report) }
            } else {
                LazyVStack(alignment: .leading, spacing: AppSpacing.large) { findings(report) }
            }
            heading(ReportCopy.limitations).accessibilityIdentifier("report-limitations")
            ForEach(Array(report.limitations.enumerated()), id: \.offset) { _, limitation in Text(limitation) }
        }
        .textSelection(.enabled)
    }

    private func findings(_ report: AccessibilityReport) -> some View {
        ForEach(Array(report.findings.enumerated()), id: \.offset) { index, finding in
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                Text("\(index + 1). \(finding.title)").font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("report-finding-\(index)")
                ForEach(Array(finding.sections.enumerated()), id: \.offset) { _, section in
                    heading(section.title)
                    ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private var exportControls: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(ReportCopy.privacy).font(.footnote)
            switch model.exportState {
            case .idle:
                Button { exportRequest += 1 } label: {
                    Label("Prepare PDF", systemImage: "doc")
                        .frame(minHeight: AppLayout.minimumTouchTarget)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Prepares a temporary PDF on this device. Nothing is shared yet.")
                .accessibilityIdentifier("report-export")
            case .generating:
                ProgressView("Preparing PDF…").accessibilityIdentifier("report-export-progress")
            case let .ready(url):
                ShareLink(item: url) {
                    Label("Share Report", systemImage: "square.and.arrow.up")
                        .frame(minHeight: AppLayout.minimumTouchTarget)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Opens sharing options for the PDF report, including Save to Files.")
                .accessibilityIdentifier("report-share")
            case let .failed(error):
                Text(error.message).accessibilityIdentifier("report-export-error")
                Button { exportRequest += 1 } label: {
                    Text("Retry Export").frame(minHeight: AppLayout.minimumTouchTarget)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("report-export-retry")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(.headline).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
    }
}
