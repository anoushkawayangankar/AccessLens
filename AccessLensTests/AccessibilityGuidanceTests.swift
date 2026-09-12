import XCTest
@testable import AccessLens

final class AccessibilityGuidanceTests: XCTestCase {
    private let provider = DeterministicAccessibilityGuidanceProvider()

    func testEverySupportedCategoryHasStructuredActionableGuidance() {
        let category = AccessibilityFindingCategory.potentialLowContrastText
            let finding = fixture(category: category)
            let guidance = provider.guidance(for: finding)
            XCTAssertEqual(guidance.ruleID, "text.potential-low-contrast")
            XCTAssertEqual(guidance.ruleVersion, 1)
            XCTAssertEqual(guidance.observation.recognizedText, finding.relevantText)
            XCTAssertEqual(guidance.observation.estimatedContrastRatio, finding.estimatedContrastRatio)
            XCTAssertFalse(guidance.observation.summary.isEmpty)
            XCTAssertTrue(guidance.interpretation.contains("may"))
            XCTAssertTrue(guidance.whyItMatters.contains("low vision"))
            XCTAssertEqual(guidance.whatToCheck.map(\.id), [.viewingPosition, .representativeLighting, .confirmText])
            XCTAssertEqual(guidance.possibleImprovements.map(\.id), [.increaseContrast, .simplifyBackground, .recheckLighting])
            XCTAssertTrue(guidance.whatToCheck.allSatisfy { !$0.text.isEmpty })
            XCTAssertTrue(guidance.possibleImprovements.allSatisfy { !$0.text.isEmpty })
            XCTAssertTrue(guidance.limitations.contains("camera"))
            XCTAssertTrue(guidance.limitations.contains("not a direct measurement"))
    }

    func testRepeatedInputIsDeterministicAndDoesNotMutateEvidence() {
        let finding = fixture()
        let expected = provider.guidance(for: finding)
        for _ in 0..<20 { XCTAssertEqual(provider.guidance(for: finding), expected) }
        XCTAssertEqual(finding.relevantText, "EXIT")
        XCTAssertEqual(finding.evidenceSummary, "Original finalized evidence")
    }

    func testPassageGuidanceRequiresDirectMeasurementAndPreservesUncertainty() {
        let finding = ScanPersistenceFixtures.passageFinding()
        let guidance = provider.guidance(for: finding)
        XCTAssertEqual(guidance.ruleID, "passage.potential-narrow")
        XCTAssertEqual(guidance.ruleVersion, 1)
        XCTAssertEqual(guidance.observation.passageEvidence, finding.passageEvidence)
        XCTAssertNil(guidance.observation.recognizedText)
        XCTAssertNil(guidance.observation.estimatedContrastRatio)
        XCTAssertTrue(guidance.observation.summary.contains("estimated"))
        XCTAssertTrue(guidance.whatToCheck.contains { $0.id == .measureClearOpening })
        XCTAssertTrue(guidance.whatToCheck.contains { $0.id == .inspectNarrowestPoint })
        XCTAssertTrue(guidance.possibleImprovements.contains { $0.id == .perpendicularRecapture })
        XCTAssertTrue(guidance.limitations.contains("LiDAR"))
        XCTAssertTrue(guidance.limitations.contains("not a survey measurement"))
        XCTAssertFalse(guidance.interpretation.localizedCaseInsensitiveContains("compliant"))
    }

    func testPassageGuidanceIsDeterministicForHistoricalRoundTrip() async throws {
        let repository = SwiftDataCompletedScanRepository(inMemory: true)
        let scan = ScanPersistenceFixtures.passageScan()
        try await repository.save(scan)
        let fetched = try await repository.fetch(id: scan.id)
        let restored = try XCTUnwrap(fetched)
        XCTAssertEqual(
            provider.guidance(for: try XCTUnwrap(restored.findings.first)),
            provider.guidance(for: try XCTUnwrap(scan.findings.first))
        )
    }

    func testTextIsContextAndDoesNotChangeAdviceOrInferSignRequirements() {
        let exit = provider.guidance(for: fixture(text: "EXIT"))
        let entrance = provider.guidance(for: fixture(text: "ACCESSIBLE ENTRANCE"))
        XCTAssertEqual(exit.whatToCheck, entrance.whatToCheck)
        XCTAssertEqual(exit.possibleImprovements, entrance.possibleImprovements)
        XCTAssertEqual(exit.whyItMatters, entrance.whyItMatters)
        XCTAssertNotEqual(exit.observation.recognizedText, entrance.observation.recognizedText)
        XCTAssertTrue(exit.possibleImprovements.first { $0.id == .simplifyBackground }?.text.hasPrefix("If") == true)
    }

