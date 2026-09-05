import XCTest
@testable import AccessLens

final class VisualContrastDomainTests: XCTestCase {
    func testRelativeLuminanceMatchesKnownSRGBValues() {
        XCTAssertEqual(RelativeLuminance.value(for: rgb(0, 0, 0)), 0, accuracy: 0.000_001)
        XCTAssertEqual(RelativeLuminance.value(for: rgb(1, 1, 1)), 1, accuracy: 0.000_001)
        XCTAssertEqual(RelativeLuminance.value(for: rgb(0.5, 0.5, 0.5)), 0.214_041, accuracy: 0.000_01)
        XCTAssertEqual(RelativeLuminance.value(for: rgb(1, 0, 0)), 0.2126, accuracy: 0.000_001)
    }

    func testContrastRatioOrdersLuminanceAndHandlesEqualColors() {
        XCTAssertEqual(ContrastRatio(lighterLuminance: 1, darkerLuminance: 0).value, 21, accuracy: 0.000_001)
        XCTAssertEqual(ContrastRatio(lighterLuminance: 0, darkerLuminance: 1).value, 21, accuracy: 0.000_001)
        XCTAssertEqual(ContrastRatio(lighterLuminance: 0.3, darkerLuminance: 0.3).value, 1, accuracy: 0.000_001)
    }

