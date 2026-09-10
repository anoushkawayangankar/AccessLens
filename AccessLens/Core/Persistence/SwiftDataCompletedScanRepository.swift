import Foundation
import OSLog
import SwiftData

/// One actor creates and exclusively owns the container/context. No context or
/// managed model crosses executors; all operations have no suspension point
/// between fetch, mutation and explicit save/rollback. Initialization is lazy
/// on this actor so application launch and camera UI never open a store on MainActor.
actor SwiftDataCompletedScanRepository: CompletedScanRepository {
    private let storeURL: URL?
    private let inMemory: Bool
    private var container: ModelContainer?
    private var context: ModelContext?

    init(storeURL: URL? = nil, inMemory: Bool = false) {
        self.storeURL = storeURL
        self.inMemory = inMemory
    }

    private func storage() throws -> ModelContext {
        if let context { return context }
        do {
            let schema = Schema(versionedSchema: ScanStorageSchemaV1.self)
            let configuration: ModelConfiguration
            if inMemory {
                configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            } else {
                let url: URL
                if let storeURL {
                    url = storeURL
                } else {
                    let directory = try FileManager.default.url(
                        for: .applicationSupportDirectory, in: .userDomainMask,
                        appropriateFor: nil, create: true
                    ).appendingPathComponent("AccessLens", isDirectory: true)
                    try FileManager.default.createDirectory(
                        at: directory, withIntermediateDirectories: true,
                        attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
                    )
                    url = directory.appendingPathComponent("CompletedScans.store")
                }
                configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            }
            let container = try ModelContainer(
                for: schema, migrationPlan: ScanStorageMigrationPlan.self, configurations: [configuration]
            )
            let context = ModelContext(container)
            context.autosaveEnabled = false
            self.container = container
            self.context = context
            return context
        } catch {
            // Keep the original store intact. A later operation retries opening
            // it; never substitute an ephemeral store and pretend a save worked.
            AppLog.persistence.error("Saved scan storage unavailable")
            throw ScanRepositoryError.unavailable
        }
    }

    func save(_ scan: CompletedScan) throws {
        try ScanStorageMapper.validate(scan)
        let context = try storage()
        do {
            if let existing = try record(id: scan.id, context: context) {
                guard try ScanStorageMapper.domain(existing) == scan else {
                    throw ScanRepositoryError.conflictingScan
                }
                return
            }
            context.insert(try ScanStorageMapper.stored(scan))
            try context.save()
            AppLog.persistence.info("Completed scan saved")
        } catch {
            context.rollback()
            AppLog.persistence.error("Completed scan save failed")
            throw (error as? ScanRepositoryError) ?? .saveFailed
        }
    }

    func fetch(id: UUID) throws -> CompletedScan? {
        let context = try storage()
        do {
            guard let record = try record(id: id, context: context) else { return nil }
            return try ScanStorageMapper.domain(record)
        } catch {
            AppLog.persistence.error("Saved scan could not be read")
            throw (error as? ScanRepositoryError) ?? .loadFailed
        }
    }

    func fetchAll() throws -> [SavedScanSummary] {
        let context = try storage()
        do {
            let records = try context.fetch(FetchDescriptor<ScanStorageSchemaV1.StoredScan>())
            return records.map {
                SavedScanSummary(id: $0.id, completedAt: $0.completedAt, findingCount: max(0, $0.findingCount))
            }.sorted(by: SavedScanSummary.newestFirst)
        } catch {
            AppLog.persistence.error("Scan history load failed")
            throw ScanRepositoryError.loadFailed
        }
    }

    func delete(id: UUID) throws {
        let context = try storage()
        do {
            guard let record = try record(id: id, context: context) else { return }
            context.delete(record)
            try context.save()
            AppLog.persistence.info("Saved scan deleted")
        } catch {
            context.rollback()
            AppLog.persistence.error("Saved scan deletion failed")
            throw ScanRepositoryError.deleteFailed
        }
    }

    private func record(id: UUID, context: ModelContext) throws -> ScanStorageSchemaV1.StoredScan? {
        var descriptor = FetchDescriptor<ScanStorageSchemaV1.StoredScan>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
