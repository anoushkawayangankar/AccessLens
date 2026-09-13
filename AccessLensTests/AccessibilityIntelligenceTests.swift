import CoreVideo
import XCTest
@testable import AccessLens

final class AccessibilityIntelligenceTests: XCTestCase {
    func testQualityPolicyClassifiesGoodLimitedAndUnusableWithoutNumericScore() {
        let policy = ScanQualityPolicy()
        XCTAssertEqual(policy.classify(metrics(mean: 0.5, sharpness: 0.2, range: 0.8)).state, .good)
        XCTAssertEqual(policy.classify(metrics(mean: 0.5, sharpness: 0.005, range: 0.8)).state, .limited)
        XCTAssertEqual(
            policy.classify(metrics(mean: 0.02, dark: 0.95, sharpness: 0, range: 0.02)).state,
            .unusable
        )
        XCTAssertEqual(Set(ScanQualityState.allCases), [.good, .limited, .unusable])
    }

    func testSyntheticSharpAndBlurredLuminanceGridsClassifyDeterministically() {
        let sharpValues = (0..<64).map { index in (index + index / 8).isMultiple(of: 2) ? 0.05 : 0.95 }
        let sharp = ScanQualityEvaluator.metrics(for: LuminanceGrid(width: 8, height: 8, values: sharpValues))
        let blurredValues = (0..<256).map { index in Double(index % 128) / 127 }
        let blurred = ScanQualityEvaluator.metrics(for: LuminanceGrid(width: 128, height: 2, values: blurredValues))
        XCTAssertEqual(ScanQualityPolicy().classify(sharp).state, .good)
        let blurredQuality = ScanQualityPolicy().classify(blurred)
        XCTAssertEqual(blurredQuality.state, .limited)
        XCTAssertTrue(blurredQuality.reasons.contains(.lowSharpness))
    }

    func testExposurePolicyDistinguishesSevereDarkNormalAndSevereBright() {
        let policy = ScanQualityPolicy()
        XCTAssertEqual(policy.classify(metrics(mean: 0.02, dark: 0.9, range: 0.02)).reasons, [.severeUnderexposure])
        XCTAssertEqual(policy.classify(metrics(mean: 0.5, sharpness: 0.2, range: 0.8)).state, .good)
        XCTAssertEqual(policy.classify(metrics(mean: 0.98, bright: 0.9, saturated: 0.9, range: 0.02)).reasons, [.severeOverexposure])
    }

    func testHighlightSaturationAndClippingOnlyLimitEvidence() {
        let saturated = ScanQualityPolicy().classify(
            metrics(mean: 0.7, saturated: 0.4, sharpness: 0.1, range: 0.9)
        )
        XCTAssertEqual(saturated.state, .limited)
        XCTAssertTrue(saturated.reasons.contains(.possibleHighlightSaturation))
        let clipped = ScanFrameQuality(state: .good, reasons: [], metrics: nil).applyingFraming(
            to: [candidate(session: AnalysisSessionID(), frame: 1, time: 1,
                           region: NormalizedRegion(x: 0, y: 0.2, width: 0.2, height: 0.1))]
        )
        XCTAssertEqual(clipped.state, .limited)
        XCTAssertTrue(clipped.reasons.contains(.targetClipped))
    }

    func testUnusableFrameSkipsAnalyzerWork() async throws {
        let recorder = IntelligenceResultRecorder()
        let counter = AnalyzerCallCounter()
        let scheduler = AnalysisScheduler(
            analyzers: [CountingQualityAnalyzer(counter: counter)],
            performancePolicy: AnalysisPerformancePolicy(
                normalMinimumInterval: 0, reducedMinimumInterval: 0, lowPowerMinimumInterval: 0
            ),
            resultHandler: { result in Task { await recorder.record(result) } }
        )
        let session = AnalysisSessionID()
        scheduler.beginSession(session)
        let buffer = try XCTUnwrap(makeDarkPixelBuffer())
        scheduler.submit(
            sessionID: session,
            presentationTimeSeconds: 1,
            orientation: .up,
            dimensions: .init(width: 16, height: 16),
            payload: AnalysisFramePayload(imageBuffer: buffer, passageSurfaces: [])
        )
        let result = await recorder.nextResult()
        let callCount = await counter.value
        XCTAssertEqual(result.frameQuality.state, .unusable)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(callCount, 0)
    }

