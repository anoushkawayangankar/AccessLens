import XCTest
@testable import AccessLens

final class AccessibilityFindingStabilizerTests: XCTestCase {
    func testNormalizedRegionAssociationHandlesExactStrongPartialNoneAndInvalidRegions() {
        let base = region(0.1, 0.1, 0.2, 0.2)
        XCTAssertEqual(NormalizedRegionAssociation.intersectionOverUnion(base, base), 1, accuracy: 0.000_001)
        XCTAssertGreaterThan(NormalizedRegionAssociation.intersectionOverUnion(base, region(0.12, 0.12, 0.2, 0.2)), 0.5)
        XCTAssertLessThan(NormalizedRegionAssociation.intersectionOverUnion(base, region(0.25, 0.25, 0.2, 0.2)), 0.1)
        XCTAssertEqual(NormalizedRegionAssociation.intersectionOverUnion(base, region(0.7, 0.7, 0.1, 0.1)), 0)
        XCTAssertEqual(NormalizedRegionAssociation.intersectionOverUnion(base, region(0.1, 0.1, 0, 0.2)), 0)
    }

    func testTextAssociationIsCaseInsensitiveWithoutFuzzyMerging() {
        XCTAssertEqual(FindingTextAssociation.normalizedIdentity("EXIT"), FindingTextAssociation.normalizedIdentity("Exit"))
        XCTAssertEqual(FindingTextAssociation.normalizedIdentity("EXIT"), FindingTextAssociation.normalizedIdentity("exit"))
        XCTAssertNotEqual(FindingTextAssociation.normalizedIdentity("EXIT"), FindingTextAssociation.normalizedIdentity("ENTRY"))
        XCTAssertNil(FindingTextAssociation.normalizedIdentity(" \n "))
    }

    func testPromotionRequiresRepeatedAssociatedUsableEvidence() {
        let stabilizer = AccessibilityFindingStabilizer()
        let sessionID = AnalysisSessionID()
        stabilizer.beginSession(sessionID)

        XCTAssertTrue(ingest(stabilizer, candidate(sessionID: sessionID, frame: 1, time: 1)).findings.isEmpty)
        XCTAssertTrue(ingest(stabilizer, candidate(sessionID: sessionID, frame: 2, time: 2)).findings.isEmpty)
        let result = ingest(stabilizer, candidate(sessionID: sessionID, frame: 3, time: 3))
        XCTAssertEqual(result.findings.count, 1)
        XCTAssertEqual(result.findings.first?.evidenceStrength, .moderate)
        XCTAssertEqual(result.newlyPromotedFindingIDs.count, 1)
    }

    func testSingleLowQualityOrOneOffCandidateDoesNotPromote() {
        let stabilizer = AccessibilityFindingStabilizer()
        let sessionID = AnalysisSessionID()
        stabilizer.beginSession(sessionID)
        let weak = candidate(sessionID: sessionID, frame: 1, time: 1, quality: .low)
        XCTAssertTrue(ingest(stabilizer, weak).findings.isEmpty)
        XCTAssertTrue(stabilizer.expire(at: 20).isEmpty)
    }

    func testRepeatedEvidenceUpdatesOneStableFindingWithTheSameIdentity() throws {
        let stabilizer = AccessibilityFindingStabilizer()
        let sessionID = AnalysisSessionID()
        stabilizer.beginSession(sessionID)
        for frame in 1...3 {
            _ = ingest(stabilizer, candidate(sessionID: sessionID, frame: UInt64(frame), time: Double(frame)))
        }
        let first = try XCTUnwrap(stabilizer.findings(for: sessionID).first)
        _ = ingest(stabilizer, candidate(sessionID: sessionID, frame: 4, time: 4))
        let updated = try XCTUnwrap(stabilizer.findings(for: sessionID).first)
        XCTAssertEqual(stabilizer.findings(for: sessionID).count, 1)
        XCTAssertEqual(updated.id, first.id)
        XCTAssertEqual(updated.supportingObservationCount, 4)
    }

    func testDistinctRegionsAreNotMergedEvenWhenTextAndCategoryMatch() {
        let stabilizer = AccessibilityFindingStabilizer()
        let sessionID = AnalysisSessionID()
        stabilizer.beginSession(sessionID)
        for frame in 1...3 {
            _ = ingest(stabilizer, candidate(sessionID: sessionID, frame: UInt64(frame), time: Double(frame), region: region(0.1, 0.1, 0.2, 0.2)))
            _ = ingest(stabilizer, candidate(sessionID: sessionID, frame: UInt64(frame), time: Double(frame), region: region(0.6, 0.6, 0.2, 0.2)))
        }
        XCTAssertEqual(stabilizer.findings(for: sessionID).count, 2)
    }

    func testFindingsExpireAfterConfiguredAbsenceInterval() {
        let stabilizer = AccessibilityFindingStabilizer(policy: FindingStabilizationPolicy(expiryInterval: 4))
        let sessionID = AnalysisSessionID()
        stabilizer.beginSession(sessionID)
        for frame in 1...3 {
            _ = ingest(stabilizer, candidate(sessionID: sessionID, frame: UInt64(frame), time: Double(frame)))
        }
        XCTAssertEqual(stabilizer.expire(at: 7).count, 1)
        XCTAssertTrue(stabilizer.expire(at: 7.1).isEmpty)
    }

