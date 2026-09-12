@preconcurrency import AVFoundation
import CoreVideo
import CoreImage
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
                    from: payload.imageBuffer,
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
                        sourceAnalyzerIDs: [textObservation.analyzerID, identifier],
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
        from pixelBuffer: CVPixelBuffer?,
        crop: PixelCropRect,
        maximumSamples: Int = 1_024
    ) throws -> [ContrastRGBSample] {
        guard let pixelBuffer else {
            throw AnalysisError.invalidImageBuffer
        }
        guard crop.width > 0, crop.height > 0, maximumSamples > 0 else {
            throw AnalysisError.insufficientPixels
        }

        if CVPixelBufferGetPixelFormatType(pixelBuffer) != kCVPixelFormatType_32BGRA {
            return try samplesFromCoreImage(
                pixelBuffer: pixelBuffer,
                crop: crop,
                maximumSamples: maximumSamples
            )
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

    /// RoomPlan/ARKit commonly supplies bi-planar camera buffers. Core Image
    /// performs the platform color conversion while the crop is downsampled to
    /// at most 1,024 pixels; no full-frame copy or retained CIImage is created.
    private static func samplesFromCoreImage(
        pixelBuffer: CVPixelBuffer,
        crop: PixelCropRect,
        maximumSamples: Int
    ) throws -> [ContrastRGBSample] {
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        guard crop.x >= 0, crop.y >= 0,
              crop.x + crop.width <= sourceWidth,
              crop.y + crop.height <= sourceHeight else {
            throw AnalysisError.invalidRegion
        }
        try Task.checkCancellation()

        let ciCrop = CGRect(
            x: crop.x,
            y: sourceHeight - crop.y - crop.height,
            width: crop.width,
            height: crop.height
        )
        let aspect = Double(crop.width) / Double(crop.height)
        let sampleHeight = max(1, min(crop.height, Int(sqrt(Double(maximumSamples) / max(aspect, 0.0001)))))
        let sampleWidth = max(1, min(crop.width, maximumSamples / sampleHeight))
        guard sampleWidth * sampleHeight >= 2 else { throw AnalysisError.insufficientPixels }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
            .cropped(to: ciCrop)
            .transformed(by: CGAffineTransform(translationX: -ciCrop.minX, y: -ciCrop.minY))
            .transformed(by: CGAffineTransform(
                scaleX: CGFloat(sampleWidth) / ciCrop.width,
                y: CGFloat(sampleHeight) / ciCrop.height
            ))
        var bytes = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
        CIContext(options: [.cacheIntermediates: false]).render(
            image,
            toBitmap: &bytes,
            rowBytes: sampleWidth * 4,
            bounds: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight),
            format: .BGRA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        try Task.checkCancellation()
        return stride(from: 0, to: bytes.count, by: 4).map { index in
            ContrastRGBSample(
                red: Double(bytes[index + 2]) / 255,
                green: Double(bytes[index + 1]) / 255,
                blue: Double(bytes[index]) / 255
            )
        }
    }
}
