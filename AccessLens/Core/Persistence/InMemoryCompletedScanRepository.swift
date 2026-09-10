#if DEBUG
import Foundation

/// Deterministic previews/tests only. Never selected by Release composition.
actor InMemoryCompletedScanRepository: CompletedScanRepository {
    private var scans: [UUID: CompletedScan]
    private var errors: [Operation: ScanRepositoryError] = [:]
    private(set) var saveCalls = 0
    enum Operation: Hashable, Sendable { case save, fetch, delete }

    init(scans: [CompletedScan] = []) {
        self.scans = scans.reduce(into: [:]) { $0[$1.id] = $1 }
    }

    func setError(_ error: ScanRepositoryError?, for operation: Operation) {
        errors[operation] = error
    }

    func save(_ scan: CompletedScan) throws {
        saveCalls += 1
        if let error = errors[.save] { throw error }
        try ScanStorageMapper.validate(scan)
        if let existing = scans[scan.id], existing != scan { throw ScanRepositoryError.conflictingScan }
        scans[scan.id] = scan
    }

    func fetch(id: UUID) throws -> CompletedScan? {
        if let error = errors[.fetch] { throw error }
        return scans[id]
    }

    func fetchAll() throws -> [SavedScanSummary] {
        if let error = errors[.fetch] { throw error }
        return scans.values.map(SavedScanSummary.init).sorted(by: SavedScanSummary.newestFirst)
    }

    func delete(id: UUID) throws {
        if let error = errors[.delete] { throw error }
        scans[id] = nil
    }
}
#endif
