import Foundation
import OSLog

/// Centralized, testable bounds and promotion rules for live findings. The
/// default policy requires repeated, spatially and text-consistent usable
/// contrast evidence inside a short window; it is intentionally not a simple
/// global "frames equals finding" rule.
nonisolated struct FindingStabilizationPolicy: Equatable, Sendable {
    let maximumCandidateTracks: Int
    let maximumEvidenceEntriesPerTrack: Int
    let maximumActiveFindings: Int
    let evidenceWindow: TimeInterval
    let expiryInterval: TimeInterval
    let minimumRegionIntersectionOverUnion: Double
    let requiredSupportingObservations: Int
    let strongEvidenceSupportingObservations: Int
    let passageMeasurementOutlierTolerance: Double

    init(
        maximumCandidateTracks: Int = 12,
        maximumEvidenceEntriesPerTrack: Int = 6,
        maximumActiveFindings: Int = 6,
        evidenceWindow: TimeInterval = 5,
        expiryInterval: TimeInterval = 6,
        minimumRegionIntersectionOverUnion: Double = 0.5,
        requiredSupportingObservations: Int = 3,
        strongEvidenceSupportingObservations: Int = 5,
        passageMeasurementOutlierTolerance: Double = 0.25
    ) {
        self.maximumCandidateTracks = maximumCandidateTracks
        self.maximumEvidenceEntriesPerTrack = maximumEvidenceEntriesPerTrack
        self.maximumActiveFindings = maximumActiveFindings
        self.evidenceWindow = evidenceWindow
        self.expiryInterval = expiryInterval
        self.minimumRegionIntersectionOverUnion = minimumRegionIntersectionOverUnion
        self.requiredSupportingObservations = requiredSupportingObservations
        self.strongEvidenceSupportingObservations = strongEvidenceSupportingObservations
        self.passageMeasurementOutlierTolerance = passageMeasurementOutlierTolerance
    }
}

