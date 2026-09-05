import Foundation

/// A compact RGB sample used only while estimating a single OCR crop. Values
/// are normalized sRGB components in `0...1`.
nonisolated struct ContrastRGBSample: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
}

nonisolated struct PixelCropRect: Equatable, Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    var area: Int { width * height }
}

/// Converts an AccessLens top-left normalized OCR region into a clamped raw
/// pixel-buffer crop. OCR regions are oriented before this conversion; the
/// converter maps their four corners back into the capture buffer orientation.
nonisolated enum ContrastRegionConverter {
    static func cropRect(
        for region: NormalizedRegion,
        dimensions: AnalysisFrameDimensions,
        orientation: AnalysisImageOrientation
    ) -> PixelCropRect? {
        guard region.x.isFinite, region.y.isFinite,
              region.width.isFinite, region.height.isFinite,
              region.width > 0, region.height > 0,
              dimensions.width > 0, dimensions.height > 0 else {
            return nil
        }

        let corners = [
            (region.x, region.y),
            (region.x + region.width, region.y),
            (region.x, region.y + region.height),
            (region.x + region.width, region.y + region.height)
        ].map { rawPoint(fromOrientedX: $0.0, y: $0.1, orientation: orientation) }

        let minimumX = max(0, min(1, corners.map(\.0).min() ?? 0))
        let maximumX = max(0, min(1, corners.map(\.0).max() ?? 0))
        let minimumY = max(0, min(1, corners.map(\.1).min() ?? 0))
        let maximumY = max(0, min(1, corners.map(\.1).max() ?? 0))

        // Avoid adding an extra pixel when an exact normalized boundary (such
        // as 0.6) is represented infinitesimally above its mathematical value.
        let boundaryTolerance = 0.000_001
        let left = Int(floor(minimumX * Double(dimensions.width) + boundaryTolerance))
        let right = Int(ceil(maximumX * Double(dimensions.width) - boundaryTolerance))
        let top = Int(floor(minimumY * Double(dimensions.height) + boundaryTolerance))
        let bottom = Int(ceil(maximumY * Double(dimensions.height) - boundaryTolerance))
        let clampedLeft = min(max(left, 0), dimensions.width)
        let clampedRight = min(max(right, 0), dimensions.width)
        let clampedTop = min(max(top, 0), dimensions.height)
        let clampedBottom = min(max(bottom, 0), dimensions.height)

        guard clampedRight > clampedLeft, clampedBottom > clampedTop else {
            return nil
        }
        return PixelCropRect(
            x: clampedLeft,
            y: clampedTop,
            width: clampedRight - clampedLeft,
            height: clampedBottom - clampedTop
        )
    }

    private static func rawPoint(
        fromOrientedX x: Double,
        y: Double,
        orientation: AnalysisImageOrientation
    ) -> (Double, Double) {
        switch orientation {
        case .up:
            (x, y)
        case .upMirrored:
            (1 - x, y)
        case .down:
            (1 - x, 1 - y)
        case .downMirrored:
            (x, 1 - y)
        case .leftMirrored:
            (y, x)
        case .right:
            (y, 1 - x)
        case .rightMirrored:
            (1 - y, 1 - x)
        case .left:
            (1 - y, x)
        }
    }
}

/// IEC sRGB linearization followed by the standard relative-luminance
/// coefficients. This is a deterministic image-space calculation, not a
/// material/display measurement.
nonisolated enum RelativeLuminance {
    static func value(for sample: ContrastRGBSample) -> Double {
        0.2126 * linearized(sample.red)
            + 0.7152 * linearized(sample.green)
            + 0.0722 * linearized(sample.blue)
    }

    private static func linearized(_ component: Double) -> Double {
        let clamped = min(max(component, 0), 1)
        return clamped <= 0.04045
            ? clamped / 12.92
            : pow((clamped + 0.055) / 1.055, 2.4)
    }
}

nonisolated struct VisualContrastMeasurement: Equatable, Sendable {
    let lowerLuminanceEstimate: Double
    let higherLuminanceEstimate: Double
    let ratio: ContrastRatio
    let evidenceQuality: ContrastEvidenceQuality
    let sampleCount: Int
    let luminanceSeparation: Double
}

