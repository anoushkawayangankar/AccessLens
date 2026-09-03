import SwiftUI

struct HomeView: View {
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
            Label("Foundation in progress", systemImage: "hammer")
                .font(.headline)

            Text("Scanning is not available yet. AccessLens does not certify accessibility or legal compliance.")
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
