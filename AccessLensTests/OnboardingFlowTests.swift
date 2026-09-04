import XCTest
@testable import AccessLens

@MainActor
final class OnboardingFlowTests: XCTestCase {
    func testFlowStartsOnFirstPage() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.currentPage, .welcome)
        XCTAssertEqual(viewModel.currentStep, 1)
        XCTAssertFalse(viewModel.canGoBack)
    }

    func testContinueAdvancesAndBackReturnsWithinValidBounds() {
        let viewModel = makeViewModel()

        viewModel.goBack()
        XCTAssertEqual(viewModel.currentPage, .welcome)

        viewModel.continueOrComplete()
        XCTAssertEqual(viewModel.currentPage, .findings)
        XCTAssertTrue(viewModel.canGoBack)

        viewModel.goBack()
        XCTAssertEqual(viewModel.currentPage, .welcome)
    }

    func testFinalCompletionTransitionsToHomeAndCannotAdvanceBeyondFinalPage() {
        let store = InMemoryOnboardingCompletionStore()
        let state = OnboardingState(store: store)
        let viewModel = OnboardingViewModel(onboardingState: state)

        for _ in 0..<(OnboardingPage.allCases.count - 1) {
            viewModel.continueOrComplete()
        }

        XCTAssertEqual(viewModel.currentPage, .cameraPreparation)
        XCTAssertTrue(viewModel.isFinalPage)

        viewModel.continueOrComplete()
        viewModel.continueOrComplete()

        XCTAssertTrue(state.isCompleted)
        XCTAssertEqual(state.destination, .home)
        XCTAssertEqual(viewModel.currentPage, .cameraPreparation)
    }

    func testRootDestinationReflectsStoredCompletionState() {
        let incompleteState = OnboardingState(
            store: InMemoryOnboardingCompletionStore(isCompleted: false)
        )
        let completedState = OnboardingState(
            store: InMemoryOnboardingCompletionStore(isCompleted: true)
        )

        XCTAssertEqual(incompleteState.destination, .onboarding)
        XCTAssertEqual(completedState.destination, .home)
    }

    private func makeViewModel() -> OnboardingViewModel {
        OnboardingViewModel(
            onboardingState: OnboardingState(
                store: InMemoryOnboardingCompletionStore()
            )
        )
    }
}
