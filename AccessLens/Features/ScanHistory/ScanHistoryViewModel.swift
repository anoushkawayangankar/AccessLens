import Combine
import Foundation

@MainActor
final class ScanHistoryViewModel: ObservableObject {
    enum State: Equatable { case loading, loaded, failed }
    @Published private(set) var state: State = .loading
    @Published private(set) var scans: [SavedScanSummary] = []
    @Published private(set) var deletingID: UUID?
    @Published private(set) var deleteFailed = false
    private let repository: any CompletedScanRepository
    private var operationID = UUID()

    init(repository: any CompletedScanRepository) { self.repository = repository }

    func load() async {
        guard deletingID == nil else { return }
        let operation = UUID()
        operationID = operation
        state = .loading
        do {
            let scans = try await repository.fetchAll()
            guard operationID == operation else { return }
            self.scans = scans.sorted(by: SavedScanSummary.newestFirst)
            state = .loaded
        } catch {
            guard operationID == operation else { return }
            state = .failed
        }
    }

    func delete(id: UUID) async {
        guard deletingID == nil else { return }
        operationID = UUID() // Reject a load begun before this mutation.
        deletingID = id
        deleteFailed = false
        defer { deletingID = nil }
        do {
            try await repository.delete(id: id)
            scans.removeAll { $0.id == id }
        } catch {
            deleteFailed = true // Keep the row; do not pretend the delete succeeded.
        }
        state = .loaded
    }
}
