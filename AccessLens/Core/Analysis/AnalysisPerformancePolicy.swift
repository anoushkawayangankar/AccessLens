import Foundation

nonisolated enum AnalysisThermalState: Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical

    init(thermalState: ProcessInfo.ThermalState) {
        switch thermalState {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .serious
        }
    }
}

nonisolated struct AnalysisPerformanceState: Equatable, Sendable {
    let thermalState: AnalysisThermalState
    let isLowPowerModeEnabled: Bool

    static let normal = AnalysisPerformanceState(
        thermalState: .nominal,
        isLowPowerModeEnabled: false
    )
}

nonisolated enum AnalysisCadence: Equatable, Sendable {
    case minimumInterval(TimeInterval)
    case suspended

    var minimumInterval: TimeInterval? {
        guard case let .minimumInterval(value) = self else { return nil }
        return value
    }
}

/// Conservative admission policy rather than a frame-rate target. The values
/// are scheduling intervals only; they do not claim measured performance.
nonisolated struct AnalysisPerformancePolicy: Equatable, Sendable {
    let normalMinimumInterval: TimeInterval
    let reducedMinimumInterval: TimeInterval
    let lowPowerMinimumInterval: TimeInterval

    init(
        normalMinimumInterval: TimeInterval = 0.75,
        reducedMinimumInterval: TimeInterval = 1.5,
        lowPowerMinimumInterval: TimeInterval = 1.5
    ) {
        self.normalMinimumInterval = normalMinimumInterval
        self.reducedMinimumInterval = reducedMinimumInterval
        self.lowPowerMinimumInterval = lowPowerMinimumInterval
    }

    func cadence(for state: AnalysisPerformanceState) -> AnalysisCadence {
        switch state.thermalState {
        case .critical:
            return .suspended
        case .serious:
            return .minimumInterval(
                state.isLowPowerModeEnabled
                    ? max(reducedMinimumInterval, lowPowerMinimumInterval)
                    : reducedMinimumInterval
            )
        case .nominal, .fair:
            return .minimumInterval(
                state.isLowPowerModeEnabled ? lowPowerMinimumInterval : normalMinimumInterval
            )
        }
    }
}

nonisolated protocol AnalysisPerformanceStateProviding: AnyObject {
    func currentState() -> AnalysisPerformanceState
}

nonisolated final class ProcessInfoAnalysisPerformanceStateProvider: AnalysisPerformanceStateProviding {
    func currentState() -> AnalysisPerformanceState {
        AnalysisPerformanceState(
            thermalState: AnalysisThermalState(thermalState: ProcessInfo.processInfo.thermalState),
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }
}