/// Uses the medians of trimmed lower and upper luminance quartiles rather
/// than individual darkest/brightest pixels. This limits glare/noise outliers,
/// but cannot identify semantic foreground/background or overcome camera
/// exposure, HDR, blur, shadow, reflection, or material/viewing-angle effects.
nonisolated enum VisualContrastEstimator {
    static func estimate(
        samples: [ContrastRGBSample],
        regionPixelArea: Int,
        qualityPolicy: ContrastEvidenceQualityPolicy = ContrastEvidenceQualityPolicy()
    ) -> VisualContrastMeasurement? {
        guard samples.count >= 2 else { return nil }
        let luminances = samples.map(RelativeLuminance.value).sorted()
        let bandCount = max(1, luminances.count / 4)
        let lower = median(Array(luminances.prefix(bandCount)))
        let higher = median(Array(luminances.suffix(bandCount)))
        let separation = higher - lower
        let quality = qualityPolicy.quality(
            sampleCount: samples.count,
            regionPixelArea: regionPixelArea,
            luminanceSeparation: separation
        )
        return VisualContrastMeasurement(
            lowerLuminanceEstimate: lower,
            higherLuminanceEstimate: higher,
            ratio: ContrastRatio(lighterLuminance: higher, darkerLuminance: lower),
            evidenceQuality: quality,
            sampleCount: samples.count,
            luminanceSeparation: separation
        )
    }

    private static func median(_ values: [Double]) -> Double {
        let midpoint = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[midpoint - 1] + values[midpoint]) / 2
        }
        return values[midpoint]
    }
}

nonisolated struct ContrastEvidenceQualityPolicy: Equatable, Sendable {
    let minimumSampleCount: Int
    let minimumPixelArea: Int
    let minimumSeparation: Double
    let usableSampleCount: Int
    let usableSeparation: Double

    init(
        minimumSampleCount: Int = 64,
        minimumPixelArea: Int = 256,
        minimumSeparation: Double = 0.025,
        usableSampleCount: Int = 128,
        usableSeparation: Double = 0.08
    ) {
        self.minimumSampleCount = minimumSampleCount
        self.minimumPixelArea = minimumPixelArea
        self.minimumSeparation = minimumSeparation
        self.usableSampleCount = usableSampleCount
        self.usableSeparation = usableSeparation
    }

    func quality(
        sampleCount: Int,
        regionPixelArea: Int,
        luminanceSeparation: Double
    ) -> ContrastEvidenceQuality {
        guard sampleCount >= minimumSampleCount,
              regionPixelArea >= minimumPixelArea,
              luminanceSeparation >= minimumSeparation else {
            return .insufficient
        }
        guard sampleCount >= usableSampleCount,
              luminanceSeparation >= usableSeparation else {
            return .low
        }
        return .usable
    }
}

nonisolated enum EstimatedContrastClassification: Equatable, Sendable {
    case likelyAdequate
    case borderline
    case potentiallyLow
    case insufficientEvidence
}

/// A conservative product heuristic. It deliberately avoids text-size rules
/// and does not certify compliance. The 3.0 / 4.5 bands provide explanatory
/// image-estimate language only; they do not assert WCAG or legal outcomes.
nonisolated struct EstimatedContrastPolicy: Equatable, Sendable {
    let potentialLowBelow: Double
    let borderlineBelow: Double

    init(potentialLowBelow: Double = 3.0, borderlineBelow: Double = 4.5) {
        self.potentialLowBelow = potentialLowBelow
        self.borderlineBelow = borderlineBelow
    }

    func classify(_ measurement: VisualContrastMeasurement) -> EstimatedContrastClassification {
        guard measurement.evidenceQuality == .usable else {
            return .insufficientEvidence
        }
        if measurement.ratio.value < potentialLowBelow { return .potentiallyLow }
        if measurement.ratio.value < borderlineBelow { return .borderline }
        return .likelyAdequate
    }
}
