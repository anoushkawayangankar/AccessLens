import Foundation

/// A small scan-local confirmation window for potentially low estimated
/// contrast. This is not the future cross-category finding stabilizer: it
/// simply requires two matching usable measurements before live presentation.
nonisolated struct TransientContrastCandidateStabilizer: Sendable {
    private struct Entry: Sendable {
        var candidate: FindingCandidate
        var confirmations: Int
        var isPresented: Bool
    }

    private var entries: [Entry] = []
    let maximumCandidates: Int
    let retentionInterval: TimeInterval
    let minimumRegionOverlap: Double
    let requiredConfirmations: Int

    init(
        maximumCandidates: Int = 3,
        retentionInterval: TimeInterval = 8,
        minimumRegionOverlap: Double = 0.5,
        requiredConfirmations: Int = 2
    ) {
        self.maximumCandidates = maximumCandidates
        self.retentionInterval = retentionInterval
        self.minimumRegionOverlap = minimumRegionOverlap
        self.requiredConfirmations = requiredConfirmations
    }

    var candidates: [FindingCandidate] {
        entries.filter(\.isPresented).map(\.candidate)
    }

    mutating func reset() {
        entries.removeAll()
    }

    mutating func ingest(
        _ incoming: [FindingCandidate],
        sessionID: AnalysisSessionID,
        currentTime: TimeInterval?
    ) -> [FindingCandidate] {
        expire(currentTime: currentTime)
        var additions: [FindingCandidate] = []

        for candidate in incoming where candidate.sessionID == sessionID && candidate.category == .potentialLowContrastText {
            if let index = entries.firstIndex(where: { isDuplicate($0.candidate, candidate) }) {
                entries[index].candidate = candidate
                entries[index].confirmations += 1
                if entries[index].confirmations >= requiredConfirmations, !entries[index].isPresented {
                    entries[index].isPresented = true
                    additions.append(candidate)
                }
            } else {
                let isPresented = requiredConfirmations <= 1
                entries.append(Entry(candidate: candidate, confirmations: 1, isPresented: isPresented))
                if isPresented { additions.append(candidate) }
            }
        }

        if entries.count > maximumCandidates {
            entries.removeFirst(entries.count - maximumCandidates)
        }
        return additions.filter { addition in candidates.contains(where: { $0.id == addition.id }) }
    }

    private mutating func expire(currentTime: TimeInterval?) {
        guard let currentTime else { return }
        entries.removeAll { entry in
            guard let timestamp = entry.candidate.presentationTimeSeconds else { return false }
            return currentTime - timestamp > retentionInterval
        }
    }

    private func isDuplicate(_ lhs: FindingCandidate, _ rhs: FindingCandidate) -> Bool {
        guard normalizedText(lhs.recognizedText) == normalizedText(rhs.recognizedText) else {
            return false
        }
        guard let lhsRegion = lhs.region, let rhsRegion = rhs.region else { return true }
        return intersectionOverUnion(lhsRegion, rhsRegion) >= minimumRegionOverlap
    }

    private func normalizedText(_ text: String?) -> String {
        (text ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func intersectionOverUnion(_ lhs: NormalizedRegion, _ rhs: NormalizedRegion) -> Double {
        let left = max(lhs.x, rhs.x)
        let top = max(lhs.y, rhs.y)
        let right = min(lhs.x + lhs.width, rhs.x + rhs.width)
        let bottom = min(lhs.y + lhs.height, rhs.y + rhs.height)
        let intersection = max(0, right - left) * max(0, bottom - top)
        let union = lhs.width * lhs.height + rhs.width * rhs.height - intersection
        return union > 0 ? intersection / union : 0
    }
}
