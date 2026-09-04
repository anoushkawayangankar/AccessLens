import XCTest
@testable import AccessLens

@MainActor
final class AnalysisCompositionTests: XCTestCase {
    func testApplicationCompositionConnectsCameraFramesToAnalysisCoordinator() {
        let dependencies = AppDependencies(
            onboardingState: OnboardingState(
                store: InMemoryOnboardingCompletionStore(isCompleted: true)
            )
        )

        XCTAssertNotNil(dependencies.cameraSessionController.frameSource.consumer)
    }
}
