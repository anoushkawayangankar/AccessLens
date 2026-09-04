import Combine

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published private(set) var currentPage: OnboardingPage = .welcome

    private let onboardingState: OnboardingState

    init(onboardingState: OnboardingState) {
        self.onboardingState = onboardingState
    }

    var currentStep: Int {
        currentPage.rawValue + 1
    }

    var totalSteps: Int {
        OnboardingPage.allCases.count
    }

    var canGoBack: Bool {
        currentPage != .welcome
    }

    var isFinalPage: Bool {
        currentPage == .cameraPreparation
    }

    var primaryActionTitle: String {
        isFinalPage ? "Continue to AccessLens" : "Continue"
    }

    func continueOrComplete() {
        guard !isFinalPage else {
            onboardingState.complete()
            return
        }

        currentPage = OnboardingPage(rawValue: currentPage.rawValue + 1) ?? currentPage
    }

    func goBack() {
        guard canGoBack else { return }
        currentPage = OnboardingPage(rawValue: currentPage.rawValue - 1) ?? currentPage
    }
}

