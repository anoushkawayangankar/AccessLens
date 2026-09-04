/// Technical camera failures. The feature maps these to presentation-safe
/// messages rather than exposing AVFoundation errors or descriptions.
nonisolated enum CameraError: Error, Equatable, Sendable {
    case noCameraDevice
    case cannotCreateInput
    case cannotAddInput
    case cannotAddOutput
    case sessionRuntimeFailure

    @MainActor
    var userFacingError: UserFacingError {
        switch self {
        case .noCameraDevice:
            UserFacingError(
                title: "Camera unavailable",
                message: "This device does not have a camera available for AccessLens."
            )
        case .cannotCreateInput, .cannotAddInput, .cannotAddOutput, .sessionRuntimeFailure:
            UserFacingError(
                title: "Camera unavailable",
                message: "AccessLens could not start the camera. Try again or return to the home screen."
            )
        }
    }

    var logValue: String {
        switch self {
        case .noCameraDevice: "noCameraDevice"
        case .cannotCreateInput: "cannotCreateInput"
        case .cannotAddInput: "cannotAddInput"
        case .cannotAddOutput: "cannotAddOutput"
        case .sessionRuntimeFailure: "sessionRuntimeFailure"
        }
    }
}

nonisolated enum CameraSessionState: Equatable, Sendable {
    case idle
    case configuring
    case ready
    case running
    case interrupted
    case unavailable(CameraError)
}