    func testSessionEndAndLateEvidenceCannotLeakIntoNewSession() {
        let stabilizer = AccessibilityFindingStabilizer()
        let firstSession = AnalysisSessionID()
        stabilizer.beginSession(firstSession)
        for frame in 1...3 {
            _ = ingest(stabilizer, candidate(sessionID: firstSession, frame: UInt64(frame), time: Double(frame)))
        }
        XCTAssertEqual(stabilizer.findings(for: firstSession).count, 1)
        stabilizer.endSession(firstSession)

        let secondSession = AnalysisSessionID()
        stabilizer.beginSession(secondSession)
        XCTAssertTrue(ingest(stabilizer, candidate(sessionID: firstSession, frame: 4, time: 4)).findings.isEmpty)
        XCTAssertTrue(stabilizer.findings(for: secondSession).isEmpty)
    }

    func testGapsFromTemporaryAnalyzerFailureDoNotResetGoodEvidence() {
        let stabilizer = AccessibilityFindingStabilizer(policy: FindingStabilizationPolicy(expiryInterval: 8))
        let sessionID = AnalysisSessionID()
        stabilizer.beginSession(sessionID)
        _ = ingest(stabilizer, candidate(sessionID: sessionID, frame: 1, time: 1))
        _ = stabilizer.ingest([], sessionID: sessionID, currentTime: 2) // temporary analyzer failure/no output
        _ = ingest(stabilizer, candidate(sessionID: sessionID, frame: 3, time: 3))
        let result = ingest(stabilizer, candidate(sessionID: sessionID, frame: 4, time: 4))
        XCTAssertEqual(result.findings.count, 1)
    }

    func testBoundsLimitTracksEvidenceAndActiveFindings() {
        let policy = FindingStabilizationPolicy(
            maximumCandidateTracks: 2,
            maximumEvidenceEntriesPerTrack: 2,
            maximumActiveFindings: 1,
            requiredSupportingObservations: 2,
            strongEvidenceSupportingObservations: 2
        )
        let stabilizer = AccessibilityFindingStabilizer(policy: policy)
        let sessionID = AnalysisSessionID()
        stabilizer.beginSession(sessionID)

        for index in 0..<8 {
            let label = "EXIT \(index)"
            _ = ingest(stabilizer, candidate(sessionID: sessionID, frame: UInt64(index * 2 + 1), time: Double(index * 2 + 1), text: label))
            _ = ingest(stabilizer, candidate(sessionID: sessionID, frame: UInt64(index * 2 + 2), time: Double(index * 2 + 2), text: label))
        }

        let snapshot = stabilizer.snapshot()
        XCTAssertLessThanOrEqual(snapshot.candidateTrackCount, policy.maximumCandidateTracks)
        XCTAssertLessThanOrEqual(snapshot.maximumEvidenceEntriesInTrack, policy.maximumEvidenceEntriesPerTrack)
        XCTAssertLessThanOrEqual(snapshot.activeFindingCount, policy.maximumActiveFindings)
    }

    func testRepeatedCandidateDoesNotCreateAnUnboundedFindingList() {
        let stabilizer = AccessibilityFindingStabilizer()
        let sessionID = AnalysisSessionID()
        stabilizer.beginSession(sessionID)
        for frame in 1...20 {
            _ = ingest(stabilizer, candidate(sessionID: sessionID, frame: UInt64(frame), time: Double(frame) * 0.2))
        }
        XCTAssertEqual(stabilizer.findings(for: sessionID).count, 1)
        XCTAssertLessThanOrEqual(stabilizer.snapshot().maximumEvidenceEntriesInTrack, 6)
    }

    func testEndSessionClearsFindingsAndRejectsCancellationLikeLateOutput() {
        let stabilizer = AccessibilityFindingStabilizer()
        let sessionID = AnalysisSessionID()
        stabilizer.beginSession(sessionID)
        for frame in 1...3 {
            _ = ingest(stabilizer, candidate(sessionID: sessionID, frame: UInt64(frame), time: Double(frame)))
        }
        stabilizer.endSession(sessionID)
        XCTAssertTrue(stabilizer.findings(for: sessionID).isEmpty)
        XCTAssertTrue(ingest(stabilizer, candidate(sessionID: sessionID, frame: 4, time: 4)).findings.isEmpty)
    }

    private func ingest(
        _ stabilizer: AccessibilityFindingStabilizer,
        _ candidate: FindingCandidate
    ) -> FindingStabilizationResult {
        stabilizer.ingest([candidate], sessionID: candidate.sessionID, currentTime: candidate.presentationTimeSeconds)
    }

    private func candidate(
        sessionID: AnalysisSessionID,
        frame: UInt64,
        time: TimeInterval,
        text: String = "EXIT",
        region: NormalizedRegion = NormalizedRegion(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
        quality: ContrastEvidenceQuality = .usable
    ) -> FindingCandidate {
        FindingCandidate(
            sessionID: sessionID,
            sourceObservationIDs: [UUID(), UUID()],
            frameSequence: AnalysisFrameSequence(rawValue: frame),
            region: region,
            evidenceKind: "visual-contrast.potential-low",
            category: .potentialLowContrastText,
            recognizedText: text,
            rawFrameworkConfidence: 0.9,
            presentationTimeSeconds: time,
            sourceAnalyzerID: AnalyzerIdentifier(rawValue: "vision.visual-contrast.v1"),
            sourceAnalyzerIDs: [
                AnalyzerIdentifier(rawValue: "vision.text.v1"),
                AnalyzerIdentifier(rawValue: "vision.visual-contrast.v1")
            ],
            estimatedContrastRatio: ContrastRatio(lighterLuminance: 0.2, darkerLuminance: 0.02),
            contrastEvidenceQuality: quality
        )
    }

    private func region(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> NormalizedRegion {
        NormalizedRegion(x: x, y: y, width: width, height: height)
    }
}
