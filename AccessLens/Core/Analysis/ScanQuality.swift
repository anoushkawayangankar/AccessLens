@preconcurrency import CoreVideo
import Foundation
import OSLog

/// Discrete capture quality. The product never presents the internal image
/// metrics as a percentage or as proof that an environment was fully assessed.
nonisolated enum ScanQualityState: String, CaseIterable, Equatable, Sendable, Hashable {
    case good
    case limited
    case unusable

    var displayName: String {
        switch self {
        case .good: String(localized: "Good")
        case .limited: String(localized: "Limited")
        case .unusable: String(localized: "Unusable")
        }
    }
}

/// Reasons are based only on measurable image-space conditions. There is no
/// semantic claim that a particular target or accessibility feature is absent.
nonisolated enum ScanFrameQualityReason: String, CaseIterable, Equatable, Sendable, Hashable {
    case severeUnderexposure
    case severeOverexposure
    case lowSharpness
    case possibleHighlightSaturation
    case insufficientVisibleDetail
    case targetClipped
    case imageUnavailable
}

/// Internal deterministic metrics derived from a bounded luminance grid. They
/// are test inputs and policy evidence, not user-facing confidence values.
nonisolated struct ScanQualityMetrics: Equatable, Sendable {
    let meanLuminance: Double
    let darkFraction: Double
    let brightFraction: Double
    let saturatedFraction: Double
    let sharpness: Double
    let luminanceRange: Double
}

nonisolated struct ScanFrameQuality: Equatable, Sendable {
    let state: ScanQualityState
    let reasons: [ScanFrameQualityReason]
    let metrics: ScanQualityMetrics?

    static let unavailable = ScanFrameQuality(
        state: .limited,
        reasons: [.imageUnavailable],
        metrics: nil
    )

    func applyingFraming(to candidates: [FindingCandidate]) -> ScanFrameQuality {
        let isClipped = candidates.contains { candidate in
            guard let region = candidate.region, NormalizedRegionAssociation.isValid(region) else { return false }
            let margin = 0.005
            return region.x <= margin || region.y <= margin
                || region.x + region.width >= 1 - margin
                || region.y + region.height >= 1 - margin
        }
        guard isClipped, !reasons.contains(.targetClipped) else { return self }
        return ScanFrameQuality(
            state: state == .unusable ? .unusable : .limited,
            reasons: reasons + [.targetClipped],
            metrics: metrics
        )
    }
}

/// Thresholds are deliberately centralized and exercised by synthetic tests.
/// Exposure becomes unusable only when both the mean and most samples are at
/// an extreme. Low sharpness alone is limited because a plain surface can look
/// numerically similar to blur.
nonisolated struct ScanQualityPolicy: Equatable, Sendable {
    let underexposedMeanMaximum: Double
    let overexposedMeanMinimum: Double
    let extremePixelFraction: Double
    let lowSharpnessMaximum: Double
    let minimumVisibleRange: Double
    let saturatedRegionFraction: Double

    init(
        underexposedMeanMaximum: Double = 0.06,
        overexposedMeanMinimum: Double = 0.94,
        extremePixelFraction: Double = 0.85,
        lowSharpnessMaximum: Double = 0.012,
        minimumVisibleRange: Double = 0.04,
        saturatedRegionFraction: Double = 0.35
    ) {
        self.underexposedMeanMaximum = underexposedMeanMaximum
        self.overexposedMeanMinimum = overexposedMeanMinimum
        self.extremePixelFraction = extremePixelFraction
        self.lowSharpnessMaximum = lowSharpnessMaximum
        self.minimumVisibleRange = minimumVisibleRange
        self.saturatedRegionFraction = saturatedRegionFraction
    }

    func classify(_ metrics: ScanQualityMetrics) -> ScanFrameQuality {
        if metrics.meanLuminance <= underexposedMeanMaximum,
           metrics.darkFraction >= extremePixelFraction {
            return ScanFrameQuality(state: .unusable, reasons: [.severeUnderexposure], metrics: metrics)
        }
        if metrics.meanLuminance >= overexposedMeanMinimum,
           metrics.brightFraction >= extremePixelFraction {
            return ScanFrameQuality(state: .unusable, reasons: [.severeOverexposure], metrics: metrics)
        }

        var reasons: [ScanFrameQualityReason] = []
        if metrics.saturatedFraction >= saturatedRegionFraction {
            reasons.append(.possibleHighlightSaturation)
        }
        if metrics.luminanceRange < minimumVisibleRange {
            reasons.append(.insufficientVisibleDetail)
        } else if metrics.sharpness < lowSharpnessMaximum {
            reasons.append(.lowSharpness)
        }
        return ScanFrameQuality(
            state: reasons.isEmpty ? .good : .limited,
            reasons: reasons,
            metrics: metrics
        )
    }
}

