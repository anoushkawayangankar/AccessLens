import Foundation
import ImageIO

/// Opaque identity for one live analysis lifetime. A new Scan appearance or
/// foreground resume creates a new value so late work cannot cross sessions.
nonisolated struct AnalysisSessionID: Hashable, Sendable, Identifiable {
    let rawValue: UUID

    var id: UUID { rawValue }

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

nonisolated struct AnalysisFrameSequence: Hashable, Sendable, Comparable {
    let rawValue: UInt64

    static func < (lhs: AnalysisFrameSequence, rhs: AnalysisFrameSequence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

nonisolated struct AnalysisFrameDimensions: Equatable, Sendable {
    let width: Int
    let height: Int
}

/// Orientation normalized for future Vision request handlers. The mapping is
/// based on the video-output connection's rotation, not device timestamps.
nonisolated enum AnalysisImageOrientation: UInt32, Sendable, Equatable {
    case up = 1
    case upMirrored = 2
    case down = 3
    case downMirrored = 4
    case leftMirrored = 5
    case right = 6
    case rightMirrored = 7
    case left = 8

    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        CGImagePropertyOrientation(rawValue: rawValue) ?? .up
    }

    static func from(videoRotationAngle: Double, isMirrored: Bool) -> AnalysisImageOrientation? {
        let normalizedAngle = ((videoRotationAngle.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360)
        let roundedAngle = (normalizedAngle / 90).rounded() * 90

        switch (Int(roundedAngle) % 360, isMirrored) {
        case (0, false):
            return .up
        case (0, true):
            return .upMirrored
        case (90, false):
            return .right
        case (90, true):
            return .rightMirrored
        case (180, false):
            return .down
        case (180, true):
            return .downMirrored
        case (270, false):
            return .left
        case (270, true):
            return .leftMirrored
        default:
            return nil
        }
    }
}

/// Sendable metadata copied from a camera callback. It intentionally contains
/// no CMSampleBuffer, CVPixelBuffer, CIImage, or CGImage reference.
nonisolated struct AnalysisFrame: Equatable, Sendable {
    let sessionID: AnalysisSessionID
    let sequence: AnalysisFrameSequence
    let presentationTimeSeconds: Double?
    let orientation: AnalysisImageOrientation?
    let dimensions: AnalysisFrameDimensions?
}

nonisolated struct AnalysisContext: Sendable {
    let frame: AnalysisFrame
}

nonisolated struct AnalyzerIdentifier: Hashable, Sendable, RawRepresentable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

nonisolated struct NormalizedRegion: Equatable, Sendable, Hashable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

/// Framework-independent output. Future Vision adapters convert framework
/// observations here before domain or stabilization logic sees them.
nonisolated struct NormalizedObservation: Identifiable, Equatable, Sendable, Hashable {
    let id: UUID
    let analyzerID: AnalyzerIdentifier
    let sessionID: AnalysisSessionID
    let frameSequence: AnalysisFrameSequence
    let region: NormalizedRegion?
    let rawFrameworkConfidence: Double?
    let evidenceKind: String

    init(
        id: UUID = UUID(),
        analyzerID: AnalyzerIdentifier,
        sessionID: AnalysisSessionID,
        frameSequence: AnalysisFrameSequence,
        region: NormalizedRegion? = nil,
        rawFrameworkConfidence: Double? = nil,
        evidenceKind: String
    ) {
        self.id = id
        self.analyzerID = analyzerID
        self.sessionID = sessionID
        self.frameSequence = frameSequence
        self.region = region
        self.rawFrameworkConfidence = rawFrameworkConfidence
        self.evidenceKind = evidenceKind
    }
}

/// A transient pre-stabilization boundary. It is neither a persisted finding
/// nor a user-facing claim, and it intentionally has no severity field.
nonisolated struct FindingCandidate: Identifiable, Equatable, Sendable, Hashable {
    let id: UUID
    let sessionID: AnalysisSessionID
    let sourceObservationIDs: [UUID]
    let frameSequence: AnalysisFrameSequence
    let region: NormalizedRegion?
    let evidenceKind: String

    init(
        id: UUID = UUID(),
        sessionID: AnalysisSessionID,
        sourceObservationIDs: [UUID],
        frameSequence: AnalysisFrameSequence,
        region: NormalizedRegion? = nil,
        evidenceKind: String
    ) {
        self.id = id
        self.sessionID = sessionID
        self.sourceObservationIDs = sourceObservationIDs
        self.frameSequence = frameSequence
        self.region = region
        self.evidenceKind = evidenceKind
    }
}

nonisolated struct AnalyzerOutput: Equatable, Sendable {
    let observations: [NormalizedObservation]
    let candidates: [FindingCandidate]

    static let empty = AnalyzerOutput(observations: [], candidates: [])
}

nonisolated enum AnalysisError: Error, Equatable, Sendable {
    case invalidFrame
    case unsupportedOrientation
    case analyzerFailed(AnalyzerIdentifier)
    case cancelled
    case staleResult
}

nonisolated struct AnalysisFailure: Equatable, Sendable {
    let analyzerID: AnalyzerIdentifier
    let error: AnalysisError
}

nonisolated struct AnalysisPassResult: Equatable, Sendable {
    let sessionID: AnalysisSessionID
    let frameSequence: AnalysisFrameSequence
    let observations: [NormalizedObservation]
    let candidates: [FindingCandidate]
    let failures: [AnalysisFailure]
}
