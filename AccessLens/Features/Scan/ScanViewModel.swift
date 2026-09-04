import Combine
import Foundation

enum CameraPermissionPresentation: Equatable, Sendable {
    case requestPermission
    case cameraReady
    case denied
    case restricted

    init(authorization: CameraAuthorizationState) {
        switch authorization {
        case .notDetermined: self = .requestPermission
        case .authorized: self = .cameraReady
        case .denied: self = .denied
        case .restricted: self = .restricted
        }
    }
}

@MainActor
final class ScanViewModel: ObservableObject {
    @Published private(set) var authorization: CameraAuthorizationState
    @Published private(set) var isRequestingPermission = false
    @Published private(set) var settingsCouldNotOpen = false

    private let authorizationService: any CameraAuthorizationProviding
    private let sessionController: CameraSessionController

    init(
        authorizationService: any CameraAuthorizationProviding,
        sessionController: CameraSessionController
    ) {
        self.authorizationService = authorizationService
        self.sessionController = sessionController
        authorization = authorizationService.currentAuthorization()
        sessionController.setAuthorization(authorization)
    }

    var permissionPresentation: CameraPermissionPresentation {
        CameraPermissionPresentation(authorization: authorization)
    }

    func appear() {
        authorization = authorizationService.currentAuthorization()
        sessionController.setAuthorization(authorization)
        sessionController.setScanVisible(true)
    }

    func disappear() {
        sessionController.setScanVisible(false)
    }

    func requestCameraAccess() async {
        guard authorization == .notDetermined, !isRequestingPermission else { return }

        isRequestingPermission = true
        let updatedAuthorization = await authorizationService.requestAuthorization()
        authorization = updatedAuthorization
        isRequestingPermission = false
        sessionController.setAuthorization(updatedAuthorization)
    }

    func noteSettingsCouldNotOpen() {
        settingsCouldNotOpen = true
    }
}
