import Foundation

/// Only finalized domain snapshots cross this boundary. Storage types and
/// contexts never escape the repository's executor.
nonisolated protocol CompletedScanRepository: Sendable {
    func save(_ scan: CompletedScan) async throws
    func fetch(id: UUID) async throws -> CompletedScan?
    func fetchAll() async throws -> [SavedScanSummary]
    func delete(id: UUID) async throws
}

nonisolated enum ScanRepositoryError: Error, Equatable, Sendable {
    case unavailable
    case saveFailed
    case loadFailed
    case deleteFailed
    case invalidRecord
    case unsupportedRecord
    case conflictingScan
}

/// History uses lightweight metadata, so an unsupported finding can still be
/// listed and explicitly deleted without silently losing the stored record.
nonisolated struct SavedScanSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let completedAt: Date
    let findingCount: Int

    init(id: UUID, completedAt: Date, findingCount: Int) {
        self.id = id
        self.completedAt = completedAt
        self.findingCount = findingCount
    }

    init(_ scan: CompletedScan) {
        self.init(id: scan.id, completedAt: scan.completedAt, findingCount: scan.findingCount)
    }

    static func newestFirst(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.completedAt != rhs.completedAt { return lhs.completedAt > rhs.completedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    var findingCountDescription: String {
        switch findingCount {
        case 0: "No potential findings"
        case 1: "1 potential finding"
        default: "\(findingCount) potential findings"
        }
    }
}
