import Foundation
import SwiftData
import XCTest
@testable import AccessLens

final class CompletedScanRepositoryTests: XCTestCase {
    func testDomainRoundTripPreservesAllEvidenceExactly() async throws {
        let repository = SwiftDataCompletedScanRepository(inMemory: true)
        let scan = ScanPersistenceFixtures.scan()
        try await repository.save(scan)
        let restored = try await repository.fetch(id: scan.id)
        XCTAssertEqual(restored, scan)
    }

    func testZeroAndMultipleFindingsKeepTheirOrderAndIdentity() async throws {
        let repository = SwiftDataCompletedScanRepository(inMemory: true)
        for count in [0, 3] {
            let scan = ScanPersistenceFixtures.scan(findingCount: count)
            try await repository.save(scan)
            let restored = try await repository.fetch(id: scan.id)
            XCTAssertEqual(restored, scan)
        }
    }

    func testDuplicateSaveIsIdempotentAndConflictingSnapshotCannotOverwrite() async throws {
        let repository = SwiftDataCompletedScanRepository(inMemory: true)
        let scan = ScanPersistenceFixtures.scan()
        try await repository.save(scan)
        try await repository.save(scan)
        let conflicting = ScanPersistenceFixtures.scan(id: scan.id, findingCount: 0)
        do {
            try await repository.save(conflicting)
            XCTFail("A different immutable snapshot must not replace the original")
        } catch { XCTAssertEqual(error as? ScanRepositoryError, .conflictingScan) }
        let rows = try await repository.fetchAll()
        let original = try await repository.fetch(id: scan.id)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(original, scan)
    }

