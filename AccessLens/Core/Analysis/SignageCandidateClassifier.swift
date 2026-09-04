import Foundation

/// Small, localizable-in-the-future rule set for environmental sign wording.
/// A matching phrase creates only a transient signage *candidate*: it does not
/// claim that a barrier exists, assign severity, or determine compliance.
nonisolated struct SignageCandidateClassifier: Sendable {
    let minimumConfidence: Double
    let maximumCandidateCharacterCount: Int

    init(minimumConfidence: Double = 0.55, maximumCandidateCharacterCount: Int = 48) {
        self.minimumConfidence = minimumConfidence
        self.maximumCandidateCharacterCount = maximumCandidateCharacterCount
    }

    func classify(_ observation: RecognizedTextObservation) -> FindingCandidate? {
        guard observation.rawFrameworkConfidence >= minimumConfidence,
              observation.text.count <= maximumCandidateCharacterCount,
              let keyword = matchingKeyword(in: observation.text) else {
            return nil
        }

        return FindingCandidate(
            sessionID: observation.sessionID,
            sourceObservationIDs: [observation.id],
            frameSequence: observation.frameSequence,
            region: observation.region,
            evidenceKind: "signage.\(keyword.rawValue)",
            category: .environmentalSignage,
            recognizedText: observation.text,
            rawFrameworkConfidence: observation.rawFrameworkConfidence,
            presentationTimeSeconds: observation.presentationTimeSeconds,
            sourceAnalyzerID: observation.analyzerID
        )
    }

    private func matchingKeyword(in text: String) -> SignageKeyword? {
        let foldedText = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return SignageKeyword.allCases.first { keyword in
            keyword.matches(foldedText)
        }
    }
}

nonisolated enum SignageKeyword: String, CaseIterable, Sendable {
    case emergencyExit = "emergency-exit"
    case accessibleEntrance = "accessible-entrance"
    case exit
    case entrance
    case restroom
    case toilet
    case accessible
    case access
    case elevator
    case lift
    case stairs
    case emergency
    case push
    case pull
    case floor
    case room

    fileprivate func matches(_ text: String) -> Bool {
        let phrase: String
        switch self {
        case .emergencyExit:
            phrase = "EMERGENCY EXIT"
        case .accessibleEntrance:
            phrase = "ACCESSIBLE ENTRANCE"
        default:
            phrase = rawValue.uppercased()
        }

        let words = text.uppercased().split { !$0.isLetter && !$0.isNumber }
        let phraseWords = phrase.split(separator: " ")
        guard words.count >= phraseWords.count else { return false }

        return words.indices.contains { index in
            words[index...].starts(with: phraseWords)
        }
    }
}
