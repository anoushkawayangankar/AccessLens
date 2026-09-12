import CoreVideo
import XCTest
@testable import AccessLens

final class PassageAnalysisTests: XCTestCase {
    func testCapabilityTiersNeverTreatIntrinsicsAsPhysicalScale() {
        let policy = PassageCaptureCapabilityPolicy()
        XCTAssertEqual(policy.capability(roomPlanSupported: true, hasCameraIntrinsics: true), .roomPlanLiDAR)
        XCTAssertEqual(policy.capability(roomPlanSupported: false, hasCameraIntrinsics: true), .cameraGeometryWithoutScale)
        XCTAssertEqual(policy.capability(roomPlanSupported: false, hasCameraIntrinsics: false), .unavailable)
        XCTAssertTrue(PassageCaptureCapability.roomPlanLiDAR.supportsPassageAnalysis)
        XCTAssertFalse(PassageCaptureCapability.cameraGeometryWithoutScale.supportsPassageAnalysis)
    }

    func testWidthHasExplicitCanonicalUnitsAndSafeConversion() throws {
        let width = try XCTUnwrap(PassageWidth(meters: 0.84))
        XCTAssertEqual(width.measurement.unit, .meters)
        XCTAssertEqual(width.measurement.converted(to: .centimeters).value, 84, accuracy: 0.0001)
        XCTAssertNil(PassageWidth(meters: 0))
        XCTAssertNil(PassageWidth(meters: .infinity))
    }

    func testEveryMeasurementQualityHasDeterministicNumericPolicy() {
        XCTAssertFalse(PassageMeasurementQuality.unavailable.supportsNumericPresentation)
        XCTAssertFalse(PassageMeasurementQuality.insufficient.supportsNumericPresentation)
        XCTAssertTrue(PassageMeasurementQuality.approximate.supportsNumericPresentation)
        XCTAssertTrue(PassageMeasurementQuality.usable.supportsNumericPresentation)
        XCTAssertEqual(PassageMeasurementQuality.allCases.map(\.displayName).count, 4)
    }

    func testAnalyzerCreatesCandidateOnlyForUsableLiDARWidth() async throws {
        let session = AnalysisSessionID()
        let surfaces = [
            surface(width: 0.84, quality: .usable),
            surface(width: 0.80, quality: .approximate),
            surface(width: nil, quality: .insufficient, method: .unavailable),
            surface(width: 1.2, quality: .usable)
        ]
        let output = try await PassageAccessibilityAnalyzer().analyze(
            context(session: session, surfaces: surfaces), priorOutput: .empty
        )
        XCTAssertEqual(output.passageObservations.count, 4)
        XCTAssertEqual(output.candidates.count, 1)
        XCTAssertEqual(output.candidates.first?.category, .potentialNarrowPassage)
        XCTAssertEqual(output.candidates.first?.passageEvidence?.estimatedWidth?.meters, 0.84)
    }

    func testUnsupportedGeometryProducesNoFakeWidthOrCandidate() async throws {
        let evidence = surface(width: nil, quality: .unavailable, method: .unavailable)
        let output = try await PassageAccessibilityAnalyzer().analyze(
            context(session: AnalysisSessionID(), surfaces: [evidence]), priorOutput: .empty
        )
        XCTAssertNil(output.passageObservations.first?.estimatedWidth)
        XCTAssertEqual(output.passageObservations.first?.measurementMethod, .unavailable)
        XCTAssertTrue(output.candidates.isEmpty)
    }

    func testRobustMedianRejectsLargeOutlier() throws {
        let widths = try [0.84, 0.85, 1.60, 0.83].map { try XCTUnwrap(PassageWidth(meters: $0)) }
        let result = try XCTUnwrap(PassageMeasurementAggregator.medianRejectingOutliers(widths))
        XCTAssertEqual(result.meters, 0.84, accuracy: 0.0001)
        XCTAssertEqual(PassageMeasurementAggregator.inliers(widths).count, 3)
    }