    func testLimitedEvidenceRequiresMoreSupportAndSurfacesAsLimited() throws {
        let stabilizer = AccessibilityFindingStabilizer()
        let session = AnalysisSessionID()
        stabilizer.beginSession(session)
        var result: FindingStabilizationResult?
        for frame in 1...5 {
            result = stabilizer.ingest(
                [candidate(session: session, frame: UInt64(frame), time: Double(frame))],
                sessionID: session,
                currentTime: Double(frame),
                frameQuality: ScanFrameQuality(state: .limited, reasons: [.lowSharpness], metrics: nil)
            )
        }
        XCTAssertTrue(result?.findings.isEmpty == true)
        result = stabilizer.ingest(
            [candidate(session: session, frame: 6, time: 5)],
            sessionID: session,
            currentTime: 5,
            frameQuality: ScanFrameQuality(state: .limited, reasons: [.lowSharpness], metrics: nil)
        )
        XCTAssertEqual(result?.findings.first?.evidenceStrength, .limited)
        let fused = AccessibilityEvidenceFusionEngine().fuse(try XCTUnwrap(result).evidence, sessionID: session)
        XCTAssertEqual(fused.findings.first?.evidenceStrength, .limited)
    }

    func testSingleWeakObservationDoesNotPromote() {
        let stabilizer = AccessibilityFindingStabilizer()
        let session = AnalysisSessionID()
        stabilizer.beginSession(session)
        let weak = candidate(session: session, frame: 1, time: 1, confidence: 0.4)
        let result = stabilizer.ingest([weak], sessionID: session, currentTime: 1)
        XCTAssertTrue(result.findings.isEmpty)
        XCTAssertTrue(result.evidence.isEmpty)
    }

    func testAnalyzerConfidenceNormalizationIsCategorySpecific() {
        let policy = AnalyzerConfidenceNormalizationPolicy()
        let session = AnalysisSessionID()
        XCTAssertEqual(policy.confidence(for: candidate(session: session, frame: 1, time: 1, confidence: 0.4)), .weak)
        XCTAssertEqual(policy.confidence(for: candidate(session: session, frame: 1, time: 1, confidence: 0.6)), .moderate)
        XCTAssertEqual(policy.confidence(for: candidate(session: session, frame: 1, time: 1, confidence: 0.8)), .strong)
        XCTAssertEqual(policy.confidence(for: passageCandidate(session: session, surfaceID: UUID(), frame: 1)), .strong)
        let signage = FindingCandidate(
            sessionID: session,
            sourceObservationIDs: [UUID()],
            frameSequence: .init(rawValue: 1),
            evidenceKind: "signage",
            category: .environmentalSignage
        )
        XCTAssertNil(policy.confidence(for: signage))
    }

    func testRepeatedConsistentEvidencePromotesWithAnalyzerSpecificProvenance() throws {
        let stabilizer = AccessibilityFindingStabilizer()
        let session = AnalysisSessionID()
        stabilizer.beginSession(session)
        var result: FindingStabilizationResult?
        for frame in 1...3 {
            result = stabilizer.ingest(
                [candidate(session: session, frame: UInt64(frame), time: Double(frame))],
                sessionID: session,
                currentTime: Double(frame)
            )
        }
        let evidence = try XCTUnwrap(result?.evidence.first)
        XCTAssertEqual(evidence.analyzerSources, [.text, .contrast])
        XCTAssertEqual(evidence.strength, .moderate)
        let fusion = AccessibilityEvidenceFusionEngine().fuse([evidence], sessionID: session)
        XCTAssertEqual(fusion.decisions[evidence.id], .surfaced)
        XCTAssertEqual(fusion.findings.count, 1)
    }

    func testWeakNormalizedConfidenceCannotBecomeStrongByFrameCountAlone() throws {
        let session = AnalysisSessionID()
        let weak = evidence(
            session: session,
            region: region(0.1, 0.1),
            first: 1,
            last: 6,
            confidence: .weak,
            supportingObservationCount: 6
        )
        let fusion = AccessibilityEvidenceFusionEngine().fuse([weak], sessionID: session)
        let finding = try XCTUnwrap(fusion.findings.first)
        XCTAssertEqual(finding.evidenceStrength, .limited)
        XCTAssertEqual(finding.qualityContext?.state, .good)
    }

