import XCTest
@testable import AccessLens

@MainActor
final class ScanHistoryTests: XCTestCase {
    func testHistoryLoadsNewestFirstAndRefreshesAfterNewSave() async throws {
        let old = ScanPersistenceFixtures.scan(completedAt: 100)
        let newest = ScanPersistenceFixtures.scan(completedAt: 300)
        let repository = InMemoryCompletedScanRepository(scans: [old])
        let model = ScanHistoryViewModel(repository: repository)
        XCTAssertEqual(model.state, .loading)
        await model.load()
        XCTAssertEqual(model.scans.map(\.id), [old.id])
        try await repository.save(newest)
        await model.load()
        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.scans.map(\.id), [newest.id, old.id])
    }

    func testEmptyAndFailedHistoryCanRetry() async {
        let repository = InMemoryCompletedScanRepository()
        let model = ScanHistoryViewModel(repository: repository)
        await repository.setError(.loadFailed, for: .fetch)
        await model.load()
        XCTAssertEqual(model.state, .failed)
        await repository.setError(nil, for: .fetch)
        await model.load()
        XCTAssertEqual(model.state, .loaded)
        XCTAssertTrue(model.scans.isEmpty)
    }

    func testDeleteFailureKeepsRowsThenRetryDeletesOnlySelectedScan() async {
        let scans = [ScanPersistenceFixtures.scan(), ScanPersistenceFixtures.scan()]
        let repository = InMemoryCompletedScanRepository(scans: scans)
        let model = ScanHistoryViewModel(repository: repository)
        await model.load()
        await repository.setError(.deleteFailed, for: .delete)
        await model.delete(id: scans[0].id)
        XCTAssertTrue(model.deleteFailed)
        XCTAssertEqual(model.scans.count, 2)
        await repository.setError(nil, for: .delete)
        await model.delete(id: scans[0].id)
        XCTAssertFalse(model.deleteFailed)
        XCTAssertEqual(model.scans.map(\.id), [scans[1].id])
        XCTAssertNil(model.deletingID)
    }

    func testCompletionSaveFailurePreservesReviewAndRetrySavesOnce() async throws {
        let scan = ScanPersistenceFixtures.scan()
        let repository = InMemoryCompletedScanRepository()
        let model = CompletedScanSaveViewModel(scan: scan, repository: repository)
        await repository.setError(.saveFailed, for: .save)
        await model.save()
        XCTAssertEqual(model.state, .failed)
        XCTAssertEqual(model.scan, scan)
        await model.save() // Reappearance must not loop retries.
        let failedCalls = await repository.saveCalls
        XCTAssertEqual(failedCalls, 1)
        await repository.setError(nil, for: .save)
        await model.save(retry: true)
        await model.save(retry: true)
        XCTAssertEqual(model.state, .saved)
        let calls = await repository.saveCalls
        let restored = try await repository.fetch(id: scan.id)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(restored, scan)
    }

    func testHistoricalReviewLoadsTheSameSnapshotWithoutSavingAgain() async {
        let scan = ScanPersistenceFixtures.scan()
        let repository = InMemoryCompletedScanRepository(scans: [scan])
        let model = HistoricalScanReviewViewModel(id: scan.id, repository: repository)
        await model.load()
        XCTAssertEqual(model.state, .loaded(scan))
        let calls = await repository.saveCalls
        XCTAssertEqual(calls, 0)
    }

    func testMissingAndUnreadableHistoricalReviewAreRecoverable() async {
        let repository = InMemoryCompletedScanRepository()
        let model = HistoricalScanReviewViewModel(id: UUID(), repository: repository)
        await model.load()
        XCTAssertEqual(model.state, .missing)
        await repository.setError(.unsupportedRecord, for: .fetch)
        await model.load()
        XCTAssertEqual(model.state, .failed)
        await repository.setError(nil, for: .fetch)
        await model.load()
        XCTAssertEqual(model.state, .missing)
    }

    func testReviewNavigationReplacesLiveRouteAndHistoryBackKeepsHistory() {
        let navigator = AppNavigator()
        let scan = ScanPersistenceFixtures.scan()
        navigator.navigate(to: .scan)
        navigator.showCompletedScan(scan)
        XCTAssertEqual(navigator.path, [.scanReview(scan)])
        navigator.returnToRoot()
        navigator.navigate(to: .savedScans)
        navigator.navigate(to: .scanDetail(id: scan.id))
        navigator.goBack()
        XCTAssertEqual(navigator.path, [.savedScans])
    }
}