    func testMissingEvidenceIsNotInvented() {
        for text: String? in [nil, " \n "] {
            let guidance = provider.guidance(for: fixture(text: text, ratio: nil))
            XCTAssertNil(guidance.observation.recognizedText)
            XCTAssertNil(guidance.observation.estimatedContrastRatio)
            XCTAssertTrue(guidance.observation.summary.contains("not available"))
            XCTAssertFalse(guidance.whatToCheck.contains { $0.id == .confirmText })
        }
    }

    @MainActor
    func testStrengthRemainsDiscreteAndLimitedEvidenceRequiresVerification() {
        let commonActions = provider.guidance(for: fixture()).possibleImprovements
        for strength in [FindingEvidenceStrength.limited, .moderate, .strong] {
            let guidance = provider.guidance(for: fixture(strength: strength))
            XCTAssertEqual(guidance.evidenceStrength, strength)
            XCTAssertEqual(guidance.possibleImprovements, commonActions)
            XCTAssertTrue(guidance.verificationNote.contains("Verify"))
            XCTAssertFalse(strength.guidanceLabel.contains("%"))
            if strength == .limited { XCTAssertTrue(guidance.verificationNote.contains("limited")) }
        }
    }

    func testUnknownStoredCategoryRemainsRejectedAndFallbackMakesNoRecommendation() throws {
        let stored = try ScanStorageMapper.stored(ScanPersistenceFixtures.scan())
        try XCTUnwrap(stored.findings.first).category = "future-unrecognized-category"
        XCTAssertThrowsError(try ScanStorageMapper.domain(stored)) {
            XCTAssertEqual($0 as? ScanRepositoryError, .unsupportedRecord)
        }
        let fallback = provider.fallbackGuidance()
        XCTAssertEqual(fallback.ruleID, "general.review")
        XCTAssertEqual(fallback.whatToCheck.map(\.id), [.reviewDirectly])
        XCTAssertTrue(fallback.possibleImprovements.isEmpty)
        XCTAssertNil(fallback.evidenceStrength)
        XCTAssertNil(fallback.observation.recognizedText)
    }

    func testHistoricalEvidenceProducesSameGuidanceWithoutChangingStorage() async throws {
        let repository = SwiftDataCompletedScanRepository(inMemory: true)
        let original = ScanPersistenceFixtures.scan(findingCount: 2)
        try await repository.save(original)
        let fetched = try await repository.fetch(id: original.id)
        let restored = try XCTUnwrap(fetched)
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.findings.map(provider.guidance), original.findings.map(provider.guidance))
        let record = try ScanStorageMapper.stored(restored)
        XCTAssertEqual(record.recordVersion, 2)
        XCTAssertEqual(try ScanStorageMapper.domain(record), original)
    }

    @MainActor
    func testLiveAndHistoricalDetailBackRetainsCorrectReviewAndFinding() throws {
        let navigator = AppNavigator()
        let scan = ScanPersistenceFixtures.scan(findingCount: 2)
        for parent in [[AppRoute.scanReview(scan)], [.savedScans, .scanDetail(id: scan.id)]] {
            navigator.path = parent
            for finding in scan.findings {
                navigator.navigate(to: .findingDetail(finding))
                XCTAssertEqual(navigator.path.last, .findingDetail(finding))
                XCTAssertEqual(provider.guidance(for: finding).observation.recognizedText, finding.relevantText)
                navigator.goBack()
                XCTAssertEqual(navigator.path, parent)
            }
        }
        XCTAssertTrue(ScanReviewViewModel(completedScan: ScanPersistenceFixtures.scan(findingCount: 0)).isZeroFindingScan)
    }

    private func fixture(category: AccessibilityFindingCategory = .potentialLowContrastText,
                         text: String? = "EXIT", strength: FindingEvidenceStrength = .moderate,
                         ratio: ContrastRatio? = ContrastRatio(lighterLuminance: 0.09, darkerLuminance: 0.02)) -> AccessibilityFinding {
        AccessibilityFinding(category: category, title: "Potential low contrast",
            explanation: "Text may be difficult to distinguish.", evidenceSummary: "Original finalized evidence",
            evidenceStrength: strength, region: nil, firstObservedTime: 1, lastObservedTime: 3,
            supportingFrameRange: FindingFrameRange(first: .init(rawValue: 1), last: .init(rawValue: 3)),
            supportingObservationCount: 3, sessionID: AnalysisSessionID(), sourceAnalyzerIDs: [],
            relevantText: text, estimatedContrastRatio: ratio)
    }
}
