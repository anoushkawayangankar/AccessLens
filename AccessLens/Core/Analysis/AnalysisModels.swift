import Foundation
import ImageIO
@preconcurrency import AVFoundation

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

/// An opaque, bounded handoff of the frame currently admitted by the analysis
/// scheduler. The payload is immutable and is retained only by one in-flight
/// analysis or the single latest pending analysis. Camera framework objects are not
/// exposed to UI, persistence, or domain models.
///
/// CoreVideo does not provide a Sendable annotation for `CVPixelBuffer`.
/// This narrow unchecked boundary is justified by immutable-buffer scheduler ownership: after
/// the capture callback hands a payload to the scheduler, exactly one analyzer
/// task reads it and no code mutates it. The scheduler drops the reference when
/// the task completes, is cancelled, or is replaced.
nonisolated final class AnalysisFramePayload: @unchecked Sendable {
    let imageBuffer: CVPixelBuffer?
    let passageSurfaces: [PassageSurfaceEvidence]

    init(sampleBuffer: CMSampleBuffer, passageSurfaces: [PassageSurfaceEvidence] = []) {
        imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        self.passageSurfaces = Array(passageSurfaces.prefix(8))
    }

    init(imageBuffer: CVPixelBuffer, passageSurfaces: [PassageSurfaceEvidence]) {
        self.imageBuffer = imageBuffer
        self.passageSurfaces = Array(passageSurfaces.prefix(8))
    }
}

