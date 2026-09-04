import Foundation

/// A bounded, scan-local presentation policy for repeated OCR of the same
/// sign. This is deliberately not the future finding stabilizer: it only
/// prevents a live camera feed from creating duplicate transient cards.
nonisolated struct TransientSignageDeduplicator: Sendable {
    private(set) var candidates: [FindingCandidate] = []

    let maximumCandidates: Int
    let retentionInterval: TimeInterval
    let minimumRegionOverlap: Double

    init(
        maximumCandidates: Int = 4,
        retentionInterval: TimeInterval = 8,
        minimumRegionOverlap: Double = 0.5
    ) {
        self.maximumCandidates = maximumCandidates
        self.retentionInterval = retentionInterval
        self.minimumRegionOverlap = minimumRegionOverlap
    }

    mutating func reset() {
        candidates.removeAll()
    }

    /// Returns only genuinely new, current-session candidates so callers can
    /// make a single controlled accessibility announcement for each one.
    mutating func ingest(
        _ incoming: [FindingCandidate],
        sessionID: AnalysisSessionID,
        currentTime: TimeInterval?
    ) -> [FindingCandidate] {
        guard !incoming.isEmpty else {
            expire(currentTime: currentTime)
            return []
        }

        expire(currentTime: currentTime)
        var additions: [FindingCandidate] = []

        for candidate in incoming where candidate.sessionID == sessionID && candidate.category == .environmentalSignage {
            if let index = candidates.firstIndex(where: { isDuplicate($0, candidate) }) {
                candidates[index] = candidate
            } else {
                candidates.append(candidate)
                additions.append(candidate)
            }
        }

        if candidates.count > maximumCandidates {
            candidates.removeFirst(candidates.count - maximumCandidates)
        }
        return additions.filter { addition in candidates.contains(where: { $0.id == addition.id }) }
    }

    private mutating func expire(currentTime: TimeInterval?) {
        guard let currentTime else { return }
        candidates.removeAll { candidate in
            guard let timestamp = candidate.presentationTimeSeconds else { return false }
            return currentTime - timestamp > retentionInterval
        }
    }

    private func isDuplicate(_ lhs: FindingCandidate, _ rhs: FindingCandidate) -> Bool {
        guard normalizedText(lhs.recognizedText) == normalizedText(rhs.recognizedText) else {
            return false
        }
        guard let lhsRegion = lhs.region, let rhsRegion = rhs.region else {
            return true
        }
        return intersectionOverUnion(lhsRegion, rhsRegion) >= minimumRegionOverlap
    }

    private func normalizedText(_ text: String?) -> String {
        (text ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func intersectionOverUnion(_ lhs: NormalizedRegion, _ rhs: NormalizedRegion) -> Double {
        let intersectionLeft = max(lhs.x, rhs.x)
        let intersectionTop = max(lhs.y, rhs.y)
        let intersectionRight = min(lhs.x + lhs.width, rhs.x + rhs.width)
        let intersectionBottom = min(lhs.y + lhs.height, rhs.y + rhs.height)
        let intersectionWidth = max(0, intersectionRight - intersectionLeft)
        let intersectionHeight = max(0, intersectionBottom - intersectionTop)
        let intersectionArea = intersectionWidth * intersectionHeight
        let union = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        return union > 0 ? intersectionArea / union : 0
    }
}
