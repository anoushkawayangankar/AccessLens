/// Pure, deterministic policy for deciding whether a configured session may
/// run. AVCaptureSession ownership remains in CameraSessionController.
nonisolated struct CameraRuntimePolicy: Equatable, Sendable {
    var isScanVisible = false
    var isApplicationActive = false
    var isAuthorized = false
    var isInterrupted = false

    var shouldRun: Bool {
        isScanVisible && isApplicationActive && isAuthorized && !isInterrupted
    }
}
