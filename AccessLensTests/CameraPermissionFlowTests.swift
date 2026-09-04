import XCTest
@testable import AccessLens

@MainActor
final class CameraPermissionFlowTests: XCTestCase {
    func testPermissionPresentationMapsEveryAuthorizationState() {
        XCTAssertEqual(
            CameraPermissionPresentation(authorization: .notDetermined),
            .requestPermission
        )
        XCTAssertEqual(
            CameraPermissionPresentation(authorization: .authorized),
            .cameraReady
        )
        XCTAssertEqual(CameraPermissionPresentation(authorization: .denied), .denied)
        XCTAssertEqual(CameraPermissionPresentation(authorization: .restricted), .restricted)
    }

    func testRequestingPermissionUpdatesScanFlowToAuthorized() async {
        let service = InMemoryCameraAuthorizationService(
            authorization: .notDetermined,
            requestedAuthorization: .authorized
        )
        let viewModel = ScanViewModel(
            authorizationService: service,
            sessionController: CameraSessionController()
        )

        await viewModel.requestCameraAccess()

        XCTAssertEqual(viewModel.authorization, .authorized)
        XCTAssertEqual(viewModel.permissionPresentation, .cameraReady)
    }
}
