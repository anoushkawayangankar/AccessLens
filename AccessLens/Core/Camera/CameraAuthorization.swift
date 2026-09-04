@preconcurrency import AVFoundation

/// Product-level authorization states. SwiftUI and feature code do not need
/// to interpret AVFoundation's authorization enum directly.
nonisolated enum CameraAuthorizationState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted

    init(status: AVAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .authorized:
            self = .authorized
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        @unknown default:
            self = .restricted
        }
    }
}

/// Isolates permission APIs from the Scan feature and enables deterministic
/// authorization-flow tests without invoking the system alert.
nonisolated protocol CameraAuthorizationProviding: AnyObject {
    func currentAuthorization() -> CameraAuthorizationState
    func requestAuthorization() async -> CameraAuthorizationState
}

nonisolated final class CameraAuthorizationService: CameraAuthorizationProviding {
    func currentAuthorization() -> CameraAuthorizationState {
        CameraAuthorizationState(status: AVCaptureDevice.authorizationStatus(for: .video))
    }

    func requestAuthorization() async -> CameraAuthorizationState {
        let currentState = currentAuthorization()
        guard currentState == .notDetermined else { return currentState }

        let wasGranted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }

        return wasGranted ? .authorized : currentAuthorization()
    }
}

#if DEBUG
/// Used only by tests, previews, and DEBUG launch configuration. It never
/// supplies a camera feed and is not selectable from product UI.
nonisolated final class InMemoryCameraAuthorizationService: CameraAuthorizationProviding {
    private var authorization: CameraAuthorizationState
    private let requestedAuthorization: CameraAuthorizationState

    init(
        authorization: CameraAuthorizationState,
        requestedAuthorization: CameraAuthorizationState? = nil
    ) {
        self.authorization = authorization
        self.requestedAuthorization = requestedAuthorization
            ?? (authorization == .notDetermined ? .authorized : authorization)
    }

    func currentAuthorization() -> CameraAuthorizationState {
        authorization
    }

    func requestAuthorization() async -> CameraAuthorizationState {
        authorization = requestedAuthorization
        return authorization
    }
}
#endif
