import SwiftUI
import XCTest
@testable import AccessLens

@MainActor
final class AppLifecycleStateTests: XCTestCase {
    func testScenePhaseMappingIsExplicit() {
        XCTAssertEqual(AppLifecycleState(scenePhase: .active), .active)
        XCTAssertEqual(AppLifecycleState(scenePhase: .inactive), .inactive)
        XCTAssertEqual(AppLifecycleState(scenePhase: .background), .background)
    }

    func testCoordinatorUpdatesStateOnlyForNewPhase() {
        let coordinator = AppLifecycleCoordinator()

        coordinator.handle(scenePhase: .active)
        coordinator.handle(scenePhase: .active)

        XCTAssertEqual(coordinator.state, .active)
    }
}

