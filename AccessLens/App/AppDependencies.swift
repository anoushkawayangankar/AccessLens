import Foundation

/// Creates application-scoped dependencies at the composition root.
///
/// Feature services remain feature-owned. Camera runtime dependencies are
/// composed here; analysis, persistence, and export remain future work.
@MainActor
final class AppDependencies {
    let navigator: AppNavigator
    let lifecycleCoordinator: AppLifecycleCoordinator
    let onboardingState: OnboardingState
    let cameraAuthorizationService: any CameraAuthorizationProviding
    let cameraSessionController: CameraSessionController
    let cameraLifecycleCoordinator: CameraLifecycleCoordinator
    let analysisCoordinator: AnalysisCoordinator

    init(
        navigator: AppNavigator? = nil,
        lifecycleCoordinator: AppLifecycleCoordinator? = nil,
        onboardingState: OnboardingState? = nil,
        cameraAuthorizationService: (any CameraAuthorizationProviding)? = nil,
        cameraSessionController: CameraSessionController? = nil,
        analysisCoordinator: AnalysisCoordinator? = nil
    ) {
        self.navigator = navigator ?? AppNavigator()
        self.lifecycleCoordinator = lifecycleCoordinator ?? AppLifecycleCoordinator()
        self.onboardingState = onboardingState ?? OnboardingState(
            store: UserDefaultsOnboardingCompletionStore(defaults: .standard)
        )
        self.cameraAuthorizationService = cameraAuthorizationService ?? CameraAuthorizationService()
        let sessionController = cameraSessionController ?? CameraSessionController()
        self.cameraSessionController = sessionController
        self.cameraLifecycleCoordinator = CameraLifecycleCoordinator(sessionController: sessionController)
        let coordinator = analysisCoordinator ?? AnalysisCoordinator(
            analyzers: [VisionTextAnalyzer(), VisualContrastAnalyzer()]
        )
        self.analysisCoordinator = coordinator
        sessionController.frameSource.consumer = coordinator
    }

    /// Creates process-specific dependencies without exposing test controls in
    /// the product UI. Release builds always use the local UserDefaults store.
    static func forApplicationLaunch(arguments: [String]) -> AppDependencies {
        #if DEBUG
        let onboardingState: OnboardingState?
        if let isComplete = AppLaunchConfiguration.onboardingCompletionOverride(arguments: arguments) {
            onboardingState = OnboardingState(
                store: InMemoryOnboardingCompletionStore(isCompleted: isComplete)
            )
        } else {
            onboardingState = nil
        }

        if let authorization = AppLaunchConfiguration.cameraAuthorizationOverride(arguments: arguments) {
            return AppDependencies(
                onboardingState: onboardingState,
                cameraAuthorizationService: InMemoryCameraAuthorizationService(
                    authorization: authorization
                )
            )
        }

        if let onboardingState {
            return AppDependencies(onboardingState: onboardingState)
        }
        #endif

        return AppDependencies()
    }
}

private enum AppLaunchConfiguration {
    private static let onboardingStateArgument = "-accesslens-onboarding-state"
    private static let cameraAuthorizationArgument = "-accesslens-camera-authorization"

    static func onboardingCompletionOverride(arguments: [String]) -> Bool? {
        guard let argumentIndex = arguments.firstIndex(of: onboardingStateArgument) else {
            return nil
        }

        let valueIndex = arguments.index(after: argumentIndex)
        guard valueIndex < arguments.endIndex else { return nil }

        switch arguments[valueIndex] {
        case "complete":
            return true
        case "incomplete":
            return false
        default:
            return nil
        }
    }

    static func cameraAuthorizationOverride(arguments: [String]) -> CameraAuthorizationState? {
        guard let argumentIndex = arguments.firstIndex(of: cameraAuthorizationArgument) else {
            return nil
        }

        let valueIndex = arguments.index(after: argumentIndex)
        guard valueIndex < arguments.endIndex else { return nil }

        switch arguments[valueIndex] {
        case "not-determined":
            return .notDetermined
        case "authorized":
            return .authorized
        case "denied":
            return .denied
        case "restricted":
            return .restricted
        default:
            return nil
        }
    }
}