    func testOneContradictoryFrameDoesNotDominateConsistentEvidence() {
        let stabilizer = AccessibilityFindingStabilizer()
        let session = AnalysisSessionID()
        stabilizer.beginSession(session)
        for frame in 1...3 {
            _ = stabilizer.ingest(
                [candidate(session: session, frame: UInt64(frame), time: Double(frame))],
                sessionID: session,
                currentTime: Double(frame)
            )
        }
        let contradictory = candidate(
            session: session, frame: 4, time: 4, category: .contrastLikelyAdequate
        )
        let result = stabilizer.ingest([contradictory], sessionID: session, currentTime: 4)
        XCTAssertEqual(result.findings.count, 1)
        XCTAssertNotEqual(result.findings.first?.evidenceStrength, .strong)
    }

    func testConsistentlyConflictingEvidenceSuppressesLowContrastFinding() {
        let stabilizer = AccessibilityFindingStabilizer()
        let session = AnalysisSessionID()
        stabilizer.beginSession(session)
        _ = stabilizer.ingest([candidate(session: session, frame: 1, time: 1)], sessionID: session, currentTime: 1)
        for frame in 2...4 {
            _ = stabilizer.ingest(
                [candidate(session: session, frame: UInt64(frame), time: Double(frame), category: .contrastLikelyAdequate)],
                sessionID: session,
                currentTime: Double(frame)
            )
        }
        XCTAssertTrue(stabilizer.findings(for: session).isEmpty)
    }

    func testFusionMergesDuplicatesButKeepsDifferentRegions() {
        let session = AnalysisSessionID()
        let engine = AccessibilityEvidenceFusionEngine()
        let first = evidence(session: session, region: region(0.1, 0.1), first: 1, last: 3)
        let duplicate = evidence(session: session, region: region(0.11, 0.1), first: 2, last: 4)
        let distinct = evidence(session: session, region: region(0.65, 0.1), first: 2, last: 4)
        let fused = engine.fuse([first, duplicate, distinct], sessionID: session)
        XCTAssertEqual(fused.findings.count, 2)
        XCTAssertEqual(fused.findings.map(\.supportingObservationCount).sorted(), [3, 6])
        XCTAssertEqual(
            fused.findings.first(where: { $0.supportingObservationCount == 6 })?.evidenceStrength,
            .moderate
        )
    }

    func testFusionDoesNotMergeSameRegionOutsideTemporalWindow() {
        let session = AnalysisSessionID()
        let early = evidence(session: session, region: region(0.1, 0.1), first: 0, last: 2)
        let later = evidence(session: session, region: region(0.1, 0.1), first: 10, last: 12)
        XCTAssertEqual(AccessibilityEvidenceFusionEngine().fuse([early, later], sessionID: session).findings.count, 2)

        let nonlocalFrames = evidence(
            session: session,
            region: region(0.1, 0.1),
            first: 3,
            last: 4,
            firstFrame: 1_000,
            lastFrame: 1_001
        )
        XCTAssertEqual(
            AccessibilityEvidenceFusionEngine().fuse([early, nonlocalFrames], sessionID: session).findings.count,
            2
        )
    }

    func testSignageAndContrastCorroborateButUnrelatedPassageDoesNotFuse() {
        let session = AnalysisSessionID()
        let signageContrast = evidence(session: session, region: region(0.1, 0.1), first: 1, last: 3)
        let passage = evidence(
            session: session,
            category: .potentialNarrowPassage,
            sources: [.passage],
            sourceIDs: [.init(rawValue: "roomplan.passage.v1")],
            region: region(0.6, 0.1),
            first: 1,
            last: 3
        )
        let result = AccessibilityEvidenceFusionEngine().fuse([signageContrast, passage], sessionID: session)
        XCTAssertEqual(result.findings.count, 2)
        XCTAssertEqual(signageContrast.analyzerSources, [.text, .contrast])
    }

