@preconcurrency import AVFoundation
import CoreVideo
import Foundation
import OSLog

/// Connects camera-frame metadata to the bounded scheduler. It owns transient
/// analysis-session identity, not camera configuration, UI navigation, or
/// persisted scan data.
nonisolated final class AnalysisCoordinator: CameraFrameConsumer, @unchecked Sendable {
    private let scheduler: AnalysisScheduler
    private let performanceMonitor: AnalysisPerformanceMonitor
    private let resultForwarder: AnalysisResultForwarder
    private let sessionGate: AnalysisSessionGate
    private let findingStabilizer: AccessibilityFindingStabilizer

    init(
        analyzers: [any AccessibilityAnalyzer] = [],
        performanceStateProvider: any AnalysisPerformanceStateProviding = ProcessInfoAnalysisPerformanceStateProvider(),
        findingStabilizer: AccessibilityFindingStabilizer = AccessibilityFindingStabilizer(),
        resultHandler: @escaping @Sendable (StabilizedAnalysisResult) -> Void = { _ in }
    ) {
        let resultForwarder = AnalysisResultForwarder(handler: resultHandler)
        let sessionGate = AnalysisSessionGate()
        let scheduler = AnalysisScheduler(
            analyzers: analyzers,
            resultHandler: { result in
                guard sessionGate.isActive(result.sessionID) else {
                    AppLog.analysis.debug("Rejected stale finding evidence")
                    return
                }
                let currentTime = result.candidates.compactMap(\.presentationTimeSeconds).max()
                let stabilized = findingStabilizer.ingest(
                    result.candidates,
                    sessionID: result.sessionID,
                    currentTime: currentTime
                )
                guard sessionGate.isActive(result.sessionID) else {
                    AppLog.analysis.debug("Rejected stale stabilized result")
                    return
                }
                resultForwarder.publish(StabilizedAnalysisResult(
                    sessionID: result.sessionID,
                    frameSequence: result.frameSequence,
                    findings: stabilized.findings,
                    newlyPromotedFindingIDs: stabilized.newlyPromotedFindingIDs,
                    failures: result.failures
                ))
            }
        )
        self.scheduler = scheduler
        self.resultForwarder = resultForwarder
        self.sessionGate = sessionGate
        self.findingStabilizer = findingStabilizer
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
    func setResultHandler(_ handler: @escaping @Sendable (StabilizedAnalysisResult) -> Void) {
        resultForwarder.setHandler(handler)
    }

    @discardableResult
    func beginSession() -> AnalysisSessionID {
        let sessionID = AnalysisSessionID()
        let previousSessionID = sessionGate.replaceActiveSession(with: sessionID)

        if let previousSessionID {
            scheduler.endSession(previousSessionID)
        }
        scheduler.beginSession(sessionID)
        findingStabilizer.beginSession(sessionID)
        performanceMonitor.refresh()
        return sessionID
    }

    func endSession() {
        _ = endActiveSession(logCompletion: false)
    }

    /// Stops admitting work before ending the scheduler and returns the last
    /// compact, stable evidence snapshot. Once this begins, no late analyzer
    /// output can reach a completed Scan review.
    func completeSession() -> [AccessibilityFinding] {
        endActiveSession(logCompletion: true)
    }

    private func endActiveSession(logCompletion: Bool) -> [AccessibilityFinding] {
        let sessionID = sessionGate.clearActiveSession()

        if let sessionID {
            scheduler.endSession(sessionID)
            let findings = findingStabilizer.findings(for: sessionID)
            findingStabilizer.endSession(sessionID)
            if logCompletion {
                AppLog.analysis.info("Analysis session completed")
            }
            return findings
        }
        return []
    }

    func cameraFrameSource(
        _ source: CameraFrameSource,
        didOutput sampleBuffer: CMSampleBuffer,
        videoRotationAngle: Double,
        isMirrored: Bool
    ) {
        let sessionID = sessionGate.activeSessionID
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

    /// RoomPlan owns the camera on LiDAR-capable devices. Its classified
    /// surface snapshot and current captured image enter the same bounded
    /// scheduler used by OCR and contrast; no second capture session runs.
    func roomPlanDidOutput(
        imageBuffer: CVPixelBuffer,
        presentationTimeSeconds: TimeInterval,
        orientation: AnalysisImageOrientation,
        passageSurfaces: [PassageSurfaceEvidence]
    ) {
        guard let sessionID = sessionGate.activeSessionID else { return }
        scheduler.submit(
            sessionID: sessionID,
            presentationTimeSeconds: presentationTimeSeconds,
            orientation: orientation,
            dimensions: AnalysisFrameDimensions(
                width: CVPixelBufferGetWidth(imageBuffer),
                height: CVPixelBufferGetHeight(imageBuffer)
            ),
            payload: AnalysisFramePayload(imageBuffer: imageBuffer, passageSurfaces: passageSurfaces)
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
    private var handler: @Sendable (StabilizedAnalysisResult) -> Void

    init(handler: @escaping @Sendable (StabilizedAnalysisResult) -> Void) {
        self.handler = handler
    }

    func setHandler(_ handler: @escaping @Sendable (StabilizedAnalysisResult) -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func publish(_ result: StabilizedAnalysisResult) {
        lock.lock()
        let handler = handler
        lock.unlock()
        handler(result)
    }
}

/// Synchronously guards the coordinator's current session around result work.
/// It ensures a completed scheduler pass cannot publish after Scan has ended
/// or after a newer session replaces it.
private nonisolated final class AnalysisSessionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var storedSessionID: AnalysisSessionID?

    var activeSessionID: AnalysisSessionID? {
        lock.lock()
        defer { lock.unlock() }
        return storedSessionID
    }

    func replaceActiveSession(with sessionID: AnalysisSessionID) -> AnalysisSessionID? {
        lock.lock()
        let previous = storedSessionID
        storedSessionID = sessionID
        lock.unlock()
        return previous
    }

    func clearActiveSession() -> AnalysisSessionID? {
        lock.lock()
        let previous = storedSessionID
        storedSessionID = nil
        lock.unlock()
        return previous
    }

    func isActive(_ sessionID: AnalysisSessionID) -> Bool {
        activeSessionID == sessionID
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
