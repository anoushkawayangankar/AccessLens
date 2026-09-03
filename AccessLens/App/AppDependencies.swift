import Foundation

/// Creates application-scoped dependencies at the composition root.
///
/// Feature services remain feature-owned. Future camera, analysis, persistence,
/// and export dependencies are introduced only when their milestones begin.
@MainActor
final class AppDependencies {
    let navigator: AppNavigator
    let lifecycleCoordinator: AppLifecycleCoordinator

    init(
        navigator: AppNavigator? = nil,
        lifecycleCoordinator: AppLifecycleCoordinator? = nil
    ) {
        self.navigator = navigator ?? AppNavigator()
        self.lifecycleCoordinator = lifecycleCoordinator ?? AppLifecycleCoordinator()
    }
}