    func testPoorPassageQualityIsSuppressedUntilEnoughLimitedSupportExists() {
        let stabilizer = AccessibilityFindingStabilizer()
        let session = AnalysisSessionID()
        stabilizer.beginSession(session)
        let surfaceID = UUID()
        for frame in 1...3 {
            _ = stabilizer.ingest(
                [passageCandidate(session: session, surfaceID: surfaceID, frame: UInt64(frame))],
                sessionID: session,
                currentTime: Double(frame),
                frameQuality: ScanFrameQuality(state: .limited, reasons: [.targetClipped], metrics: nil)
            )
        }
        XCTAssertTrue(stabilizer.findings(for: session).isEmpty)
    }

    func testFusionRejectsOldSessionAndUnusableEvidence() {
        let current = AnalysisSessionID()
        let old = evidence(session: AnalysisSessionID(), region: region(0.1, 0.1), first: 1, last: 3)
        let unusable = evidence(
            session: current, region: region(0.1, 0.1), first: 1, last: 3,
            quality: .unusable
        )
        let result = AccessibilityEvidenceFusionEngine().fuse([old, unusable], sessionID: current)
        XCTAssertTrue(result.findings.isEmpty)
        XCTAssertTrue(result.decisions.isEmpty)
    }

    func testQualityGuidanceUsesPriorityAndDebouncesChanges() {
        let stabilizer = ScanQualityGuidanceStabilizer()
        let session = AnalysisSessionID()
        stabilizer.beginSession(session)
        let limited = ScanFrameQuality(
            state: .limited,
            reasons: [.possibleHighlightSaturation, .targetClipped],
            metrics: nil
        )
        XCTAssertNil(stabilizer.ingest(limited, sessionID: session)?.guidance)
        XCTAssertEqual(stabilizer.ingest(limited, sessionID: session)?.guidance, "Keep the area fully in view.")
        let good = ScanFrameQuality(state: .good, reasons: [], metrics: nil)
        XCTAssertNotNil(stabilizer.ingest(good, sessionID: session)?.guidance)
        XCTAssertNil(stabilizer.ingest(good, sessionID: session)?.guidance)
        stabilizer.endSession(session)
        XCTAssertNil(stabilizer.ingest(limited, sessionID: session))
    }

    private func metrics(
        mean: Double,
        dark: Double = 0,
        bright: Double = 0,
        saturated: Double = 0,
        sharpness: Double = 0.1,
        range: Double = 0.5
    ) -> ScanQualityMetrics {
        ScanQualityMetrics(
            meanLuminance: mean,
            darkFraction: dark,
            brightFraction: bright,
            saturatedFraction: saturated,
            sharpness: sharpness,
            luminanceRange: range
        )
    }

    private func candidate(
        session: AnalysisSessionID,
        frame: UInt64,
        time: TimeInterval,
        category: FindingCandidateCategory = .potentialLowContrastText,
        region: NormalizedRegion = NormalizedRegion(x: 0.1, y: 0.1, width: 0.2, height: 0.1),
        confidence: Double = 0.9
    ) -> FindingCandidate {
        FindingCandidate(
            sessionID: session,
            sourceObservationIDs: [UUID(), UUID()],
            frameSequence: .init(rawValue: frame),
            region: region,
            evidenceKind: category == .potentialLowContrastText
                ? "visual-contrast.potential-low" : "visual-contrast.likely-adequate",
            category: category,
            recognizedText: "EXIT",
            rawFrameworkConfidence: confidence,
            presentationTimeSeconds: time,
            sourceAnalyzerID: .init(rawValue: "vision.visual-contrast.v1"),
            sourceAnalyzerIDs: [
                .init(rawValue: "vision.text.v1"),
                .init(rawValue: "vision.visual-contrast.v1")
            ],
            estimatedContrastRatio: ContrastRatio(estimatedValue: category == .potentialLowContrastText ? 2.2 : 7),
            contrastEvidenceQuality: .usable
        )
    }

