import XCTest
@testable import AccessLens

final class AnalysisSchedulerTests: XCTestCase {
    func testBurstKeepsOneInFlightAndOneNewestPendingFrame() async {
        let analyzer = GateAnalyzer()
        let recorder = ResultRecorder()
        let scheduler = makeScheduler(analyzers: [analyzer], recorder: recorder)
        let sessionID = AnalysisSessionID()
        scheduler.beginSession(sessionID)

        scheduler.submit(sessionID: sessionID, presentationTimeSeconds: 0, orientation: .up, dimensions: nil)
        await analyzer.waitUntilInvoked(sequence: 1)

        scheduler.submit(sessionID: sessionID, presentationTimeSeconds: 1, orientation: .up, dimensions: nil)
        scheduler.submit(sessionID: sessionID, presentationTimeSeconds: 2, orientation: .up, dimensions: nil)
        scheduler.submit(sessionID: sessionID, presentationTimeSeconds: 3, orientation: .up, dimensions: nil)

        let snapshot = scheduler.snapshot()
        XCTAssertEqual(snapshot.inFlightCount, 1)
        XCTAssertEqual(snapshot.pendingCount, 1)
        XCTAssertEqual(snapshot.inFlightSequence?.rawValue, 1)
        XCTAssertEqual(snapshot.pendingSequence?.rawValue, 4)
        XCTAssertEqual(snapshot.pendingReplacementCount, 2)

        await analyzer.complete(sequence: 1)
        await analyzer.waitUntilInvoked(sequence: 4)
        await analyzer.complete(sequence: 4)
        await recorder.waitForCount(2)

        let sequences = await recorder.results.map(\.frameSequence.rawValue)
        XCTAssertEqual(sequences, [1, 4])
    }

    func testLatestPendingFrameReplacesOlderPendingFrame() async {
        let analyzer = GateAnalyzer()
        let recorder = ResultRecorder()
        let scheduler = makeScheduler(analyzers: [analyzer], recorder: recorder)
        let sessionID = AnalysisSessionID()
        scheduler.beginSession(sessionID)

        scheduler.submit(sessionID: sessionID, presentationTimeSeconds: 0, orientation: .up, dimensions: nil)
        await analyzer.waitUntilInvoked(sequence: 1)
        scheduler.submit(sessionID: sessionID, presentationTimeSeconds: 1, orientation: .up, dimensions: nil)
        scheduler.submit(sessionID: sessionID, presentationTimeSeconds: 2, orientation: .up, dimensions: nil)

        await analyzer.complete(sequence: 1)
        await analyzer.waitUntilInvoked(sequence: 3)
        await analyzer.complete(sequence: 3)
        await recorder.waitForCount(2)

        let invokedSequences = await analyzer.invokedSequences
        XCTAssertEqual(invokedSequences, [1, 3])
    }

    func testStaleResultFromReplacedSessionIsDiscarded() async {
        let analyzer = GateAnalyzer(honorsCancellation: false)
        let recorder = ResultRecorder()
        let scheduler = makeScheduler(analyzers: [analyzer], recorder: recorder)
        let firstSession = AnalysisSessionID()
        let secondSession = AnalysisSessionID()
        scheduler.beginSession(firstSession)
        scheduler.submit(sessionID: firstSession, presentationTimeSeconds: 0, orientation: .up, dimensions: nil)
        await analyzer.waitUntilInvoked(sequence: 1)

        scheduler.beginSession(secondSession)
        await analyzer.complete(sequence: 1)
        await analyzer.waitUntilReturned(sequence: 1)
        await eventually { scheduler.snapshot().staleResultDiscardCount == 1 }

        let staleResults = await recorder.results
        XCTAssertEqual(staleResults.count, 0)
        XCTAssertEqual(scheduler.snapshot().activeSessionID, secondSession)
    }

