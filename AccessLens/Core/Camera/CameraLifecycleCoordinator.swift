import SwiftUI

/// Translates application scene changes into camera-session policy updates.
/// It deliberately contains no session configuration or UI state.
@MainActor
final class CameraLifecycleCoordinator {
    private let sessionController: CameraSessionController

    init(sessionController: CameraSessionController) {
        self.sessionController = sessionController
    }

    func handle(scenePhase: ScenePhase) {
        sessionController.setApplicationIsActive(scenePhase == .active)
    }
}
