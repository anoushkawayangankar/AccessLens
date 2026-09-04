import XCTest
@testable import AccessLens

final class CameraRuntimePolicyTests: XCTestCase {
    func testSessionRunsOnlyWhenAllRequiredConditionsAreMet() {
        var policy = CameraRuntimePolicy()

        XCTAssertFalse(policy.shouldRun)

        policy.isScanVisible = true
        policy.isApplicationActive = true
        policy.isAuthorized = true

        XCTAssertTrue(policy.shouldRun)
    }

    func testRepeatedLifecycleInputsRemainIdempotent() {
        var policy = runningPolicy()

        policy.isScanVisible = true
        policy.isScanVisible = true
        policy.isApplicationActive = true
        policy.isApplicationActive = true

        XCTAssertTrue(policy.shouldRun)
    }

    func testLeavingScanPreventsRunning() {
        var policy = runningPolicy()

        policy.isScanVisible = false

        XCTAssertFalse(policy.shouldRun)
    }

    func testBackgroundPreventsRunningUntilApplicationReturnsActive() {
        var policy = runningPolicy()

        policy.isApplicationActive = false
        XCTAssertFalse(policy.shouldRun)

        policy.isApplicationActive = true
        XCTAssertTrue(policy.shouldRun)
    }

    func testInterruptionPreventsRunningUntilItEnds() {
        var policy = runningPolicy()

        policy.isInterrupted = true
        XCTAssertFalse(policy.shouldRun)

        policy.isInterrupted = false
        XCTAssertTrue(policy.shouldRun)
    }

    func testDeniedAuthorizationNeverPermitsRunning() {
        var policy = runningPolicy()

        policy.isAuthorized = false

        XCTAssertFalse(policy.shouldRun)
    }

    private func runningPolicy() -> CameraRuntimePolicy {
        CameraRuntimePolicy(
            isScanVisible: true,
            isApplicationActive: true,
            isAuthorized: true,
            isInterrupted: false
        )
    }
}
