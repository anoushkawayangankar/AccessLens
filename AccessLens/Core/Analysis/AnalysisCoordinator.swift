@preconcurrency import AVFoundation
import CoreVideo
import Foundation

/// Connects camera-frame metadata to the bounded scheduler. It owns transient
/// analysis-session identity, not camera configuration, UI navigation, or
/// persisted scan data.
nonisolated final class AnalysisCoordinator: CameraFrameConsumer, @unchecked Sendable {
    private let lock = NSLock()
    private let scheduler: AnalysisScheduler
    private let performanceMonitor: AnalysisPerformanceMonitor
    private let resultForwarder: AnalysisResultForwarder
    private var activeSessionID: AnalysisSessionID?

    init(
        analyzers: [any AccessibilityAnalyzer] = [],
        performanceStateProvider: any AnalysisPerformanceStateProviding = ProcessInfoAnalysisPerformanceStateProvider(),
        resultHandler: @escaping @Sendable (AnalysisPassResult) -> Void = { _ in }
    ) {
        let resultForwarder = AnalysisResultForwarder(handler: resultHandler)
        let scheduler = AnalysisScheduler(
            analyzers: analyzers,
            resultHandler: resultForwarder.publish
        )
        self.scheduler = scheduler
        self.resultForwarder = resultForwarder
        performanceMonitor = AnalysisPerformanceMonitor(
            provider: performanceStateProvider,
            update: scheduler.updatePerformanceState
        )
        performanceMonitor.start()
    }

    deinit {
        performanceMonitor.stop()
    }

    /// Scan presentation owns the result handler. Replacing it does not alter
    /// camera/session ownership and keeps transient output out of app globals.
    func setResultHandler(_ handler: @escaping @Sendable (AnalysisPassResult) -> Void) {
        resultForwarder.setHandler(handler)
    }

    @discardableResult
    func beginSession() -> AnalysisSessionID {
        let sessionID = AnalysisSessionID()
        lock.lock()
        let previousSessionID = activeSessionID
        activeSessionID = sessionID
        lock.unlock()

        if let previousSessionID {
            scheduler.endSession(previousSessionID)
        }
        scheduler.beginSession(sessionID)
        performanceMonitor.refresh()
        return sessionID
    }

    func endSession() {
        lock.lock()
        let sessionID = activeSessionID
        activeSessionID = nil
        lock.unlock()

        if let sessionID {
            scheduler.endSession(sessionID)
        }
    }

    func cameraFrameSource(
        _ source: CameraFrameSource,
        didOutput sampleBuffer: CMSampleBuffer,
        videoRotationAngle: Double,
        isMirrored: Bool
    ) {
        lock.lock()
        let sessionID = activeSessionID
        lock.unlock()
        guard let sessionID else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let presentationTimeSeconds = timestamp.isValid ? CMTimeGetSeconds(timestamp) : nil
        let dimensions = dimensions(from: sampleBuffer)
        let orientation = AnalysisImageOrientation.from(
            videoRotationAngle: videoRotationAngle,
            isMirrored: isMirrored
        )

        scheduler.submit(
            sessionID: sessionID,
            presentationTimeSeconds: presentationTimeSeconds,
            orientation: orientation,
            dimensions: dimensions,
            payload: AnalysisFramePayload(sampleBuffer: sampleBuffer)
        )
    }

    private func dimensions(from sampleBuffer: CMSampleBuffer) -> AnalysisFrameDimensions? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        return AnalysisFrameDimensions(
            width: CVPixelBufferGetWidth(imageBuffer),
            height: CVPixelBufferGetHeight(imageBuffer)
        )
    }
}

/// A lock-protected bridge from the application-scoped coordinator to the
/// Scan-owned presentation sink. Results are already compact, Sendable values
/// when this bridge is invoked.
private nonisolated final class AnalysisResultForwarder: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: @Sendable (AnalysisPassResult) -> Void

    init(handler: @escaping @Sendable (AnalysisPassResult) -> Void) {
        self.handler = handler
    }

    func setHandler(_ handler: @escaping @Sendable (AnalysisPassResult) -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func publish(_ result: AnalysisPassResult) {
        lock.lock()
        let handler = handler
        lock.unlock()
        handler(result)
    }
}

/// Observes process performance changes centrally rather than asking every
/// analyzer to inspect thermal or Low Power Mode state.
nonisolated final class AnalysisPerformanceMonitor: @unchecked Sendable {
    private let provider: any AnalysisPerformanceStateProviding
    private let update: @Sendable (AnalysisPerformanceState) -> Void
    private var tokens: [NSObjectProtocol] = []

    init(
        provider: any AnalysisPerformanceStateProviding,
        update: @escaping @Sendable (AnalysisPerformanceState) -> Void
    ) {
        self.provider = provider
        self.update = update
    }

    func start() {
        guard tokens.isEmpty else { return }
        let center = NotificationCenter.default
        tokens = [
            center.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.refresh()
            },
            center.addObserver(
                forName: Notification.Name("NSProcessInfoPowerStateDidChangeNotification"),
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.refresh()
            }
        ]
        refresh()
    }

    func stop() {
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens.removeAll()
    }

    func refresh() {
        update(provider.currentState())
    }
}
