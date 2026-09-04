import Foundation
import OSLog

nonisolated struct AnalysisSchedulerSnapshot: Equatable, Sendable {
    let activeSessionID: AnalysisSessionID?
    let inFlightSequence: AnalysisFrameSequence?
    let pendingSequence: AnalysisFrameSequence?
    let pendingReplacementCount: Int
    let cadenceDropCount: Int
    let staleResultDiscardCount: Int

    var inFlightCount: Int { inFlightSequence == nil ? 0 : 1 }
    var pendingCount: Int { pendingSequence == nil ? 0 : 1 }
}

/// Lock-protected bounded scheduler. It admits one analysis task and retains
/// only one newest frame payload while that task runs; it never queues a Task
/// for every camera callback.
nonisolated final class AnalysisScheduler: @unchecked Sendable {
    private struct InFlightWork {
        let workID: UUID
        let frame: AnalysisFrame
        var task: Task<Void, Never>?
    }

    private struct State {
        var activeSessionID: AnalysisSessionID?
        var nextSequence: UInt64 = 0
        var inFlight: InFlightWork?
        var pendingFrame: ScheduledFrame?
        var lastStartedPresentationTime: Double?
        var performanceState = AnalysisPerformanceState.normal
        var pendingReplacementCount = 0
        var cadenceDropCount = 0
        var staleResultDiscardCount = 0
    }

    private struct ScheduledFrame: Sendable {
        let frame: AnalysisFrame
        let payload: AnalysisFramePayload?
    }

    private let lock = NSLock()
    private let analyzers: [any AccessibilityAnalyzer]
    private let performancePolicy: AnalysisPerformancePolicy
    private let resultHandler: @Sendable (AnalysisPassResult) -> Void
    private var state = State()

    init(
        analyzers: [any AccessibilityAnalyzer],
        performancePolicy: AnalysisPerformancePolicy = AnalysisPerformancePolicy(),
        resultHandler: @escaping @Sendable (AnalysisPassResult) -> Void = { _ in }
    ) {
        self.analyzers = analyzers
        self.performancePolicy = performancePolicy
        self.resultHandler = resultHandler
    }

    func beginSession(_ sessionID: AnalysisSessionID) {
        lock.lock()
        let previousTask = state.inFlight?.task
        state.activeSessionID = sessionID
        state.inFlight = nil
        state.pendingFrame = nil
        state.lastStartedPresentationTime = nil
        lock.unlock()

        previousTask?.cancel()
        AppLog.analysis.info("Analysis session started")
    }

    func endSession(_ sessionID: AnalysisSessionID) {
        lock.lock()
        guard state.activeSessionID == sessionID else {
            lock.unlock()
            return
        }

        let task = state.inFlight?.task
        state.activeSessionID = nil
        state.inFlight = nil
        state.pendingFrame = nil
        state.lastStartedPresentationTime = nil
        lock.unlock()

        task?.cancel()
        AppLog.analysis.info("Analysis session ended")
    }

    func updatePerformanceState(_ performanceState: AnalysisPerformanceState) {
        lock.lock()
        guard performanceState != state.performanceState else {
            lock.unlock()
            return
        }

        state.performanceState = performanceState
        let shouldSuspend = performancePolicy.cadence(for: performanceState) == .suspended
        let task = shouldSuspend ? state.inFlight?.task : nil
        if shouldSuspend {
            state.inFlight = nil
            state.pendingFrame = nil
        }
        lock.unlock()

        task?.cancel()
        AppLog.analysis.info("Analysis performance policy changed")
    }

    /// Sequence assignment and admission are synchronous and bounded, so the
    /// capture callback retains at most one in-flight and one pending payload.
    func submit(
        sessionID: AnalysisSessionID,
        presentationTimeSeconds: Double?,
        orientation: AnalysisImageOrientation?,
        dimensions: AnalysisFrameDimensions?,
        payload: AnalysisFramePayload? = nil
    ) {
        lock.lock()
        guard state.activeSessionID == sessionID else {
            lock.unlock()
            return
        }

        state.nextSequence &+= 1
        let frame = AnalysisFrame(
            sessionID: sessionID,
            sequence: AnalysisFrameSequence(rawValue: state.nextSequence),
            presentationTimeSeconds: presentationTimeSeconds,
            orientation: orientation,
            dimensions: dimensions
        )

        let scheduledFrame = ScheduledFrame(frame: frame, payload: payload)

        if performancePolicy.cadence(for: state.performanceState) == .suspended {
            state.cadenceDropCount += 1
            lock.unlock()
            return
        }

        if state.inFlight != nil {
            if state.pendingFrame != nil {
                state.pendingReplacementCount += 1
            }
            state.pendingFrame = scheduledFrame
            lock.unlock()
            return
        }

        startIfPermittedLocked(scheduledFrame)
        lock.unlock()
    }

    func snapshot() -> AnalysisSchedulerSnapshot {
        lock.lock()
        defer { lock.unlock() }

        return AnalysisSchedulerSnapshot(
            activeSessionID: state.activeSessionID,
            inFlightSequence: state.inFlight?.frame.sequence,
            pendingSequence: state.pendingFrame?.frame.sequence,
            pendingReplacementCount: state.pendingReplacementCount,
            cadenceDropCount: state.cadenceDropCount,
            staleResultDiscardCount: state.staleResultDiscardCount
        )
    }

    private func startIfPermittedLocked(_ scheduledFrame: ScheduledFrame) {
        let frame = scheduledFrame.frame
        guard permits(frame) else {
            state.cadenceDropCount += 1
            return
        }

        let workID = UUID()
        let context = AnalysisContext(frame: frame, payload: scheduledFrame.payload)
        state.lastStartedPresentationTime = frame.presentationTimeSeconds
        state.inFlight = InFlightWork(workID: workID, frame: frame, task: nil)

        let analyzers = analyzers
        let task = Task { [weak self, analyzers] in
            let execution = await Self.execute(analyzers: analyzers, context: context)
            self?.complete(workID: workID, frame: frame, execution: execution)
        }
        state.inFlight?.task = task
    }

    private func permits(_ frame: AnalysisFrame) -> Bool {
        guard let minimumInterval = performancePolicy.cadence(for: state.performanceState).minimumInterval else {
            return false
        }
        guard let previousTime = state.lastStartedPresentationTime,
              let frameTime = frame.presentationTimeSeconds else {
            return true
        }
        return frameTime - previousTime >= minimumInterval
    }

    private func complete(
        workID: UUID,
        frame: AnalysisFrame,
        execution: AnalysisExecution
    ) {
        var resultToPublish: AnalysisPassResult?

        lock.lock()
        guard state.activeSessionID == frame.sessionID,
              state.inFlight?.workID == workID else {
            state.staleResultDiscardCount += 1
            lock.unlock()
            AppLog.analysis.debug("Discarded stale analysis result")
            return
        }

        state.inFlight = nil
        if case let .completed(output) = execution {
            resultToPublish = AnalysisPassResult(
                sessionID: frame.sessionID,
                frameSequence: frame.sequence,
                observations: output.observations,
                textObservations: output.textObservations,
                candidates: output.candidates,
                failures: output.failures
            )
        }

        if let pendingFrame = state.pendingFrame {
            state.pendingFrame = nil
            startIfPermittedLocked(pendingFrame)
        }
        lock.unlock()

        if let resultToPublish {
            resultHandler(resultToPublish)
        }
    }

    private static func execute(
        analyzers: [any AccessibilityAnalyzer],
        context: AnalysisContext
    ) async -> AnalysisExecution {
        var observations: [NormalizedObservation] = []
        var textObservations: [RecognizedTextObservation] = []
        var candidates: [FindingCandidate] = []
        var failures: [AnalysisFailure] = []

        for analyzer in analyzers {
            if Task.isCancelled {
                return .cancelled
            }

            do {
                let output = try await analyzer.analyze(context)
                if Task.isCancelled {
                    return .cancelled
                }
                observations.append(contentsOf: output.observations)
                textObservations.append(contentsOf: output.textObservations)
                candidates.append(contentsOf: output.candidates)
            } catch is CancellationError {
                return .cancelled
            } catch {
                failures.append(
                    AnalysisFailure(
                        analyzerID: analyzer.identifier,
                        error: .analyzerFailed(analyzer.identifier)
                    )
                )
                AppLog.analysis.error("Analyzer failed: \(analyzer.identifier.rawValue, privacy: .public)")
            }
        }

        return .completed(AnalysisExecutionOutput(
            observations: observations,
            textObservations: textObservations,
            candidates: candidates,
            failures: failures
        ))
    }
}

private enum AnalysisExecution {
    case completed(AnalysisExecutionOutput)
    case cancelled
}

private struct AnalysisExecutionOutput {
    let observations: [NormalizedObservation]
    let textObservations: [RecognizedTextObservation]
    let candidates: [FindingCandidate]
    let failures: [AnalysisFailure]
}
