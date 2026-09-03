import XCTest
@testable import AccessLens

@MainActor
final class AppNavigatorTests: XCTestCase {
    func testNavigateAndGoBackMaintainsTypedPath() {
        let navigator = AppNavigator()
        let scanID = UUID()

        navigator.navigate(to: .savedScans)
        navigator.navigate(to: .scanDetail(id: scanID))
        navigator.goBack()

        XCTAssertEqual(navigator.path, [.savedScans])
    }

    func testReturnToRootRemovesAllRoutes() {
        let navigator = AppNavigator()

        navigator.navigate(to: .scan)
        navigator.navigate(to: .settings)
        navigator.returnToRoot()

        XCTAssertTrue(navigator.path.isEmpty)
    }
}