    private func passageCandidate(
        session: AnalysisSessionID,
        surfaceID: UUID,
        frame: UInt64
    ) -> FindingCandidate {
        FindingCandidate(
            sessionID: session,
            sourceObservationIDs: [UUID()],
            frameSequence: .init(rawValue: frame),
            region: NormalizedRegion(x: 0.2, y: 0.1, width: 0.4, height: 0.8),
            evidenceKind: "passage.potential-narrow",
            category: .potentialNarrowPassage,
            presentationTimeSeconds: Double(frame),
            sourceAnalyzerID: .init(rawValue: "roomplan.passage.v1"),
            passageSurfaceID: surfaceID,
            passageEvidence: PassageFindingEvidence(
                estimatedWidth: PassageWidth(meters: 0.84),
                measurementMethod: .roomPlanLiDAR,
                measurementQuality: .usable
            )
        )
    }

    private func evidence(
        session: AnalysisSessionID,
        category: AccessibilityFindingCategory = .potentialLowContrastText,
        sources: Set<AccessibilityAnalyzerSource> = [.text, .contrast],
        sourceIDs: [AnalyzerIdentifier] = [
            .init(rawValue: "vision.text.v1"),
            .init(rawValue: "vision.visual-contrast.v1")
        ],
        region: NormalizedRegion,
        first: TimeInterval,
        last: TimeInterval,
        quality: ScanQualityState = .good,
        confidence: NormalizedEvidenceConfidence = .moderate,
        supportingObservationCount: Int = 3,
        firstFrame: UInt64? = nil,
        lastFrame: UInt64? = nil
    ) -> AccessibilityEvidence {
        AccessibilityEvidence(
            sessionID: session,
            category: category,
            analyzerSources: sources,
            sourceAnalyzerIDs: sourceIDs,
            firstObservedTime: first,
            lastObservedTime: last,
            supportingFrameRange: .init(
                first: .init(rawValue: firstFrame ?? UInt64(first)),
                last: .init(rawValue: lastFrame ?? UInt64(last))
            ),
            region: region,
            strength: .moderate,
            normalizedConfidence: confidence,
            qualityContext: FindingQualityContext(state: quality, summary: "Synthetic quality context."),
            supportingObservationCount: supportingObservationCount,
            sourceSummary: "Synthetic source summary.",
            title: category == .potentialNarrowPassage ? "Potential narrow passage" : "Potential low contrast",
            explanation: "Review this possible issue directly.",
            relevantText: category == .potentialLowContrastText ? "EXIT" : nil,
            estimatedContrastRatio: category == .potentialLowContrastText ? ContrastRatio(estimatedValue: 2.2) : nil,
            passageEvidence: category == .potentialNarrowPassage
                ? PassageFindingEvidence(
                    estimatedWidth: PassageWidth(meters: 0.84),
                    measurementMethod: .roomPlanLiDAR,
                    measurementQuality: .usable
                ) : nil
        )
    }

    private func region(_ x: Double, _ y: Double) -> NormalizedRegion {
        NormalizedRegion(x: x, y: y, width: 0.2, height: 0.1)
    }

    private func makeDarkPixelBuffer() -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, 16, 16, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let address = CVPixelBufferGetBaseAddress(buffer) {
            address.initializeMemory(as: UInt8.self, repeating: 0, count: CVPixelBufferGetDataSize(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
}

private actor AnalyzerCallCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private struct CountingQualityAnalyzer: AccessibilityAnalyzer {
    let identifier = AnalyzerIdentifier(rawValue: "test.quality-count")
    let counter: AnalyzerCallCounter

    func analyze(_ context: AnalysisContext, priorOutput _: AnalyzerOutput) async throws -> AnalyzerOutput {
        await counter.increment()
        return AnalyzerOutput(observations: [NormalizedObservation(
            analyzerID: identifier,
            sessionID: context.frame.sessionID,
            frameSequence: context.frame.sequence,
            evidenceKind: "test.called"
        )])
    }
}

private actor IntelligenceResultRecorder {
    private var result: AnalysisPassResult?
    private var waiter: CheckedContinuation<AnalysisPassResult, Never>?

    func record(_ result: AnalysisPassResult) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: result)
        } else {
            self.result = result
        }
    }

    func nextResult() async -> AnalysisPassResult {
        if let result {
            self.result = nil
            return result
        }
        return await withCheckedContinuation { waiter = $0 }
    }
}