    func testEndingSessionCancelsWorkClearsPendingAndPublishesNothing() async {
        let analyzer = GateAnalyzer()
        let recorder = ResultRecorder()
        let scheduler = makeScheduler(analyzers: [analyzer], recorder: recorder)
        let sessionID = AnalysisSessionID()
        scheduler.beginSession(sessionID)
        scheduler.submit(sessionID: sessionID, presentationTimeSeconds: 0, orientation: .up, dimensions: nil)
        await analyzer.waitUntilInvoked(sequence: 1)
        scheduler.submit(sessionID: sessionID, presentationTimeSeconds: 1, orientation: .up, dimensions: nil)

        scheduler.endSession(sessionID)
        await analyzer.waitUntilCancelled(sequence: 1)
        await eventually { scheduler.snapshot().activeSessionID == nil }

        let snapshot = scheduler.snapshot()
        XCTAssertEqual(snapshot.inFlightCount, 0)
        XCTAssertEqual(snapshot.pendingCount, 0)
        let cancelledResults = await recorder.results
        XCTAssertEqual(cancelledResults.count, 0)
    }

    func testCadenceDropsFramesThatArriveTooSoon() async {
        let analyzer = ImmediateAnalyzer()
        let recorder = ResultRecorder()
        let scheduler = makeScheduler(analyzers: [analyzer], recorder: recorder)
        let sessionID = AnalysisSessionID()
        scheduler.beginSession(sessionID)

        scheduler.submit(sessionID: sessionID, presentationTimeSeconds: 0, orientation: .up, dimensions: nil)
        await recorder.waitForCount(1)
        scheduler.submit(sessionID: sessionID, presentationTimeSeconds: 0.2, orientation: .up, dimensions: nil)
        scheduler.submit(sessionID: sessionID, presentationTimeSeconds: 0.8, orientation: .up, dimensions: nil)
        await recorder.waitForCount(2)

        let cadenceInvocations = await analyzer.invokedSequences
        XCTAssertEqual(cadenceInvocations, [1, 3])
        XCTAssertEqual(scheduler.snapshot().cadenceDropCount, 1)
    }

    func testAnalyzerFailureIsReturnedWithoutBlockingLaterFrames() async {
        let successfulAnalyzer = ImmediateAnalyzer()
        let failingAnalyzer = FailingAnalyzer()
        let recorder = ResultRecorder()
        let scheduler = makeScheduler(
            analyzers: [successfulAnalyzer, failingAnalyzer],
            recorder: recorder
        )
        let sessionID = AnalysisSessionID()
        scheduler.beginSession(sessionID)

        scheduler.submit(sessionID: sessionID, presentationTimeSeconds: 0, orientation: .up, dimensions: nil)
        await recorder.waitForCount(1)
        scheduler.submit(sessionID: sessionID, presentationTimeSeconds: 1, orientation: .up, dimensions: nil)
        await recorder.waitForCount(2)

        let results = await recorder.results
        XCTAssertEqual(results[0].failures, [
            AnalysisFailure(analyzerID: failingAnalyzer.identifier, error: .analyzerFailed(failingAnalyzer.identifier))
        ])
        let successfulInvocations = await successfulAnalyzer.invokedSequences
        XCTAssertEqual(successfulInvocations, [1, 2])
    }

    func testFrameSequencesAreMonotonicAcrossSessions() async {
        let analyzer = ImmediateAnalyzer()
        let recorder = ResultRecorder()
        let scheduler = makeScheduler(analyzers: [analyzer], recorder: recorder)
        let firstSession = AnalysisSessionID()
        scheduler.beginSession(firstSession)
        scheduler.submit(sessionID: firstSession, presentationTimeSeconds: 0, orientation: .up, dimensions: nil)
        await recorder.waitForCount(1)

        let secondSession = AnalysisSessionID()
        scheduler.beginSession(secondSession)
        scheduler.submit(sessionID: secondSession, presentationTimeSeconds: 0, orientation: .up, dimensions: nil)
        await recorder.waitForCount(2)

        let sessionResults = await recorder.results
        XCTAssertEqual(sessionResults.map(\.frameSequence.rawValue), [1, 2])
    }