    func testSingleObservationDoesNotPromoteAndRepeatedEvidenceDoes() {
        let stabilizer = AccessibilityFindingStabilizer()
        let session = AnalysisSessionID()
        let surfaceID = UUID()
        stabilizer.beginSession(session)
        var result = stabilizer.ingest([candidate(session: session, surfaceID: surfaceID, sequence: 1, width: 0.84)], sessionID: session, currentTime: 1)
        XCTAssertTrue(result.findings.isEmpty)
        result = stabilizer.ingest([candidate(session: session, surfaceID: surfaceID, sequence: 2, width: 0.85)], sessionID: session, currentTime: 2)
        XCTAssertTrue(result.findings.isEmpty)
        result = stabilizer.ingest([candidate(session: session, surfaceID: surfaceID, sequence: 3, width: 0.83)], sessionID: session, currentTime: 3)
        XCTAssertEqual(result.findings.count, 1)
        XCTAssertEqual(result.findings.first?.category, .potentialNarrowPassage)
        XCTAssertEqual(result.findings.first?.passageEvidence?.estimatedWidth?.meters ?? 0, 0.84, accuracy: 0.0001)
    }

    func testOverlappingChangingSurfaceIdentityAssociatesButDistinctRegionsDoNotMerge() {
        let stabilizer = AccessibilityFindingStabilizer()
        let session = AnalysisSessionID()
        stabilizer.beginSession(session)
        let left = NormalizedRegion(x: 0.1, y: 0.1, width: 0.3, height: 0.8)
        let overlapping = NormalizedRegion(x: 0.11, y: 0.1, width: 0.3, height: 0.8)
        let right = NormalizedRegion(x: 0.6, y: 0.1, width: 0.3, height: 0.8)
        for sequence in 1...3 {
            let region = sequence.isMultiple(of: 2) ? overlapping : left
            _ = stabilizer.ingest([
                candidate(session: session, surfaceID: UUID(), sequence: UInt64(sequence), width: 0.84, region: region),
                candidate(session: session, surfaceID: UUID(), sequence: UInt64(sequence), width: 0.82, region: right)
            ], sessionID: session, currentTime: Double(sequence))
        }
        let findings = stabilizer.findings(for: session)
        XCTAssertEqual(findings.count, 2)
        XCTAssertNotEqual(findings[0].id, findings[1].id)
    }

    func testSessionEndClearsPassageEvidenceAndRejectsLateCandidate() {
        let stabilizer = AccessibilityFindingStabilizer()
        let first = AnalysisSessionID()
        let second = AnalysisSessionID()
        let surfaceID = UUID()
        stabilizer.beginSession(first)
        for sequence in 1...3 {
            _ = stabilizer.ingest([candidate(session: first, surfaceID: surfaceID, sequence: UInt64(sequence), width: 0.84)], sessionID: first, currentTime: Double(sequence))
        }
        XCTAssertEqual(stabilizer.findings(for: first).count, 1)
        stabilizer.endSession(first)
        stabilizer.beginSession(second)
        let late = stabilizer.ingest([candidate(session: first, surfaceID: surfaceID, sequence: 4, width: 0.84)], sessionID: first, currentTime: 4)
        XCTAssertTrue(late.findings.isEmpty)
        XCTAssertTrue(stabilizer.findings(for: second).isEmpty)
    }

    func testPassageAndContrastTracksShareExistingBounds() {
        let policy = FindingStabilizationPolicy(maximumCandidateTracks: 3)
        let stabilizer = AccessibilityFindingStabilizer(policy: policy)
        let session = AnalysisSessionID()
        stabilizer.beginSession(session)
        for sequence in 1...20 {
            _ = stabilizer.ingest([
                candidate(session: session, surfaceID: UUID(), sequence: UInt64(sequence), width: 0.84,
                          region: NormalizedRegion(x: Double(sequence % 10) / 10, y: 0, width: 0.05, height: 0.5))
            ], sessionID: session, currentTime: Double(sequence))
        }
        XCTAssertLessThanOrEqual(stabilizer.snapshot().candidateTrackCount, 3)
        XCTAssertLessThanOrEqual(stabilizer.snapshot().maximumEvidenceEntriesInTrack, policy.maximumEvidenceEntriesPerTrack)
    }