/// Lock-isolated session evidence fusion. It never receives camera or Vision
/// framework types, retains no image/frame payload, and publishes only compact
/// stable findings. Its synchronous work is bounded and remains off MainActor.
nonisolated final class AccessibilityFindingStabilizer: @unchecked Sendable {
    private struct Evidence: Sendable {
        let frameSequence: AnalysisFrameSequence
        let timestamp: TimeInterval
        let ratio: ContrastRatio
        let sourceAnalyzerIDs: [AnalyzerIdentifier]
    }

    private struct Track: Sendable {
        let id: UUID
        let sessionID: AnalysisSessionID
        let category: AccessibilityFindingCategory
        let normalizedText: String
        let displayText: String
        var region: NormalizedRegion
        var firstObservedTime: TimeInterval
        var lastObservedTime: TimeInterval
        var evidence: [Evidence]
        var findingID: UUID?
    }

    private struct PassageEvidence: Sendable {
        let frameSequence: AnalysisFrameSequence
        let timestamp: TimeInterval
        let width: PassageWidth
        let method: PassageMeasurementMethod
        let quality: PassageMeasurementQuality
        let sourceAnalyzerIDs: [AnalyzerIdentifier]
    }

    private struct PassageTrack: Sendable {
        let id: UUID
        let sessionID: AnalysisSessionID
        let surfaceID: UUID
        var region: NormalizedRegion?
        var firstObservedTime: TimeInterval
        var lastObservedTime: TimeInterval
        var evidence: [PassageEvidence]
        var findingID: UUID?
    }

    private let policy: FindingStabilizationPolicy
    private let lock = NSLock()
    private var activeSessionID: AnalysisSessionID?
    private var tracks: [Track] = []
    private var passageTracks: [PassageTrack] = []
    private var activeFindings: [AccessibilityFinding] = []

    init(policy: FindingStabilizationPolicy = FindingStabilizationPolicy()) {
        self.policy = policy
    }

    func beginSession(_ sessionID: AnalysisSessionID) {
        lock.lock()
        defer { lock.unlock() }
        activeSessionID = sessionID
        tracks.removeAll()
        passageTracks.removeAll()
        activeFindings.removeAll()
    }

    func endSession(_ sessionID: AnalysisSessionID) {
        lock.lock()
        defer { lock.unlock() }
        guard activeSessionID == sessionID else { return }
        activeSessionID = nil
        tracks.removeAll()
        passageTracks.removeAll()
        activeFindings.removeAll()
    }

    func ingest(
        _ candidates: [FindingCandidate],
        sessionID: AnalysisSessionID,
        currentTime: TimeInterval?
    ) -> FindingStabilizationResult {
        lock.lock()
        defer { lock.unlock() }
        guard activeSessionID == sessionID else {
            return FindingStabilizationResult(findings: [], newlyPromotedFindingIDs: [])
        }

        let latestTime = currentTime ?? candidates.map(evidenceTime(for:)).max()
        if let latestTime {
            _ = expireUnlocked(at: latestTime)
        }

        var newlyPromotedFindingIDs: Set<UUID> = []
        for candidate in candidates where candidate.sessionID == sessionID {
            if let passageInput = qualifyingPassageInput(from: candidate) {
                let evidence = PassageEvidence(
                    frameSequence: candidate.frameSequence,
                    timestamp: evidenceTime(for: candidate),
                    width: passageInput.width,
                    method: passageInput.evidence.measurementMethod,
                    quality: passageInput.evidence.measurementQuality,
                    sourceAnalyzerIDs: candidate.sourceAnalyzerIDs
                )
                if let index = passageTracks.firstIndex(where: { associates($0, with: candidate, input: passageInput) }) {
                    append(evidence, candidate: candidate, toPassageTrackAt: index)
                    if let findingID = promoteOrUpdate(passageTrackAt: index) {
                        newlyPromotedFindingIDs.insert(findingID)
                    }
                } else {
                    addPassageTrack(candidate: candidate, input: passageInput, evidence: evidence)
                    if let findingID = promoteOrUpdate(passageTrackAt: passageTracks.index(before: passageTracks.endIndex)) {
                        newlyPromotedFindingIDs.insert(findingID)
                    }
                }
                continue
            }

            guard let input = qualifyingInput(from: candidate) else { continue }
            let evidence = Evidence(
                frameSequence: candidate.frameSequence,
                timestamp: evidenceTime(for: candidate),
                ratio: input.ratio,
                sourceAnalyzerIDs: candidate.sourceAnalyzerIDs
            )

            if let trackIndex = tracks.firstIndex(where: { associates($0, with: candidate, input: input) }) {
                append(evidence, candidate: candidate, toTrackAt: trackIndex)
                if let findingID = promoteOrUpdate(trackAt: trackIndex) {
                    newlyPromotedFindingIDs.insert(findingID)
                }
            } else {
                addTrack(candidate: candidate, input: input, evidence: evidence)
                let trackIndex = tracks.index(before: tracks.endIndex)
                if let findingID = promoteOrUpdate(trackAt: trackIndex) {
                    newlyPromotedFindingIDs.insert(findingID)
                }
            }
        }

        enforceBounds()
        return FindingStabilizationResult(
            findings: activeFindings,
            newlyPromotedFindingIDs: newlyPromotedFindingIDs.intersection(Set(activeFindings.map(\.id)))
        )
    }

    func expire(at currentTime: TimeInterval) -> [AccessibilityFinding] {
        lock.lock()
        defer { lock.unlock() }
        return expireUnlocked(at: currentTime)
    }

    private func expireUnlocked(at currentTime: TimeInterval) -> [AccessibilityFinding] {
        let expiredTrackIDs = Set(tracks.compactMap { track in
            currentTime - track.lastObservedTime > policy.expiryInterval ? track.id : nil
        })
        let expiredPassageTrackIDs = Set(passageTracks.compactMap { track in
            currentTime - track.lastObservedTime > policy.expiryInterval ? track.id : nil
        })
        guard !expiredTrackIDs.isEmpty || !expiredPassageTrackIDs.isEmpty else { return activeFindings }

        let expiredFindingIDs = Set(
            tracks.compactMap { expiredTrackIDs.contains($0.id) ? $0.findingID : nil }
        )
        let expiredPassageFindingIDs = Set(
            passageTracks.compactMap { expiredPassageTrackIDs.contains($0.id) ? $0.findingID : nil }
        )
        tracks.removeAll { expiredTrackIDs.contains($0.id) }
        passageTracks.removeAll { expiredPassageTrackIDs.contains($0.id) }
        activeFindings.removeAll { expiredFindingIDs.contains($0.id) || expiredPassageFindingIDs.contains($0.id) }
        AppLog.analysis.debug("Expired stale accessibility findings")
        return activeFindings
    }

    func findings(for sessionID: AnalysisSessionID) -> [AccessibilityFinding] {
        lock.lock()
        defer { lock.unlock() }
        return activeSessionID == sessionID ? activeFindings : []
    }

    func snapshot() -> FindingStabilizerSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return FindingStabilizerSnapshot(
            activeSessionID: activeSessionID,
            candidateTrackCount: tracks.count + passageTracks.count,
            maximumEvidenceEntriesInTrack: max(
                tracks.map(\.evidence.count).max() ?? 0,
                passageTracks.map(\.evidence.count).max() ?? 0
            ),
            activeFindingCount: activeFindings.count
        )
    }

    private func qualifyingInput(from candidate: FindingCandidate) -> (text: String, normalizedText: String, region: NormalizedRegion, ratio: ContrastRatio)? {
        guard candidate.category == .potentialLowContrastText,
              candidate.contrastEvidenceQuality == .usable,
              let ratio = candidate.estimatedContrastRatio,
              let text = candidate.recognizedText,
              let normalizedText = FindingTextAssociation.normalizedIdentity(text),
              let region = candidate.region,
              NormalizedRegionAssociation.isValid(region) else {
            return nil
        }
        return (text, normalizedText, region, ratio)
    }

    private func qualifyingPassageInput(
        from candidate: FindingCandidate
    ) -> (surfaceID: UUID, width: PassageWidth, evidence: PassageFindingEvidence)? {
        guard candidate.category == .potentialNarrowPassage,
              let surfaceID = candidate.passageSurfaceID,
              let evidence = candidate.passageEvidence,
              evidence.measurementMethod == .roomPlanLiDAR,
              evidence.measurementQuality == .usable,
              let width = evidence.estimatedWidth else { return nil }
        return (surfaceID, width, evidence)
    }

    private func associates(
        _ track: Track,
        with candidate: FindingCandidate,
        input: (text: String, normalizedText: String, region: NormalizedRegion, ratio: ContrastRatio)
    ) -> Bool {
        guard category(for: candidate) == track.category,
              input.normalizedText == track.normalizedText,
              evidenceTime(for: candidate) - track.lastObservedTime <= policy.evidenceWindow else {
            return false
        }
        return NormalizedRegionAssociation.intersectionOverUnion(track.region, input.region)
            >= policy.minimumRegionIntersectionOverUnion
    }

    private func addTrack(
        candidate: FindingCandidate,
        input: (text: String, normalizedText: String, region: NormalizedRegion, ratio: ContrastRatio),
        evidence: Evidence
    ) {
        tracks.append(Track(
            id: UUID(),
            sessionID: candidate.sessionID,
            category: category(for: candidate),
            normalizedText: input.normalizedText,
            displayText: input.text,
            region: input.region,
            firstObservedTime: evidence.timestamp,
            lastObservedTime: evidence.timestamp,
            evidence: [evidence],
            findingID: nil
        ))
        AppLog.analysis.debug("Created accessibility candidate track")
    }

    private func associates(
        _ track: PassageTrack,
        with candidate: FindingCandidate,
        input: (surfaceID: UUID, width: PassageWidth, evidence: PassageFindingEvidence)
    ) -> Bool {
        guard evidenceTime(for: candidate) - track.lastObservedTime <= policy.evidenceWindow else { return false }
        if track.surfaceID == input.surfaceID { return true }
        guard let trackRegion = track.region, let candidateRegion = candidate.region else { return false }
        return NormalizedRegionAssociation.intersectionOverUnion(trackRegion, candidateRegion)
            >= policy.minimumRegionIntersectionOverUnion
    }

    private func addPassageTrack(
        candidate: FindingCandidate,
        input: (surfaceID: UUID, width: PassageWidth, evidence: PassageFindingEvidence),
        evidence: PassageEvidence
    ) {
        passageTracks.append(PassageTrack(
            id: UUID(), sessionID: candidate.sessionID, surfaceID: input.surfaceID,
            region: candidate.region, firstObservedTime: evidence.timestamp,
            lastObservedTime: evidence.timestamp, evidence: [evidence], findingID: nil
        ))
        AppLog.analysis.debug("Created passage candidate track")
    }

    private func append(_ evidence: Evidence, candidate: FindingCandidate, toTrackAt index: Int) {
        tracks[index].region = candidate.region ?? tracks[index].region
        tracks[index].lastObservedTime = evidence.timestamp
        tracks[index].evidence.append(evidence)
        if tracks[index].evidence.count > policy.maximumEvidenceEntriesPerTrack {
            tracks[index].evidence.removeFirst(tracks[index].evidence.count - policy.maximumEvidenceEntriesPerTrack)
        }
    }

    private func append(
        _ evidence: PassageEvidence,
        candidate: FindingCandidate,
        toPassageTrackAt index: Int
    ) {
        passageTracks[index].region = candidate.region ?? passageTracks[index].region
        passageTracks[index].lastObservedTime = evidence.timestamp
        passageTracks[index].evidence.append(evidence)
        if passageTracks[index].evidence.count > policy.maximumEvidenceEntriesPerTrack {
            passageTracks[index].evidence.removeFirst(
                passageTracks[index].evidence.count - policy.maximumEvidenceEntriesPerTrack
            )
        }
    }

    /// Returns an ID only when a new active finding is minted. Existing
    /// findings keep their identity and are updated in place.
    private func promoteOrUpdate(trackAt index: Int) -> UUID? {
        let track = tracks[index]
        guard let first = track.evidence.first,
              let last = track.evidence.last,
              track.evidence.count >= policy.requiredSupportingObservations,
              last.timestamp - first.timestamp <= policy.evidenceWindow else {
            return nil
        }

        let finding = makeFinding(from: track)
        if let findingID = track.findingID,
           let findingIndex = activeFindings.firstIndex(where: { $0.id == findingID }) {
            activeFindings[findingIndex] = finding
            AppLog.analysis.debug("Updated stable accessibility finding")
            return nil
        }

        tracks[index].findingID = finding.id
        activeFindings.append(finding)
        AppLog.analysis.info("Promoted accessibility finding")
        return finding.id
    }

    private func makeFinding(from track: Track) -> AccessibilityFinding {
        let sources = Array(Set(track.evidence.flatMap(\.sourceAnalyzerIDs)))
            .sorted { $0.rawValue < $1.rawValue }
        let latestRatio = track.evidence.last?.ratio
        let strength: FindingEvidenceStrength = track.evidence.count >= policy.strongEvidenceSupportingObservations
            ? .strong
            : .moderate
        let evidenceCount = track.evidence.count
        let summary = "Text \u{201C}\(track.displayText)\u{201D} was observed in a similar area across \(evidenceCount) analyses. Estimated contrast remained low with usable camera evidence."
        return AccessibilityFinding(
            id: track.findingID ?? UUID(),
            category: track.category,
            title: "Potential low contrast",
            explanation: "Text in this area may be difficult to distinguish from its background.",
            evidenceSummary: summary,
            evidenceStrength: strength,
            region: track.region,
            firstObservedTime: track.firstObservedTime,
            lastObservedTime: track.lastObservedTime,
            supportingFrameRange: FindingFrameRange(
                first: track.evidence.first?.frameSequence ?? AnalysisFrameSequence(rawValue: 0),
                last: track.evidence.last?.frameSequence ?? AnalysisFrameSequence(rawValue: 0)
            ),
            supportingObservationCount: evidenceCount,
            sessionID: track.sessionID,
            sourceAnalyzerIDs: sources,
            relevantText: track.displayText,
            estimatedContrastRatio: latestRatio,
            passageEvidence: nil
        )
    }

    private func promoteOrUpdate(passageTrackAt index: Int) -> UUID? {
        let track = passageTracks[index]
        let widths = track.evidence.map(\.width)
        let inliers = PassageMeasurementAggregator.inliers(
            widths,
            relativeTolerance: policy.passageMeasurementOutlierTolerance
        )
        guard let first = track.evidence.first,
              let last = track.evidence.last,
              inliers.count >= policy.requiredSupportingObservations,
              last.timestamp - first.timestamp <= policy.evidenceWindow,
              let medianWidth = PassageMeasurementAggregator.medianRejectingOutliers(
                inliers,
                relativeTolerance: policy.passageMeasurementOutlierTolerance
              ) else { return nil }

        let finding = makePassageFinding(from: track, inlierCount: inliers.count, width: medianWidth)
        if let findingID = track.findingID,
           let findingIndex = activeFindings.firstIndex(where: { $0.id == findingID }) {
            activeFindings[findingIndex] = finding
            AppLog.analysis.debug("Updated stable passage finding")
            return nil
        }
        passageTracks[index].findingID = finding.id
        activeFindings.append(finding)
        AppLog.analysis.info("Promoted passage finding")
        return finding.id
    }

    private func makePassageFinding(
        from track: PassageTrack,
        inlierCount: Int,
        width: PassageWidth
    ) -> AccessibilityFinding {
        let sources = Array(Set(track.evidence.flatMap(\.sourceAnalyzerIDs)))
            .sorted { $0.rawValue < $1.rawValue }
        let strength: FindingEvidenceStrength = inlierCount >= policy.strongEvidenceSupportingObservations
            ? .strong : .moderate
        let centimeters = Int((width.meters * 100).rounded())
        return AccessibilityFinding(
            id: track.findingID ?? UUID(), category: .potentialNarrowPassage,
            title: "Potential narrow passage",
            explanation: "The visible opening was repeatedly estimated as relatively narrow. Verify the clear opening directly before making accessibility decisions.",
            evidenceSummary: "A LiDAR-supported room scan repeatedly identified a similar door or opening. The median estimated opening width was about \(centimeters) centimeters after rejecting inconsistent measurements.",
            evidenceStrength: strength, region: track.region,
            firstObservedTime: track.firstObservedTime, lastObservedTime: track.lastObservedTime,
            supportingFrameRange: FindingFrameRange(
                first: track.evidence.first?.frameSequence ?? AnalysisFrameSequence(rawValue: 0),
                last: track.evidence.last?.frameSequence ?? AnalysisFrameSequence(rawValue: 0)
            ),
            supportingObservationCount: inlierCount, sessionID: track.sessionID,
            sourceAnalyzerIDs: sources, relevantText: nil, estimatedContrastRatio: nil,
            passageEvidence: PassageFindingEvidence(
                estimatedWidth: width, measurementMethod: .roomPlanLiDAR, measurementQuality: .usable
            )
        )
    }

    private func enforceBounds() {
        let totalTracks = tracks.count + passageTracks.count
        if totalTracks > policy.maximumCandidateTracks {
            var excess = totalTracks - policy.maximumCandidateTracks
            while excess > 0 {
                let contrastTime = tracks.first?.lastObservedTime ?? .infinity
                let passageTime = passageTracks.first?.lastObservedTime ?? .infinity
                if contrastTime <= passageTime, let removed = tracks.first {
                    tracks.removeFirst()
                    if let id = removed.findingID { activeFindings.removeAll { $0.id == id } }
                } else if let removed = passageTracks.first {
                    passageTracks.removeFirst()
                    if let id = removed.findingID { activeFindings.removeAll { $0.id == id } }
                }
                excess -= 1
            }
        }
        if activeFindings.count > policy.maximumActiveFindings {
            let excess = activeFindings.count - policy.maximumActiveFindings
            let removedIDs = Set(activeFindings.prefix(excess).map(\.id))
            activeFindings.removeFirst(excess)
            for index in tracks.indices where tracks[index].findingID.map(removedIDs.contains) ?? false {
                tracks[index].findingID = nil
            }
            for index in passageTracks.indices where passageTracks[index].findingID.map(removedIDs.contains) ?? false {
                passageTracks[index].findingID = nil
            }
        }
    }

    private func category(for candidate: FindingCandidate) -> AccessibilityFindingCategory {
        // `qualifyingInput` has already limited candidates to current, real
        // contrast evidence; this mapping remains explicit for future growth.
        switch candidate.category {
        case .potentialLowContrastText:
            .potentialLowContrastText
        case .unclassified, .environmentalSignage, .potentialNarrowPassage:
            .potentialLowContrastText
        }
    }

    private func evidenceTime(for candidate: FindingCandidate) -> TimeInterval {
        candidate.presentationTimeSeconds ?? TimeInterval(candidate.frameSequence.rawValue)
    }
}

nonisolated struct FindingStabilizationResult: Equatable, Sendable {
    let findings: [AccessibilityFinding]
    let newlyPromotedFindingIDs: Set<UUID>
}

nonisolated struct FindingStabilizerSnapshot: Equatable, Sendable {
    let activeSessionID: AnalysisSessionID?
    let candidateTrackCount: Int
    let maximumEvidenceEntriesInTrack: Int
    let activeFindingCount: Int
}
