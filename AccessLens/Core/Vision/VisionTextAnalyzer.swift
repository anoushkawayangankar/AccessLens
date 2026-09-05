@preconcurrency import AVFoundation
import Foundation
import OSLog
import Vision

/// The live-signage OCR policy. These values are deliberately conservative
/// admission-quality filters, not a statement of text correctness or an
/// accessibility confidence score.
nonisolated struct VisionTextRecognitionConfiguration: Equatable, Sendable {
    let recognitionLevel: RecognitionLevel
    let usesLanguageCorrection: Bool
    let recognitionLanguages: [String]
    let minimumTextHeight: Float
    let minimumConfidence: Double
    let maximumCharacterCount: Int

    nonisolated enum RecognitionLevel: Equatable, Sendable {
        case fast
        case accurate
    }

    static let environmentalSignage = VisionTextRecognitionConfiguration(
        recognitionLevel: .fast,
        usesLanguageCorrection: false,
        recognitionLanguages: ["en-US"],
        minimumTextHeight: 0.02,
        minimumConfidence: 0.35,
        maximumCharacterCount: 160
    )
}

/// Portable recognition data used by the Vision adapter and deterministic
/// mapper tests. `visionBoundingBox` has Vision's lower-left origin.
nonisolated struct VisionTextRecognitionResult: Equatable, Sendable {
    let text: String
    let confidence: Double
    let visionBoundingBox: NormalizedRegion
}

/// Performs the one real Vision request admitted by the bounded scheduler.
/// Vision framework values are mapped to value types before leaving this file.
nonisolated final class VisionTextAnalyzer: AccessibilityAnalyzer {
    let identifier = AnalyzerIdentifier(rawValue: "vision.text.v1")

    private let configuration: VisionTextRecognitionConfiguration
    private let signageClassifier: SignageCandidateClassifier

    init(
        configuration: VisionTextRecognitionConfiguration = .environmentalSignage,
        signageClassifier: SignageCandidateClassifier = SignageCandidateClassifier()
    ) {
        self.configuration = configuration
        self.signageClassifier = signageClassifier
    }

    func analyze(
        _ context: AnalysisContext,
        priorOutput _: AnalyzerOutput
    ) async throws -> AnalyzerOutput {
        try Task.checkCancellation()
        guard let payload = context.payload else {
            throw AnalysisError.invalidFrame
        }
        guard let orientation = context.frame.orientation else {
            throw AnalysisError.unsupportedOrientation
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = visionRecognitionLevel
        request.usesLanguageCorrection = configuration.usesLanguageCorrection
        request.recognitionLanguages = configuration.recognitionLanguages
        request.minimumTextHeight = configuration.minimumTextHeight

        do {
            let handler = VNImageRequestHandler(
                cmSampleBuffer: payload.sampleBuffer,
                orientation: orientation.cgImagePropertyOrientation,
                options: [:]
            )
            try handler.perform([request])
        } catch {
            AppLog.vision.error("Vision text request failed")
            throw AnalysisError.analyzerFailed(identifier)
        }

        try Task.checkCancellation()
        let mappedResults = (request.results ?? []).compactMap { observation -> VisionTextRecognitionResult? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return VisionTextRecognitionResult(
                text: candidate.string,
                confidence: Double(candidate.confidence),
                visionBoundingBox: NormalizedRegion(
                    x: observation.boundingBox.origin.x,
                    y: observation.boundingBox.origin.y,
                    width: observation.boundingBox.width,
                    height: observation.boundingBox.height
                )
            )
        }

        let output = VisionTextObservationMapper.makeOutput(
            recognizedResults: mappedResults,
            context: context,
            analyzerID: identifier,
            configuration: configuration,
            classifier: signageClassifier
        )
        if !output.textObservations.isEmpty {
            AppLog.vision.debug("Vision text analysis produced \(output.textObservations.count, privacy: .public) observations")
        }
        return output
    }

    private var visionRecognitionLevel: VNRequestTextRecognitionLevel {
        switch configuration.recognitionLevel {
        case .fast:
            .fast
        case .accurate:
            .accurate
        }
    }
}

/// Converts Vision-shaped recognition values into framework-independent data.
/// It is intentionally separate from request execution for deterministic tests.
nonisolated enum VisionTextObservationMapper {
    static func makeOutput(
        recognizedResults: [VisionTextRecognitionResult],
        context: AnalysisContext,
        analyzerID: AnalyzerIdentifier,
        configuration: VisionTextRecognitionConfiguration,
        classifier: SignageCandidateClassifier
    ) -> AnalyzerOutput {
        let textObservations = recognizedResults.compactMap { result -> RecognizedTextObservation? in
            guard let normalizedText = normalizedText(
                result.text,
                maximumCharacterCount: configuration.maximumCharacterCount
            ), result.confidence >= configuration.minimumConfidence else {
                return nil
            }

            let region = topLeftRegion(fromVisionBoundingBox: result.visionBoundingBox)
            return RecognizedTextObservation(
                analyzerID: analyzerID,
                sessionID: context.frame.sessionID,
                frameSequence: context.frame.sequence,
                presentationTimeSeconds: context.frame.presentationTimeSeconds,
                text: normalizedText,
                rawFrameworkConfidence: result.confidence,
                region: region
            )
        }

        let observations = textObservations.map { textObservation in
            NormalizedObservation(
                id: textObservation.id,
                analyzerID: textObservation.analyzerID,
                sessionID: textObservation.sessionID,
                frameSequence: textObservation.frameSequence,
                region: textObservation.region,
                rawFrameworkConfidence: textObservation.rawFrameworkConfidence,
                evidenceKind: "recognized-text"
            )
        }
        let candidates = textObservations.compactMap(classifier.classify)
        return AnalyzerOutput(
            observations: observations,
            textObservations: textObservations,
            candidates: candidates
        )
    }

    static func normalizedText(_ text: String, maximumCharacterCount: Int) -> String? {
        let components = text.split(whereSeparator: { $0.isWhitespace })
        let normalized = components.joined(separator: " ")
        guard !normalized.isEmpty, normalized.count <= maximumCharacterCount else {
            return nil
        }
        return normalized
    }

    static func topLeftRegion(fromVisionBoundingBox region: NormalizedRegion) -> NormalizedRegion {
        NormalizedRegion(
            x: region.x,
            y: 1 - region.y - region.height,
            width: region.width,
            height: region.height
        )
    }
}
