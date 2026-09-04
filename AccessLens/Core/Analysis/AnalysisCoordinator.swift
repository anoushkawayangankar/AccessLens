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
    private var activeSessionID: AnalysisSessionID?

    init(
        analyzers: [any AccessibilityAnalyzer] = [],
        performanceStateProvider: any AnalysisPerformanceStateProviding = ProcessInfoAnalysisPerformanceStateProvider(),
        resultHandler: @escaping @Sendable (AnalysisPassResult) -> Void = { _ in }
    ) {
        let scheduler = AnalysisScheduler(analyzers: analyzers, resultHandler: resultHandler)
        self.scheduler = scheduler
        performanceMonitor = AnalysisPerformanceMonitor(
            provider: performanceStateProvider,
            update: scheduler.updatePerformanceState
        )
        performanceMonitor.start()
    }

    deinit {
        performanceMonitor.stop()
    }

    func beginSession() {
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
            dimensions: dimensions
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
