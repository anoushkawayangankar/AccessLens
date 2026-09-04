import XCTest
@testable import AccessLens

final class VisionTextAnalysisTests: XCTestCase {
    func testTextNormalizationCollapsesWhitespaceRejectsEmptyAndPreservesDisplayCasing() {
        XCTAssertEqual(VisionTextObservationMapper.normalizedText("  Emergency\n Exit  ", maximumCharacterCount: 48), "Emergency Exit")
        XCTAssertNil(VisionTextObservationMapper.normalizedText(" \n\t ", maximumCharacterCount: 48))
        XCTAssertNil(VisionTextObservationMapper.normalizedText(String(repeating: "A", count: 49), maximumCharacterCount: 48))
    }

    func testObservationMappingPreservesMetadataConfidenceAndTransformsVisionCoordinates() throws {
        let sessionID = AnalysisSessionID(rawValue: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)
        let context = AnalysisContext(frame: AnalysisFrame(
            sessionID: sessionID,
            sequence: AnalysisFrameSequence(rawValue: 7),
            presentationTimeSeconds: 12.5,
            orientation: .up,
            dimensions: AnalysisFrameDimensions(width: 1920, height: 1080)
        ))
        let output = VisionTextObservationMapper.makeOutput(
            recognizedResults: [VisionTextRecognitionResult(
                text: " Exit ",
                confidence: 0.9,
                visionBoundingBox: NormalizedRegion(x: 0.2, y: 0.6, width: 0.3, height: 0.1)
            )],
            context: context,
            analyzerID: AnalyzerIdentifier(rawValue: "test.vision"),
            configuration: .environmentalSignage,
            classifier: SignageCandidateClassifier()
        )

        XCTAssertEqual(output.textObservations.count, 1)
        let observation = try XCTUnwrap(output.textObservations.first)
        XCTAssertEqual(observation.text, "Exit")
        XCTAssertEqual(observation.sessionID, sessionID)
        XCTAssertEqual(observation.frameSequence.rawValue, 7)
        XCTAssertEqual(observation.presentationTimeSeconds, 12.5)
        XCTAssertEqual(observation.rawFrameworkConfidence, 0.9)
        XCTAssertEqual(observation.region.x, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(observation.region.y, 0.3, accuracy: 0.000_001)
        XCTAssertEqual(observation.region.width, 0.3, accuracy: 0.000_001)
        XCTAssertEqual(observation.region.height, 0.1, accuracy: 0.000_001)
        XCTAssertEqual(output.observations.first?.id, observation.id)
    }

    func testLowConfidenceRecognitionIsFilteredBeforeCandidateClassification() {
        let output = mappedOutput(text: "EXIT", confidence: 0.34)
        XCTAssertTrue(output.textObservations.isEmpty)
        XCTAssertTrue(output.candidates.isEmpty)
    }

    func testSignageClassifierMatchesInitialKeywordsAcrossCasingWithoutClassifyingParagraphs() {
        let classifier = SignageCandidateClassifier()
        for text in ["exit", "EXIT", "Exit", "Emergency Exit", "Elevator", "Accessible Entrance", "Restroom"] {
            XCTAssertNotNil(classifier.classify(makeTextObservation(text: text)), "Expected \(text) to classify")
        }

        XCTAssertNil(classifier.classify(makeTextObservation(text: "This is a long paragraph describing the building and its history in detail.")))
        XCTAssertNil(classifier.classify(makeTextObservation(text: "")))
    }

    func testTransientDeduplicationKeepsOneRepeatedSignageCandidate() {
        var deduplicator = TransientSignageDeduplicator(maximumCandidates: 4, retentionInterval: 8)
        let sessionID = AnalysisSessionID()
        let first = makeCandidate(text: "EXIT", sessionID: sessionID, frame: 1, timestamp: 1)
        let second = makeCandidate(text: "exit", sessionID: sessionID, frame: 2, timestamp: 2)
        let third = makeCandidate(text: "EXIT", sessionID: sessionID, frame: 3, timestamp: 3)

        XCTAssertEqual(deduplicator.ingest([first], sessionID: sessionID, currentTime: 1).count, 1)
        XCTAssertTrue(deduplicator.ingest([second], sessionID: sessionID, currentTime: 2).isEmpty)
        XCTAssertTrue(deduplicator.ingest([third], sessionID: sessionID, currentTime: 3).isEmpty)
        XCTAssertEqual(deduplicator.candidates.count, 1)
        XCTAssertEqual(deduplicator.candidates.first?.frameSequence.rawValue, 3)
    }

    func testLateTextResultFromPreviousSessionIsDiscarded() async {
        let analyzer = LateTextAnalyzer()
        let recorder = TextResultRecorder()
        let scheduler = AnalysisScheduler(
            analyzers: [analyzer],
            resultHandler: { result in Task { await recorder.append(result) } }
        )
        let first = AnalysisSessionID()
        scheduler.beginSession(first)
        scheduler.submit(sessionID: first, presentationTimeSeconds: 0, orientation: .up, dimensions: nil)
        await analyzer.waitUntilInvoked()

        scheduler.beginSession(AnalysisSessionID())
        await analyzer.finish()
        await eventually { scheduler.snapshot().staleResultDiscardCount == 1 }
        let resultCount = await recorder.count
        XCTAssertEqual(resultCount, 0)
    }

    func testCancellationStopsTextWorkAndPublishesNoLateResult() async {
        let analyzer = CancellableTextAnalyzer()
        let recorder = TextResultRecorder()
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

    func testTextAnalyzerFailureIsIsolatedAndReported() async {
        let analyzer = FailingTextAnalyzer()
        let recorder = TextResultRecorder()
        let scheduler = AnalysisScheduler(
            analyzers: [analyzer],
            resultHandler: { result in Task { await recorder.append(result) } }
        )
        let sessionID = AnalysisSessionID()
        scheduler.beginSession(sessionID)
        scheduler.submit(sessionID: sessionID, presentationTimeSeconds: 0, orientation: .up, dimensions: nil)
        await recorder.waitForCount(1)

        let results = await recorder.results
        let failure = results.first?.failures.first
        XCTAssertEqual(failure, AnalysisFailure(analyzerID: analyzer.identifier, error: .analyzerFailed(analyzer.identifier)))
    }

    private func mappedOutput(text: String, confidence: Double) -> AnalyzerOutput {
        VisionTextObservationMapper.makeOutput(
            recognizedResults: [VisionTextRecognitionResult(
                text: text,
                confidence: confidence,
                visionBoundingBox: NormalizedRegion(x: 0, y: 0, width: 1, height: 1)
            )],
            context: AnalysisContext(frame: AnalysisFrame(
                sessionID: AnalysisSessionID(),
                sequence: AnalysisFrameSequence(rawValue: 1),
                presentationTimeSeconds: 0,
                orientation: .up,
                dimensions: nil
            )),
            analyzerID: AnalyzerIdentifier(rawValue: "test.vision"),
            configuration: .environmentalSignage,
            classifier: SignageCandidateClassifier()
        )
    }

    private func makeTextObservation(text: String) -> RecognizedTextObservation {
        RecognizedTextObservation(
            analyzerID: AnalyzerIdentifier(rawValue: "test.vision"),
            sessionID: AnalysisSessionID(),
            frameSequence: AnalysisFrameSequence(rawValue: 1),
            presentationTimeSeconds: 0,
            text: text,
            rawFrameworkConfidence: 0.9,
            region: NormalizedRegion(x: 0, y: 0, width: 1, height: 1)
        )
    }

    private func makeCandidate(
        text: String,
        sessionID: AnalysisSessionID,
        frame: UInt64,
        timestamp: Double
    ) -> FindingCandidate {
        FindingCandidate(
            sessionID: sessionID,
            sourceObservationIDs: [UUID()],
            frameSequence: AnalysisFrameSequence(rawValue: frame),
            region: NormalizedRegion(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            evidenceKind: "signage.exit",
            category: .environmentalSignage,
            recognizedText: text,
            rawFrameworkConfidence: 0.9,
            presentationTimeSeconds: timestamp,
            sourceAnalyzerID: AnalyzerIdentifier(rawValue: "test.vision")
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

private actor TextResultRecorder {
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

private actor LateTextAnalyzer: AccessibilityAnalyzer {
    nonisolated let identifier = AnalyzerIdentifier(rawValue: "test.late-text")
    private var continuation: CheckedContinuation<AnalyzerOutput, Never>?
    private var invoked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func analyze(_ context: AnalysisContext) async throws -> AnalyzerOutput {
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

private actor CancellableTextAnalyzer: AccessibilityAnalyzer {
    nonisolated let identifier = AnalyzerIdentifier(rawValue: "test.cancellable-text")
    private var continuation: CheckedContinuation<AnalyzerOutput, Error>?
    private var invoked = false
    private var cancelled = false
    private var invocationWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []

    func analyze(_ context: AnalysisContext) async throws -> AnalyzerOutput {
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

private actor FailingTextAnalyzer: AccessibilityAnalyzer {
    nonisolated let identifier = AnalyzerIdentifier(rawValue: "test.failing-text")

    func analyze(_ context: AnalysisContext) async throws -> AnalyzerOutput {
        throw AnalysisError.analyzerFailed(identifier)
    }
}