    private func makeScheduler(
        analyzers: [any AccessibilityAnalyzer],
        recorder: ResultRecorder
    ) -> AnalysisScheduler {
        AnalysisScheduler(
            analyzers: analyzers,
            performancePolicy: AnalysisPerformancePolicy(
                normalMinimumInterval: 0.75,
                reducedMinimumInterval: 1.5,
                lowPowerMinimumInterval: 1.5
            ),
            resultHandler: { result in
                Task { await recorder.append(result) }
            }
        )
    }

    private func eventually(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () -> Bool
    ) async {
        for _ in 0..<100 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not satisfied.", file: file, line: line)
    }
}

final class AnalysisPerformancePolicyTests: XCTestCase {
    func testThermalStatesSelectExpectedCadence() {
        let policy = AnalysisPerformancePolicy(
            normalMinimumInterval: 0.75,
            reducedMinimumInterval: 1.5,
            lowPowerMinimumInterval: 1.25
        )

        XCTAssertEqual(policy.cadence(for: state(.nominal, lowPower: false)), .minimumInterval(0.75))
        XCTAssertEqual(policy.cadence(for: state(.fair, lowPower: false)), .minimumInterval(0.75))
        XCTAssertEqual(policy.cadence(for: state(.serious, lowPower: false)), .minimumInterval(1.5))
        XCTAssertEqual(policy.cadence(for: state(.critical, lowPower: false)), .suspended)
    }

    func testLowPowerModeReducesCadenceWithoutSuspendingNominalAnalysis() {
        let policy = AnalysisPerformancePolicy(
            normalMinimumInterval: 0.75,
            reducedMinimumInterval: 1.5,
            lowPowerMinimumInterval: 1.25
        )

        XCTAssertEqual(policy.cadence(for: state(.nominal, lowPower: true)), .minimumInterval(1.25))
        XCTAssertEqual(policy.cadence(for: state(.serious, lowPower: true)), .minimumInterval(1.5))
    }

    private func state(
        _ thermalState: AnalysisThermalState,
        lowPower: Bool
    ) -> AnalysisPerformanceState {
        AnalysisPerformanceState(thermalState: thermalState, isLowPowerModeEnabled: lowPower)
    }
}

final class AnalysisOrientationTests: XCTestCase {
    func testVideoRotationMapsToNormalizedImageOrientation() {
        XCTAssertEqual(AnalysisImageOrientation.from(videoRotationAngle: 0, isMirrored: false), .up)
        XCTAssertEqual(AnalysisImageOrientation.from(videoRotationAngle: 90, isMirrored: false), .right)
        XCTAssertEqual(AnalysisImageOrientation.from(videoRotationAngle: 180, isMirrored: false), .down)
        XCTAssertEqual(AnalysisImageOrientation.from(videoRotationAngle: 270, isMirrored: false), .left)
        XCTAssertEqual(AnalysisImageOrientation.from(videoRotationAngle: 90, isMirrored: true), .rightMirrored)
    }
}

private actor ResultRecorder {
    private var storedResults: [AnalysisPassResult] = []
    private var countWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    var results: [AnalysisPassResult] { storedResults }

    func append(_ result: AnalysisPassResult) {
        storedResults.append(result)
        let readyWaiters = countWaiters.filter { storedResults.count >= $0.0 }
        countWaiters.removeAll { storedResults.count >= $0.0 }
        readyWaiters.forEach { $0.1.resume() }
    }

    func waitForCount(_ count: Int) async {
        guard storedResults.count < count else { return }
        await withCheckedContinuation { continuation in
            countWaiters.append((count, continuation))
        }
    }
}

