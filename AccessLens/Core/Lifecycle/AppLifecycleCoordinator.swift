import OSLog
import SwiftUI

/// Centralizes app-level lifecycle observation without owning feature behavior.
@MainActor
final class AppLifecycleCoordinator {
    private(set) var state: AppLifecycleState = .inactive

    func handle(scenePhase: ScenePhase) {
        let newState = AppLifecycleState(scenePhase: scenePhase)
        guard newState != state else { return }

        state = newState
        AppLog.lifecycle.debug("App lifecycle changed to \(newState.logValue, privacy: .public)")
    }
}

enum AppLifecycleState: Equatable, Sendable {
    case active
    case inactive
    case background

    init(scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            self = .active
        case .background:
            self = .background
        case .inactive:
            self = .inactive
        @unknown default:
            self = .inactive
        }
    }

    var logValue: String {
        switch self {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        }
    }
}