    func testPassageAnalyzerFailureDoesNotRemoveOtherAnalyzerOutput() async {
        let recorder = PassageResultRecorder()
        let scheduler = AnalysisScheduler(
            analyzers: [PassageSentinelAnalyzer(), PassageFailingAnalyzer()],
            performancePolicy: AnalysisPerformancePolicy(normalMinimumInterval: 0, reducedMinimumInterval: 0, lowPowerMinimumInterval: 0),
            resultHandler: { result in Task { await recorder.record(result) } }
        )
        let session = AnalysisSessionID()
        scheduler.beginSession(session)
        scheduler.submit(sessionID: session, presentationTimeSeconds: 1, orientation: .up, dimensions: nil)
        let result = await recorder.nextResult()
        XCTAssertEqual(result.observations.map(\.evidenceKind), ["test.existing-analysis"])
        XCTAssertEqual(result.failures.map(\.analyzerID.rawValue), ["roomplan.passage.failure-test"])
    }

    private func surface(
        width: Double?,
        quality: PassageMeasurementQuality,
        method: PassageMeasurementMethod = .roomPlanLiDAR
    ) -> PassageSurfaceEvidence {
        PassageSurfaceEvidence(
            surfaceID: UUID(), kind: .door,
            region: NormalizedRegion(x: 0.2, y: 0.1, width: 0.4, height: 0.8),
            estimatedWidth: width.flatMap(PassageWidth.init(meters:)),
            measurementMethod: method,
            measurementQuality: quality
        )
    }

    private func context(session: AnalysisSessionID, surfaces: [PassageSurfaceEvidence]) -> AnalysisContext {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 2, 2, kCVPixelFormatType_32BGRA, nil, &buffer)
        return AnalysisContext(
            frame: AnalysisFrame(
                sessionID: session, sequence: .init(rawValue: 1), presentationTimeSeconds: 1,
                orientation: .up, dimensions: .init(width: 2, height: 2)
            ),
            payload: buffer.map { AnalysisFramePayload(imageBuffer: $0, passageSurfaces: surfaces) }
        )
    }

    private func candidate(
        session: AnalysisSessionID,
        surfaceID: UUID,
        sequence: UInt64,
        width: Double,
        region: NormalizedRegion = NormalizedRegion(x: 0.2, y: 0.1, width: 0.4, height: 0.8)
    ) -> FindingCandidate {
        FindingCandidate(
            sessionID: session,
            sourceObservationIDs: [UUID()],
            frameSequence: .init(rawValue: sequence),
            region: region,
            evidenceKind: "passage.potential-narrow",
            category: .potentialNarrowPassage,
            presentationTimeSeconds: Double(sequence),
            sourceAnalyzerID: .init(rawValue: "roomplan.passage.v1"),
            passageSurfaceID: surfaceID,
            passageEvidence: PassageFindingEvidence(
                estimatedWidth: PassageWidth(meters: width),
                measurementMethod: .roomPlanLiDAR,
                measurementQuality: .usable
            )
        )
    }
}

private actor PassageResultRecorder {
    private var result: AnalysisPassResult?
    private var waiter: CheckedContinuation<AnalysisPassResult, Never>?

    func record(_ value: AnalysisPassResult) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: value)
        } else {
            result = value
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

private struct PassageSentinelAnalyzer: AccessibilityAnalyzer {
    let identifier = AnalyzerIdentifier(rawValue: "test.existing")

    func analyze(_ context: AnalysisContext, priorOutput _: AnalyzerOutput) async throws -> AnalyzerOutput {
        AnalyzerOutput(observations: [NormalizedObservation(
            analyzerID: identifier,
            sessionID: context.frame.sessionID,
            frameSequence: context.frame.sequence,
            evidenceKind: "test.existing-analysis"
        )])
    }
}

private struct PassageFailingAnalyzer: AccessibilityAnalyzer {
    let identifier = AnalyzerIdentifier(rawValue: "roomplan.passage.failure-test")

    func analyze(_ context: AnalysisContext, priorOutput _: AnalyzerOutput) async throws -> AnalyzerOutput {
        throw AnalysisError.insufficientCalibration
    }
}
