@preconcurrency import AVFoundation
import CoreVideo
import Foundation
import OSLog

/// Measures image-space luminance separation only around same-frame signage
/// OCR regions. It never analyzes arbitrary full-frame content and never
/// turns a camera estimate into a legal or accessibility-compliance result.
nonisolated final class VisualContrastAnalyzer: AccessibilityAnalyzer {
    let identifier = AnalyzerIdentifier(rawValue: "vision.visual-contrast.v1")

    private let qualityPolicy: ContrastEvidenceQualityPolicy
    private let classificationPolicy: EstimatedContrastPolicy

    init(
        qualityPolicy: ContrastEvidenceQualityPolicy = ContrastEvidenceQualityPolicy(),
        classificationPolicy: EstimatedContrastPolicy = EstimatedContrastPolicy()
    ) {
        self.qualityPolicy = qualityPolicy
        self.classificationPolicy = classificationPolicy
    }

    func analyze(
        _ context: AnalysisContext,
        priorOutput: AnalyzerOutput
    ) async throws -> AnalyzerOutput {
        try Task.checkCancellation()
        guard let payload = context.payload,
              let dimensions = context.frame.dimensions,
              let orientation = context.frame.orientation else {
            throw AnalysisError.invalidFrame
        }

        let signageObservationIDs = Set(
            priorOutput.candidates
                .filter { $0.category == .environmentalSignage }
                .flatMap(\.sourceObservationIDs)
        )
        let relevantText = priorOutput.textObservations.filter {
            signageObservationIDs.contains($0.id)
        }
        guard !relevantText.isEmpty else { return .empty }

        var contrastObservations: [ContrastObservation] = []
        var candidates: [FindingCandidate] = []

        for textObservation in relevantText {
            try Task.checkCancellation()
            guard let crop = ContrastRegionConverter.cropRect(
                for: textObservation.region,
                dimensions: dimensions,
                orientation: orientation
            ) else {
                continue
            }

            do {
                let samples = try BGRARegionSampler.samples(
                    from: payload.sampleBuffer,
                    crop: crop
                )
                guard let measurement = VisualContrastEstimator.estimate(
                    samples: samples,
                    regionPixelArea: crop.area,
                    qualityPolicy: qualityPolicy
                ) else {
                    continue
                }

                let contrastObservation = ContrastObservation(
                    analyzerID: identifier,
                    sourceTextObservationID: textObservation.id,
                    sessionID: textObservation.sessionID,
                    frameSequence: textObservation.frameSequence,
                    presentationTimeSeconds: textObservation.presentationTimeSeconds,
                    region: textObservation.region,
                    lowerLuminanceEstimate: measurement.lowerLuminanceEstimate,
                    higherLuminanceEstimate: measurement.higherLuminanceEstimate,
                    estimatedContrastRatio: measurement.ratio,
                    evidenceQuality: measurement.evidenceQuality
                )
                contrastObservations.append(contrastObservation)

                if classificationPolicy.classify(measurement) == .potentiallyLow {
                    candidates.append(FindingCandidate(
                        sessionID: textObservation.sessionID,
                        sourceObservationIDs: [textObservation.id, contrastObservation.id],
                        frameSequence: textObservation.frameSequence,
                        region: textObservation.region,
                        evidenceKind: "visual-contrast.potential-low",
                        category: .potentialLowContrastText,
                        recognizedText: textObservation.text,
                        rawFrameworkConfidence: textObservation.rawFrameworkConfidence,
                        presentationTimeSeconds: textObservation.presentationTimeSeconds,
                        sourceAnalyzerID: identifier,
                        estimatedContrastRatio: measurement.ratio,
                        contrastEvidenceQuality: measurement.evidenceQuality
                    ))
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as AnalysisError {
                if error == .insufficientPixels {
                    AppLog.analysis.debug("Contrast evidence was insufficient")
                    continue
                }
                AppLog.analysis.error("Visual contrast analysis failed")
                throw AnalysisError.analyzerFailed(identifier)
            } catch {
                AppLog.analysis.error("Visual contrast analysis failed")
                throw AnalysisError.analyzerFailed(identifier)
            }
        }

        if !candidates.isEmpty {
            AppLog.analysis.debug("Visual contrast analysis created \(candidates.count, privacy: .public) candidates")
        }
        return AnalyzerOutput(
            contrastObservations: contrastObservations,
            candidates: candidates
        )
    }
}

/// Samples at most 1,024 BGRA pixels from one bounded crop. It locks the
/// current CVPixelBuffer only for synchronous read access and keeps no crop or
/// pixel data after the analyzer returns.
private nonisolated enum BGRARegionSampler {
    static func samples(
        from sampleBuffer: CMSampleBuffer,
        crop: PixelCropRect,
        maximumSamples: Int = 1_024
    ) throws -> [ContrastRGBSample] {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw AnalysisError.invalidImageBuffer
        }
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            throw AnalysisError.unsupportedPixelFormat
        }
        guard crop.width > 0, crop.height > 0, maximumSamples > 0 else {
            throw AnalysisError.insufficientPixels
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw AnalysisError.invalidImageBuffer
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let step = max(1, Int(ceil(sqrt(Double(crop.area) / Double(maximumSamples)))))
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        var samples: [ContrastRGBSample] = []
        samples.reserveCapacity(min(maximumSamples, crop.area))

        for y in stride(from: crop.y, to: crop.y + crop.height, by: step) {
            for x in stride(from: crop.x, to: crop.x + crop.width, by: step) {
                if Task.isCancelled { throw CancellationError() }
                let pixel = bytes.advanced(by: y * bytesPerRow + x * 4)
                samples.append(ContrastRGBSample(
                    red: Double(pixel[2]) / 255,
                    green: Double(pixel[1]) / 255,
                    blue: Double(pixel[0]) / 255
                ))
            }
        }
        guard samples.count >= 2 else { throw AnalysisError.insufficientPixels }
        return samples
    }
}
