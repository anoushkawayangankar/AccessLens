import Foundation

/// Creates application-scoped dependencies at the composition root.
///
/// Feature services remain feature-owned. Future camera, analysis, persistence,
/// and export dependencies are introduced only when their milestones begin.
@MainActor
final class AppDependencies {
    let navigator: AppNavigator
    let lifecycleCoordinator: AppLifecycleCoordinator
    let onboardingState: OnboardingState

    init(
        navigator: AppNavigator? = nil,
        lifecycleCoordinator: AppLifecycleCoordinator? = nil,
        onboardingState: OnboardingState? = nil
    ) {
        self.navigator = navigator ?? AppNavigator()
        self.lifecycleCoordinator = lifecycleCoordinator ?? AppLifecycleCoordinator()
        self.onboardingState = onboardingState ?? OnboardingState(
            store: UserDefaultsOnboardingCompletionStore(defaults: .standard)
        )
    }

    /// Creates process-specific dependencies without exposing test controls in
    /// the product UI. Release builds always use the local UserDefaults store.
    static func forApplicationLaunch(arguments: [String]) -> AppDependencies {
        #if DEBUG
        if let isComplete = AppLaunchConfiguration.onboardingCompletionOverride(arguments: arguments) {
            return AppDependencies(
                onboardingState: OnboardingState(
                    store: InMemoryOnboardingCompletionStore(isCompleted: isComplete)
                )
            )
        }
        #endif

        return AppDependencies()
    }
}

private enum AppLaunchConfiguration {
    private static let onboardingStateArgument = "-accesslens-onboarding-state"

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
}