/// Runs once for each frame already admitted by the scheduler, before Vision
/// or RoomPlan interpretation. It reads at most a 32 x 32 luminance grid and
/// retains neither that grid nor the source pixel buffer.
nonisolated struct ScanQualityEvaluator: Sendable {
    let policy: ScanQualityPolicy

    init(policy: ScanQualityPolicy = ScanQualityPolicy()) {
        self.policy = policy
    }

    func evaluate(_ context: AnalysisContext) throws -> ScanFrameQuality {
        try Task.checkCancellation()
        guard let imageBuffer = context.payload?.imageBuffer else { return .unavailable }
        guard let grid = try BoundedLuminanceSampler.sample(imageBuffer), grid.values.count >= 4 else {
            return .unavailable
        }
        try Task.checkCancellation()
        return policy.classify(Self.metrics(for: grid))
    }

    static func metrics(for grid: LuminanceGrid) -> ScanQualityMetrics {
        let values = grid.values
        let count = Double(values.count)
        let mean = values.reduce(0, +) / count
        let dark = Double(values.lazy.filter { $0 <= 0.04 }.count) / count
        let bright = Double(values.lazy.filter { $0 >= 0.96 }.count) / count
        let saturated = Double(values.lazy.filter { $0 >= 0.985 }.count) / count

        var differenceTotal = 0.0
        var differenceCount = 0
        for row in 0..<grid.height {
            for column in 0..<grid.width {
                let index = row * grid.width + column
                if column + 1 < grid.width {
                    differenceTotal += abs(values[index] - values[index + 1])
                    differenceCount += 1
                }
                if row + 1 < grid.height {
                    differenceTotal += abs(values[index] - values[index + grid.width])
                    differenceCount += 1
                }
            }
        }
        let sharpness = differenceCount == 0 ? 0 : differenceTotal / Double(differenceCount)
        return ScanQualityMetrics(
            meanLuminance: mean,
            darkFraction: dark,
            brightFraction: bright,
            saturatedFraction: saturated,
            sharpness: sharpness,
            luminanceRange: (values.max() ?? 0) - (values.min() ?? 0)
        )
    }
}

nonisolated struct LuminanceGrid: Equatable, Sendable {
    let width: Int
    let height: Int
    let values: [Double]
}

private nonisolated enum BoundedLuminanceSampler {
    static func sample(_ pixelBuffer: CVPixelBuffer, maximumSide: Int = 32) throws -> LuminanceGrid? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 1, height > 1, maximumSide > 1 else { return nil }
        let gridWidth = min(maximumSide, width)
        let gridHeight = min(maximumSide, height)
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        if format == kCVPixelFormatType_32BGRA,
           let address = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let bytes = address.assumingMemoryBound(to: UInt8.self)
            let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
            var values: [Double] = []
            values.reserveCapacity(gridWidth * gridHeight)
            for row in 0..<gridHeight {
                if Task.isCancelled { throw CancellationError() }
                let y = min(height - 1, row * height / gridHeight)
                for column in 0..<gridWidth {
                    let x = min(width - 1, column * width / gridWidth)
                    let pixel = bytes.advanced(by: y * rowBytes + x * 4)
                    values.append((0.2126 * Double(pixel[2]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[0])) / 255)
                }
            }
            return LuminanceGrid(width: gridWidth, height: gridHeight, values: values)
        }

        let supportedYUV = format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            || format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        guard supportedYUV, CVPixelBufferGetPlaneCount(pixelBuffer) > 0,
              let address = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }
        let planeWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let planeHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let bytes = address.assumingMemoryBound(to: UInt8.self)
        let isVideoRange = format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        var values: [Double] = []
        values.reserveCapacity(gridWidth * gridHeight)
        for row in 0..<gridHeight {
            if Task.isCancelled { throw CancellationError() }
            let y = min(planeHeight - 1, row * planeHeight / gridHeight)
            for column in 0..<gridWidth {
                let x = min(planeWidth - 1, column * planeWidth / gridWidth)
                let raw = Double(bytes[y * rowBytes + x])
                let normalized = isVideoRange ? (raw - 16) / 219 : raw / 255
                values.append(min(max(normalized, 0), 1))
            }
        }
        return LuminanceGrid(width: gridWidth, height: gridHeight, values: values)
    }
}