    func testConcurrentDuplicateSavesHaveOneLogicalRecord() async throws {
        let repository = SwiftDataCompletedScanRepository(inMemory: true)
        let scan = ScanPersistenceFixtures.scan()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<10 { group.addTask { try await repository.save(scan) } }
            try await group.waitForAll()
        }
        let rows = try await repository.fetchAll()
        XCTAssertEqual(rows.count, 1)
    }

    func testNewestFirstUsesStableIDToBreakDateTies() async throws {
        let repository = SwiftDataCompletedScanRepository(inMemory: true)
        let lowID = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let highID = try XCTUnwrap(UUID(uuidString: "99999999-9999-9999-9999-999999999999"))
        let old = ScanPersistenceFixtures.scan(completedAt: 100)
        let first = ScanPersistenceFixtures.scan(id: lowID)
        let second = ScanPersistenceFixtures.scan(id: highID)
        for scan in [old, second, first] { try await repository.save(scan) }
        let rows = try await repository.fetchAll()
        XCTAssertEqual(rows.map(\.id), [first.id, second.id, old.id])
        let unknown = try await repository.fetch(id: UUID())
        XCTAssertNil(unknown)
    }

    func testDeleteRemovesOnlySelectedScanAndIsIdempotent() async throws {
        let repository = SwiftDataCompletedScanRepository(inMemory: true)
        let scans = (0..<3).map { _ in ScanPersistenceFixtures.scan(findingCount: 2) }
        for scan in scans { try await repository.save(scan) }
        try await repository.delete(id: scans[1].id)
        try await repository.delete(id: scans[1].id)
        let rows = try await repository.fetchAll()
        XCTAssertEqual(Set(rows.map(\.id)), Set([scans[0].id, scans[2].id]))
        let deleted = try await repository.fetch(id: scans[1].id)
        XCTAssertNil(deleted)
        let surviving = try await repository.fetch(id: scans[0].id)
        XCTAssertEqual(surviving, scans[0])
    }

    func testDiskStoreSurvivesRepositoryRecreationAndCascadesDeletion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AccessLensPersistenceTest-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("scans.store")
        let scan = ScanPersistenceFixtures.scan(findingCount: 2)
        try await saveAndRelease(scan, url: url)
        try await readDeleteAndRelease(scan, url: url)

        // Independent container confirms both parent and dependent rows are gone.
        let schema = Schema(versionedSchema: ScanStorageSchemaV1.self)
        let container = try ModelContainer(for: schema, migrationPlan: ScanStorageMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScanStorageSchemaV1.StoredScan>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScanStorageSchemaV1.StoredFinding>()), 0)
    }

    private func saveAndRelease(_ scan: CompletedScan, url: URL) async throws {
        let repository = SwiftDataCompletedScanRepository(storeURL: url)
        try await repository.save(scan)
    }

    private func readDeleteAndRelease(_ scan: CompletedScan, url: URL) async throws {
        let repository = SwiftDataCompletedScanRepository(storeURL: url)
        let restored = try await repository.fetch(id: scan.id)
        XCTAssertEqual(restored, scan)
        try await repository.delete(id: scan.id)
    }

    func testUnknownEnumsAndVersionAreRejectedWithoutGuessingMeaning() throws {
        let scan = ScanPersistenceFixtures.scan()
        for field in ["category", "strength", "version", "lifecycle"] {
            let stored = try ScanStorageMapper.stored(scan)
            let finding = try XCTUnwrap(stored.findings.first)
            switch field {
            case "category": finding.category = "futureCategory"
            case "strength": finding.evidenceStrength = "futureStrength"
            case "version": stored.recordVersion = 9
            default: finding.lifecycle = "futureLifecycle"
            }
            XCTAssertThrowsError(try ScanStorageMapper.domain(stored)) {
                XCTAssertEqual($0 as? ScanRepositoryError, .unsupportedRecord)
            }
        }
    }

    func testInvalidRecordDoesNotEnterStoreOrDamageExistingScan() async throws {
        let repository = SwiftDataCompletedScanRepository(inMemory: true)
        let original = ScanPersistenceFixtures.scan()
        try await repository.save(original)
        let invalid = CompletedScan(sessionID: UUID(), startedAt: .distantFuture,
                                    completedAt: .distantPast, findings: [])
        do { try await repository.save(invalid); XCTFail("Invalid dates must fail") }
        catch { XCTAssertEqual(error as? ScanRepositoryError, .invalidRecord) }
        let rows = try await repository.fetchAll()
        XCTAssertEqual(rows.map(\.id), [original.id])
    }

    func testMalformedEvidenceIsRejected() throws {
        let record = try ScanStorageMapper.stored(ScanPersistenceFixtures.scan())
        let finding = try XCTUnwrap(record.findings.first)
        finding.estimatedContrast = .nan
        XCTAssertThrowsError(try ScanStorageMapper.domain(record))
        finding.estimatedContrast = 2
        finding.regionX = nil
        XCTAssertThrowsError(try ScanStorageMapper.domain(record))
    }

    func testUnavailableStoreDoesNotFallBackToSuccessfulMemorySave() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AccessLensUnavailableTest-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocker = directory.appendingPathComponent("file-not-directory")
        try Data("blocked".utf8).write(to: blocker)
        let url = blocker.appendingPathComponent("scans.store")
        let repository = SwiftDataCompletedScanRepository(storeURL: url)
        do { try await repository.save(ScanPersistenceFixtures.scan()); XCTFail("Store open must fail") }
        catch { XCTAssertEqual(error as? ScanRepositoryError, .unavailable) }
    }

    func testUnsupportedStoredRecordRemainsListedAndDeletable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AccessLensUnknownTest-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("scans.store")
        let scan = ScanPersistenceFixtures.scan()
        try writeUnsupportedRecord(scan, url: url)
        let repository = SwiftDataCompletedScanRepository(storeURL: url)
        let rows = try await repository.fetchAll()
        XCTAssertEqual(rows.map(\.id), [scan.id])
        do { _ = try await repository.fetch(id: scan.id); XCTFail("Unknown meaning must not render as current evidence") }
        catch { XCTAssertEqual(error as? ScanRepositoryError, .unsupportedRecord) }
        try await repository.delete(id: scan.id)
        let remaining = try await repository.fetchAll()
        XCTAssertTrue(remaining.isEmpty)
    }

    private func writeUnsupportedRecord(_ scan: CompletedScan, url: URL) throws {
        let schema = Schema(versionedSchema: ScanStorageSchemaV1.self)
        let container = try ModelContainer(for: schema, migrationPlan: ScanStorageMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let record = try ScanStorageMapper.stored(scan)
        let finding = try XCTUnwrap(record.findings.first)
        finding.category = "futureCategory"
        context.insert(record)
        try context.save()
    }
}