private actor ImmediateAnalyzer: AccessibilityAnalyzer {
    nonisolated let identifier = AnalyzerIdentifier(rawValue: "test.immediate")
    private(set) var invokedSequences: [UInt64] = []

    func analyze(_ context: AnalysisContext, priorOutput _: AnalyzerOutput) async throws -> AnalyzerOutput {
        invokedSequences.append(context.frame.sequence.rawValue)
        return .empty
    }
}

private actor FailingAnalyzer: AccessibilityAnalyzer {
    nonisolated let identifier = AnalyzerIdentifier(rawValue: "test.failing")

    func analyze(_ context: AnalysisContext, priorOutput _: AnalyzerOutput) async throws -> AnalyzerOutput {
        throw AnalysisError.analyzerFailed(identifier)
    }
}

private actor GateAnalyzer: AccessibilityAnalyzer {
    nonisolated let identifier = AnalyzerIdentifier(rawValue: "test.gate")

    private let honorsCancellation: Bool
    private(set) var invokedSequences: [UInt64] = []
    private var continuations: [UInt64: CheckedContinuation<AnalyzerOutput, Error>] = [:]
    private var invocationWaiters: [UInt64: [CheckedContinuation<Void, Never>]] = [:]
    private var cancellationWaiters: [UInt64: [CheckedContinuation<Void, Never>]] = [:]
    private var returnWaiters: [UInt64: [CheckedContinuation<Void, Never>]] = [:]
    private var cancelledSequences: Set<UInt64> = []
    private var returnedSequences: Set<UInt64> = []

    init(honorsCancellation: Bool = true) {
        self.honorsCancellation = honorsCancellation
    }

    func analyze(_ context: AnalysisContext, priorOutput _: AnalyzerOutput) async throws -> AnalyzerOutput {
        let sequence = context.frame.sequence.rawValue
        invokedSequences.append(sequence)
        invocationWaiters.removeValue(forKey: sequence)?.forEach { $0.resume() }

        do {
            let output: AnalyzerOutput
            if honorsCancellation {
                output = try await withTaskCancellationHandler(
                    operation: { try await self.awaitCompletion(sequence: sequence) },
                    onCancel: { Task { await self.cancel(sequence: sequence) } }
                )
            } else {
                output = try await awaitCompletion(sequence: sequence)
            }
            markReturned(sequence)
            return output
        } catch {
            markReturned(sequence)
            throw error
        }
    }

    func complete(sequence: UInt64) {
        continuations.removeValue(forKey: sequence)?.resume(returning: .empty)
    }

    func waitUntilInvoked(sequence: UInt64) async {
        guard !invokedSequences.contains(sequence) else { return }
        await withCheckedContinuation { continuation in
            invocationWaiters[sequence, default: []].append(continuation)
        }
    }

    func waitUntilCancelled(sequence: UInt64) async {
        guard !cancelledSequences.contains(sequence) else { return }
        await withCheckedContinuation { continuation in
            cancellationWaiters[sequence, default: []].append(continuation)
        }
    }

    func waitUntilReturned(sequence: UInt64) async {
        guard !returnedSequences.contains(sequence) else { return }
        await withCheckedContinuation { continuation in
            returnWaiters[sequence, default: []].append(continuation)
        }
    }

    private func awaitCompletion(sequence: UInt64) async throws -> AnalyzerOutput {
        try await withCheckedThrowingContinuation { continuation in
            continuations[sequence] = continuation
        }
    }

    private func cancel(sequence: UInt64) {
        cancelledSequences.insert(sequence)
        cancellationWaiters.removeValue(forKey: sequence)?.forEach { $0.resume() }
        continuations.removeValue(forKey: sequence)?.resume(throwing: CancellationError())
    }

    private func markReturned(_ sequence: UInt64) {
        returnedSequences.insert(sequence)
        returnWaiters.removeValue(forKey: sequence)?.forEach { $0.resume() }
    }
}
