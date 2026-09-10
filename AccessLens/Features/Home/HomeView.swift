import SwiftUI

struct HomeView: View {
    let onStartScan: () -> Void
    let onHistory: () -> Void

    init(onStartScan: @escaping () -> Void = {}, onHistory: @escaping () -> Void = {}) {
        self.onStartScan = onStartScan
        self.onHistory = onHistory
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                Image(systemName: "accessibility")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("AccessLens")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("accesslens-root-title")

                    Text("AccessLens helps identify potential accessibility barriers using on-device analysis.")
                        .font(.body)
                        .accessibilityIdentifier("accesslens-product-statement")
                }

                FoundationStatusView()

                Button("Start Scan") {
                    onStartScan()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: AppLayout.minimumTouchTarget)
                .accessibilityIdentifier("start-scan")

                Button(action: onHistory) {
                    Text("Scan History")
                        .frame(maxWidth: .infinity, minHeight: AppLayout.minimumTouchTarget)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("scan-history")

                Text("Completed scans are saved on this device, including text needed to explain findings. No camera images are saved. You can delete scans from Scan History.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: AppLayout.maximumReadableWidth, alignment: .leading)
            .padding(AppSpacing.page)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("AccessLens")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FoundationStatusView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Label("On-device text analysis", systemImage: "text.viewfinder")
                .font(.headline)

            Text("Scan visible text and environmental signage. AccessLens presents observations and does not certify accessibility or legal compliance.")
                .font(.body)
        }
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            HomeView()
        }
    }
}