/// Persistable scan-level summary. It is categorical and explanatory rather
/// than a numeric score, and it contains no per-frame quality history.
nonisolated struct ScanQualitySummary: Equatable, Sendable, Hashable {
    let state: ScanQualityState
    let summary: String
}

nonisolated struct ScanQualityPresentation: Equatable, Sendable {
    let frameQuality: ScanFrameQuality
    let guidance: String?
    let summary: ScanQualitySummary
}

/// Bounded, lock-isolated quality history and live-message debounce. A reason
/// must repeat on two admitted frames; two subsequent good frames clear it.
nonisolated final class ScanQualityGuidanceStabilizer: @unchecked Sendable {
    private struct State {
        var sessionID: AnalysisSessionID?
        var history: [ScanQualityState] = []
        var pendingReason: ScanFrameQualityReason?
        var pendingCount = 0
        var displayedReason: ScanFrameQualityReason?
        var consecutiveGood = 0
    }

    private let lock = NSLock()
    private let maximumHistoryCount: Int
    private var state = State()

    init(maximumHistoryCount: Int = 8) {
        self.maximumHistoryCount = max(1, maximumHistoryCount)
    }

    func beginSession(_ sessionID: AnalysisSessionID) {
        lock.lock()
        state = State(sessionID: sessionID)
        lock.unlock()
    }

    func endSession(_ sessionID: AnalysisSessionID) {
        lock.lock()
        if state.sessionID == sessionID { state = State() }
        lock.unlock()
    }

    func ingest(_ quality: ScanFrameQuality, sessionID: AnalysisSessionID) -> ScanQualityPresentation? {
        lock.lock()
        defer { lock.unlock() }
        guard state.sessionID == sessionID else { return nil }

        state.history.append(quality.state)
        if state.history.count > maximumHistoryCount {
            state.history.removeFirst(state.history.count - maximumHistoryCount)
        }

        let reason = highestPriorityReason(in: quality.reasons)
        if quality.state == .good || reason == nil || reason == .imageUnavailable {
            state.consecutiveGood += 1
            state.pendingReason = nil
            state.pendingCount = 0
            if state.consecutiveGood >= 2 { state.displayedReason = nil }
        } else {
            state.consecutiveGood = 0
            if state.pendingReason == reason {
                state.pendingCount += 1
            } else {
                state.pendingReason = reason
                state.pendingCount = 1
            }
            if state.pendingCount >= 2 { state.displayedReason = reason }
        }

        if quality.state != .good {
            AppLog.analysis.debug("Scan quality downgraded")
        }
        return ScanQualityPresentation(
            frameQuality: quality,
            guidance: state.displayedReason.flatMap(guidance(for:)),
            summary: makeSummary()
        )
    }

    func snapshot(for sessionID: AnalysisSessionID) -> ScanQualitySummary? {
        lock.lock()
        defer { lock.unlock() }
        guard state.sessionID == sessionID, !state.history.isEmpty else { return nil }
        return makeSummary()
    }

    private func makeSummary() -> ScanQualitySummary {
        let goodCount = state.history.filter { $0 == .good }.count
        let limitedCount = state.history.filter { $0 == .limited }.count
        let unusableCount = state.history.filter { $0 == .unusable }.count
        if goodCount > 0, goodCount >= limitedCount + unusableCount {
            return ScanQualitySummary(
                state: .good,
                summary: String(localized: "Recent frames provided adequate visibility for supported analysis.")
            )
        }
        return ScanQualitySummary(
            state: .limited,
            summary: String(localized: "Some areas were captured with limited visibility. Review the environment directly and consider scanning again.")
        )
    }

    private func highestPriorityReason(in reasons: [ScanFrameQualityReason]) -> ScanFrameQualityReason? {
        let priority: [ScanFrameQualityReason] = [
            .targetClipped,
            .lowSharpness,
            .severeUnderexposure,
            .severeOverexposure,
            .possibleHighlightSaturation,
            .insufficientVisibleDetail,
            .imageUnavailable
        ]
        return priority.first(where: reasons.contains)
    }

    private func guidance(for reason: ScanFrameQualityReason) -> String? {
        switch reason {
        case .targetClipped:
            String(localized: "Keep the area fully in view.")
        case .lowSharpness:
            String(localized: "Hold the phone steady and include clear visual detail.")
        case .severeUnderexposure:
            String(localized: "Move to better lighting.")
        case .severeOverexposure:
            String(localized: "Reduce direct light on the area.")
        case .possibleHighlightSaturation:
            String(localized: "Change the camera angle to reduce bright reflections.")
        case .insufficientVisibleDetail:
            String(localized: "Include more visible detail in the frame.")
        case .imageUnavailable:
            nil
        }
    }
}
