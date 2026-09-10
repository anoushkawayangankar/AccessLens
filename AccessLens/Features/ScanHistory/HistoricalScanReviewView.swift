import Combine
import SwiftUI

@MainActor
final class HistoricalScanReviewViewModel: ObservableObject {
    enum State: Equatable { case loading, loaded(CompletedScan), missing, failed }
    @Published private(set) var state: State = .loading
    private let id: UUID
    private let repository: any CompletedScanRepository

    init(id: UUID, repository: any CompletedScanRepository) {
        self.id = id
        self.repository = repository
    }

    func load() async {
        state = .loading
        do {
            if let scan = try await repository.fetch(id: id) { state = .loaded(scan) }
            else { state = .missing }
        } catch { state = .failed }
    }
}

struct HistoricalScanReviewView: View {
    @StateObject private var model: HistoricalScanReviewViewModel
    let onBack: () -> Void

    init(id: UUID, repository: any CompletedScanRepository, onBack: @escaping () -> Void) {
        _model = StateObject(wrappedValue: HistoricalScanReviewViewModel(id: id, repository: repository))
        self.onBack = onBack
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView("Loading saved scan…")
            case let .loaded(scan):
                ScanReviewView(completedScan: scan, context: .historical, onDone: onBack)
            case .missing:
                ContentUnavailableView("Scan no longer available", systemImage: "doc", description: Text("Return to Scan History to choose another scan."))
            case .failed:
                VStack(spacing: AppSpacing.medium) {
                    Text("This saved scan couldn’t be opened. It may require a newer version of AccessLens or contain unreadable data.")
                    Button("Retry") { Task { await model.load() } }
                    Text("You can return to Scan History to delete it.").font(.footnote)
                }.padding(AppSpacing.page)
            }
        }
        .navigationTitle("Scan Review")
        .task { await model.load() }
    }
}
