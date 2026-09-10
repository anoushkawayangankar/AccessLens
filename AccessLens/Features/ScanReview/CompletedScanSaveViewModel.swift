import Combine
import Foundation

/// Owns one completion's save attempt and retains its immutable review through
/// failure. Reappearance cannot duplicate a successful save; Retry is explicit.
@MainActor
final class CompletedScanSaveViewModel: ObservableObject {
    enum State: Equatable { case pending, saving, saved, failed }
    let scan: CompletedScan
    @Published private(set) var state: State = .pending
    private let repository: any CompletedScanRepository

    init(scan: CompletedScan, repository: any CompletedScanRepository) {
        self.scan = scan
        self.repository = repository
    }

    func save(retry: Bool = false) async {
        guard state == .pending || (retry && state == .failed) else { return }
        state = .saving
        do {
            try await repository.save(scan)
            state = .saved
        } catch {
            state = .failed
        }
    }
}
