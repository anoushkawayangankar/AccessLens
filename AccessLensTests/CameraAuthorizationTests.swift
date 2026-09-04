@preconcurrency import AVFoundation
import XCTest
@testable import AccessLens

final class CameraAuthorizationTests: XCTestCase {
    func testAVFoundationAuthorizationStatusMapsToProductStates() {
        XCTAssertEqual(CameraAuthorizationState(status: .notDetermined), .notDetermined)
        XCTAssertEqual(CameraAuthorizationState(status: .authorized), .authorized)
        XCTAssertEqual(CameraAuthorizationState(status: .denied), .denied)
        XCTAssertEqual(CameraAuthorizationState(status: .restricted), .restricted)
    }

    func testInMemoryAuthorizationServiceReturnsItsConfiguredRequestResult() async {
        let service = InMemoryCameraAuthorizationService(
            authorization: .notDetermined,
            requestedAuthorization: .authorized
        )

        XCTAssertEqual(service.currentAuthorization(), .notDetermined)
        let requestedAuthorization = await service.requestAuthorization()
        XCTAssertEqual(requestedAuthorization, .authorized)
        XCTAssertEqual(service.currentAuthorization(), .authorized)
    }
}