nonisolated struct AnalysisContext: Sendable {
    let frame: AnalysisFrame
    let payload: AnalysisFramePayload?

    init(frame: AnalysisFrame, payload: AnalysisFramePayload? = nil) {
        self.frame = frame
        self.payload = payload
    }
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

/// A framework-independent, normalized text observation. Its region is in
/// image coordinates with a **top-left** origin and values in `0...1`; Vision's
/// lower-left bounding boxes are transformed at the analyzer boundary.
nonisolated struct RecognizedTextObservation: Identifiable, Equatable, Sendable, Hashable {
    let id: UUID
    let analyzerID: AnalyzerIdentifier
    let sessionID: AnalysisSessionID
    let frameSequence: AnalysisFrameSequence
    let presentationTimeSeconds: Double?
    let text: String
    let rawFrameworkConfidence: Double
    let region: NormalizedRegion

    init(
        id: UUID = UUID(),
        analyzerID: AnalyzerIdentifier,
        sessionID: AnalysisSessionID,
        frameSequence: AnalysisFrameSequence,
        presentationTimeSeconds: Double?,
        text: String,
        rawFrameworkConfidence: Double,
        region: NormalizedRegion
    ) {
        self.id = id
        self.analyzerID = analyzerID
        self.sessionID = sessionID
        self.frameSequence = frameSequence
        self.presentationTimeSeconds = presentationTimeSeconds
        self.text = text
        self.rawFrameworkConfidence = rawFrameworkConfidence
        self.region = region
    }
}

/// A bounded, camera-image estimate around a real OCR region. Its ratio is
/// evidence from the captured image, not a display/material measurement or a
/// compliance result.
nonisolated struct ContrastObservation: Identifiable, Equatable, Sendable, Hashable {
    let id: UUID
    let analyzerID: AnalyzerIdentifier
    let sourceTextObservationID: UUID
    let sessionID: AnalysisSessionID
    let frameSequence: AnalysisFrameSequence
    let presentationTimeSeconds: Double?
    let region: NormalizedRegion
    let lowerLuminanceEstimate: Double
    let higherLuminanceEstimate: Double
    let estimatedContrastRatio: ContrastRatio
    let evidenceQuality: ContrastEvidenceQuality

    init(
        id: UUID = UUID(),
        analyzerID: AnalyzerIdentifier,
        sourceTextObservationID: UUID,
        sessionID: AnalysisSessionID,
        frameSequence: AnalysisFrameSequence,
        presentationTimeSeconds: Double?,
        region: NormalizedRegion,
        lowerLuminanceEstimate: Double,
        higherLuminanceEstimate: Double,
        estimatedContrastRatio: ContrastRatio,
        evidenceQuality: ContrastEvidenceQuality
    ) {
        self.id = id
        self.analyzerID = analyzerID
        self.sourceTextObservationID = sourceTextObservationID
        self.sessionID = sessionID
        self.frameSequence = frameSequence
        self.presentationTimeSeconds = presentationTimeSeconds
        self.region = region
        self.lowerLuminanceEstimate = lowerLuminanceEstimate
        self.higherLuminanceEstimate = higherLuminanceEstimate
        self.estimatedContrastRatio = estimatedContrastRatio
        self.evidenceQuality = evidenceQuality
    }
}

nonisolated struct ContrastRatio: Equatable, Sendable, Hashable {
    let value: Double

    /// Reconstructs a validated estimate without recomputing or rounding it.
    init?(estimatedValue: Double) {
        guard estimatedValue.isFinite, (1...21).contains(estimatedValue) else { return nil }
        value = estimatedValue
    }

    init(lighterLuminance: Double, darkerLuminance: Double) {
        let lighter = max(lighterLuminance, darkerLuminance)
        let darker = min(lighterLuminance, darkerLuminance)
        value = (lighter + 0.05) / (darker + 0.05)
    }
}

nonisolated enum ContrastEvidenceQuality: String, Equatable, Sendable, Hashable {
    case insufficient
    case low
    case usable
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
    let category: FindingCandidateCategory
    let recognizedText: String?
    let rawFrameworkConfidence: Double?
    let presentationTimeSeconds: Double?
    let sourceAnalyzerID: AnalyzerIdentifier
    /// All analyzers that contributed direct evidence to this candidate. This
    /// stays compact and framework-independent so a later finding can explain
    /// multi-analyzer provenance without retaining an image or framework type.
    let sourceAnalyzerIDs: [AnalyzerIdentifier]
    let estimatedContrastRatio: ContrastRatio?
    let contrastEvidenceQuality: ContrastEvidenceQuality?
    let passageSurfaceID: UUID?
    let passageEvidence: PassageFindingEvidence?

    init(
        id: UUID = UUID(),
        sessionID: AnalysisSessionID,
        sourceObservationIDs: [UUID],
        frameSequence: AnalysisFrameSequence,
        region: NormalizedRegion? = nil,
        evidenceKind: String,
        category: FindingCandidateCategory = .unclassified,
        recognizedText: String? = nil,
        rawFrameworkConfidence: Double? = nil,
        presentationTimeSeconds: Double? = nil,
        sourceAnalyzerID: AnalyzerIdentifier = AnalyzerIdentifier(rawValue: "unknown"),
        sourceAnalyzerIDs: [AnalyzerIdentifier]? = nil,
        estimatedContrastRatio: ContrastRatio? = nil,
        contrastEvidenceQuality: ContrastEvidenceQuality? = nil,
        passageSurfaceID: UUID? = nil,
        passageEvidence: PassageFindingEvidence? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.sourceObservationIDs = sourceObservationIDs
        self.frameSequence = frameSequence
        self.region = region
        self.evidenceKind = evidenceKind
        self.category = category
        self.recognizedText = recognizedText
        self.rawFrameworkConfidence = rawFrameworkConfidence
        self.presentationTimeSeconds = presentationTimeSeconds
        self.sourceAnalyzerID = sourceAnalyzerID
        self.sourceAnalyzerIDs = Array(Set(sourceAnalyzerIDs ?? [sourceAnalyzerID]))
            .sorted { $0.rawValue < $1.rawValue }
        self.estimatedContrastRatio = estimatedContrastRatio
        self.contrastEvidenceQuality = contrastEvidenceQuality
        self.passageSurfaceID = passageSurfaceID
        self.passageEvidence = passageEvidence
    }
}

/// Candidate categories are transient evidence groupings. They are not legal,
/// accessibility-compliance, severity, or persisted finding classifications.
nonisolated enum FindingCandidateCategory: String, Equatable, Sendable, Hashable {
    case unclassified
    case environmentalSignage
    case potentialLowContrastText
    case potentialNarrowPassage
}

nonisolated struct AnalyzerOutput: Equatable, Sendable {
    let observations: [NormalizedObservation]
    let textObservations: [RecognizedTextObservation]
    let contrastObservations: [ContrastObservation]
    let passageObservations: [PassageObservation]
    let candidates: [FindingCandidate]

    init(
        observations: [NormalizedObservation] = [],
        textObservations: [RecognizedTextObservation] = [],
        contrastObservations: [ContrastObservation] = [],
        passageObservations: [PassageObservation] = [],
        candidates: [FindingCandidate] = []
    ) {
        self.observations = observations
        self.textObservations = textObservations
        self.contrastObservations = contrastObservations
        self.passageObservations = passageObservations
        self.candidates = candidates
    }

    static let empty = AnalyzerOutput()
}

nonisolated enum AnalysisError: Error, Equatable, Sendable {
    case invalidFrame
    case invalidRegion
    case insufficientPixels
    case invalidImageBuffer
    case unsupportedPixelFormat
    case insufficientEvidence
    case unsupportedOrientation
    case insufficientCalibration
    case depthUnavailable
    case invalidGeometry
    case insufficientSceneEvidence
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
    let textObservations: [RecognizedTextObservation]
    let contrastObservations: [ContrastObservation]
    let passageObservations: [PassageObservation]
    let candidates: [FindingCandidate]
    let failures: [AnalysisFailure]
}