    func testRegionConversionClampsEdgesRejectsEmptyAndMapsRightOrientation() {
        let dimensions = AnalysisFrameDimensions(width: 100, height: 200)
        XCTAssertEqual(
            ContrastRegionConverter.cropRect(
                for: NormalizedRegion(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
                dimensions: dimensions,
                orientation: .up
            ),
            PixelCropRect(x: 10, y: 40, width: 30, height: 80)
        )
        XCTAssertEqual(
            ContrastRegionConverter.cropRect(
                for: NormalizedRegion(x: -0.2, y: 0.9, width: 0.4, height: 0.3),
                dimensions: dimensions,
                orientation: .up
            ),
            PixelCropRect(x: 0, y: 180, width: 20, height: 20)
        )
        XCTAssertNil(ContrastRegionConverter.cropRect(
            for: NormalizedRegion(x: 0.2, y: 0.2, width: 0, height: 0.2),
            dimensions: dimensions,
            orientation: .up
        ))
        XCTAssertEqual(
            ContrastRegionConverter.cropRect(
                for: NormalizedRegion(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
                dimensions: dimensions,
                orientation: .right
            ),
            PixelCropRect(x: 20, y: 120, width: 40, height: 60)
        )
    }

    func testEvidenceQualityPolicyDistinguishesInsufficientLowAndUsableEvidence() {
        let policy = ContrastEvidenceQualityPolicy()
        XCTAssertEqual(policy.quality(sampleCount: 63, regionPixelArea: 500, luminanceSeparation: 0.2), .insufficient)
        XCTAssertEqual(policy.quality(sampleCount: 80, regionPixelArea: 500, luminanceSeparation: 0.05), .low)
        XCTAssertEqual(policy.quality(sampleCount: 128, regionPixelArea: 500, luminanceSeparation: 0.1), .usable)
    }

    func testClassificationUsesCentralizedHeuristicAndRefusesWeakEvidence() {
        let policy = EstimatedContrastPolicy()
        XCTAssertEqual(policy.classify(measurement(ratio: 7, quality: .usable)), .likelyAdequate)
        XCTAssertEqual(policy.classify(measurement(ratio: 3.5, quality: .usable)), .borderline)
        XCTAssertEqual(policy.classify(measurement(ratio: 2.8, quality: .usable)), .potentiallyLow)
        XCTAssertEqual(policy.classify(measurement(ratio: 2, quality: .low)), .insufficientEvidence)
    }

    func testEstimatorUsesTrimmedLuminanceBandsRatherThanSingleExtremePixels() throws {
        let samples = Array(repeating: rgb(0.2, 0.2, 0.2), count: 64)
            + Array(repeating: rgb(0.8, 0.8, 0.8), count: 64)
            + [rgb(0, 0, 0), rgb(1, 1, 1)]
        let result = try XCTUnwrap(VisualContrastEstimator.estimate(samples: samples, regionPixelArea: 1_000))
        XCTAssertEqual(result.lowerLuminanceEstimate, RelativeLuminance.value(for: rgb(0.2, 0.2, 0.2)), accuracy: 0.000_001)
        XCTAssertEqual(result.higherLuminanceEstimate, RelativeLuminance.value(for: rgb(0.8, 0.8, 0.8)), accuracy: 0.000_001)
        XCTAssertEqual(result.evidenceQuality, .usable)
    }

    func testTransientContrastStabilityDeduplicatesAndRequiresTwoMeasurements() {
        var stabilizer = TransientContrastCandidateStabilizer()
        let sessionID = AnalysisSessionID()
        let first = candidate(sessionID: sessionID, frame: 1, timestamp: 1)
        let second = candidate(sessionID: sessionID, frame: 2, timestamp: 2)
        let third = candidate(sessionID: sessionID, frame: 3, timestamp: 3)

        XCTAssertTrue(stabilizer.ingest([first], sessionID: sessionID, currentTime: 1).isEmpty)
        XCTAssertEqual(stabilizer.ingest([second], sessionID: sessionID, currentTime: 2).count, 1)
        XCTAssertTrue(stabilizer.ingest([third], sessionID: sessionID, currentTime: 3).isEmpty)
        XCTAssertEqual(stabilizer.candidates.count, 1)
    }

    func testContrastAnalyzerFailureIsIsolatedWhileTextOutputSurvives() async {
        let textAnalyzer = StaticTextAnalyzer()
        let failingAnalyzer = FailingContrastAnalyzer()
        let recorder = ContrastResultRecorder()
        let scheduler = AnalysisScheduler(
            analyzers: [textAnalyzer, failingAnalyzer],
            resultHandler: { result in Task { await recorder.append(result) } }
        )
        let sessionID = AnalysisSessionID()
        scheduler.beginSession(sessionID)
        scheduler.submit(sessionID: sessionID, presentationTimeSeconds: 0, orientation: .up, dimensions: nil)
        await recorder.waitForCount(1)

        let result = await recorder.results.first
        XCTAssertEqual(result?.textObservations.count, 1)
        XCTAssertEqual(result?.failures.first?.analyzerID, failingAnalyzer.identifier)
    }

    func testLateContrastResultFromPriorSessionIsRejected() async {
        let analyzer = LateContrastAnalyzer()
        let recorder = ContrastResultRecorder()
        let scheduler = AnalysisScheduler(
            analyzers: [analyzer],
            resultHandler: { result in Task { await recorder.append(result) } }
        )
        let firstSession = AnalysisSessionID()
        scheduler.beginSession(firstSession)
        scheduler.submit(sessionID: firstSession, presentationTimeSeconds: 0, orientation: .up, dimensions: nil)
        await analyzer.waitUntilInvoked()
        scheduler.beginSession(AnalysisSessionID())
        await analyzer.finish()
        await eventually { scheduler.snapshot().staleResultDiscardCount == 1 }
        let resultCount = await recorder.count
        XCTAssertEqual(resultCount, 0)
    }

    func testEndingSessionCancelsContrastWorkWithoutPublishing() async {
        let analyzer = CancellableContrastAnalyzer()
        let recorder = ContrastResultRecorder()
        let scheduler = AnalysisScheduler(
            analyzers: [analyzer],
            resultHandler: { result in Task { await recorder.append(result) } }
        )
        let sessionID = AnalysisSessionID()
        scheduler.beginSession(sessionID)
        scheduler.submit(sessionID: sessionID, presentationTimeSeconds: 0, orientation: .up, dimensions: nil)
        await analyzer.waitUntilInvoked()
        scheduler.endSession(sessionID)
        await analyzer.waitUntilCancelled()
        let resultCount = await recorder.count
        XCTAssertEqual(resultCount, 0)
    }

    private func rgb(_ red: Double, _ green: Double, _ blue: Double) -> ContrastRGBSample {
        ContrastRGBSample(red: red, green: green, blue: blue)
    }

    private func measurement(ratio: Double, quality: ContrastEvidenceQuality) -> VisualContrastMeasurement {
        let darker = 0.05
        let lighter = ratio * (darker + 0.05) - 0.05
        return VisualContrastMeasurement(
            lowerLuminanceEstimate: darker,
            higherLuminanceEstimate: lighter,
            ratio: ContrastRatio(lighterLuminance: lighter, darkerLuminance: darker),
            evidenceQuality: quality,
            sampleCount: 200,
            luminanceSeparation: lighter - darker
        )
    }

    private func candidate(sessionID: AnalysisSessionID, frame: UInt64, timestamp: Double) -> FindingCandidate {
        FindingCandidate(
            sessionID: sessionID,
            sourceObservationIDs: [UUID()],
            frameSequence: AnalysisFrameSequence(rawValue: frame),
            region: NormalizedRegion(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            evidenceKind: "visual-contrast.potential-low",
            category: .potentialLowContrastText,
            recognizedText: "EXIT",
            presentationTimeSeconds: timestamp,
            sourceAnalyzerID: AnalyzerIdentifier(rawValue: "test.contrast"),
            estimatedContrastRatio: ContrastRatio(lighterLuminance: 0.2, darkerLuminance: 0.02),
            contrastEvidenceQuality: .usable
        )
    }

    private func eventually(_ condition: @escaping () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not satisfied.")
    }
}

private actor ContrastResultRecorder {
    private(set) var results: [AnalysisPassResult] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    var count: Int { results.count }

    func append(_ result: AnalysisPassResult) {
        results.append(result)
        let ready = waiters.filter { results.count >= $0.0 }
        waiters.removeAll { results.count >= $0.0 }
        ready.forEach { $0.1.resume() }
    }

    func waitForCount(_ count: Int) async {
        guard results.count < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
}

private actor StaticTextAnalyzer: AccessibilityAnalyzer {
    nonisolated let identifier = AnalyzerIdentifier(rawValue: "test.text")

    func analyze(_ context: AnalysisContext, priorOutput _: AnalyzerOutput) async throws -> AnalyzerOutput {
        let text = RecognizedTextObservation(
            analyzerID: identifier,
            sessionID: context.frame.sessionID,
            frameSequence: context.frame.sequence,
            presentationTimeSeconds: context.frame.presentationTimeSeconds,
            text: "EXIT",
            rawFrameworkConfidence: 0.9,
            region: NormalizedRegion(x: 0, y: 0, width: 1, height: 1)
        )
        return AnalyzerOutput(textObservations: [text])
    }
}

private actor FailingContrastAnalyzer: AccessibilityAnalyzer {
    nonisolated let identifier = AnalyzerIdentifier(rawValue: "test.failing-contrast")
    func analyze(_ context: AnalysisContext, priorOutput _: AnalyzerOutput) async throws -> AnalyzerOutput {
        throw AnalysisError.analyzerFailed(identifier)
    }
}

private actor LateContrastAnalyzer: AccessibilityAnalyzer {
    nonisolated let identifier = AnalyzerIdentifier(rawValue: "test.late-contrast")
    private var continuation: CheckedContinuation<AnalyzerOutput, Never>?
    private var invoked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func analyze(_ context: AnalysisContext, priorOutput _: AnalyzerOutput) async throws -> AnalyzerOutput {
        invoked = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilInvoked() async {
        guard !invoked else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func finish() {
        continuation?.resume(returning: .empty)
        continuation = nil
    }
}

private actor CancellableContrastAnalyzer: AccessibilityAnalyzer {
    nonisolated let identifier = AnalyzerIdentifier(rawValue: "test.cancellable-contrast")
    private var continuation: CheckedContinuation<AnalyzerOutput, Error>?
    private var invoked = false
    private var cancelled = false
    private var invocationWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []

    func analyze(_ context: AnalysisContext, priorOutput _: AnalyzerOutput) async throws -> AnalyzerOutput {
        invoked = true
        invocationWaiters.forEach { $0.resume() }
        invocationWaiters.removeAll()
        return try await withTaskCancellationHandler(
            operation: { try await withCheckedThrowingContinuation { continuation = $0 } },
            onCancel: { Task { await self.cancel() } }
        )
    }

    func waitUntilInvoked() async {
        guard !invoked else { return }
        await withCheckedContinuation { invocationWaiters.append($0) }
    }

    func waitUntilCancelled() async {
        guard !cancelled else { return }
        await withCheckedContinuation { cancellationWaiters.append($0) }
    }

    private func cancel() {
        cancelled = true
        cancellationWaiters.forEach { $0.resume() }
        cancellationWaiters.removeAll()
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}
