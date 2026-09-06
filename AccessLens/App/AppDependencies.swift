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
    /// DEBUG launch composition may provide a deterministic presentation value
    /// for UI tests. Production composition always leaves this empty.
    let scanFindingOverride: [AccessibilityFinding]
    let scanAnalysisPresentationOverride: Bool

    init(
        navigator: AppNavigator? = nil,
        lifecycleCoordinator: AppLifecycleCoordinator? = nil,
        onboardingState: OnboardingState? = nil,
        cameraAuthorizationService: (any CameraAuthorizationProviding)? = nil,
        cameraSessionController: CameraSessionController? = nil,
        analysisCoordinator: AnalysisCoordinator? = nil,
        scanFindingOverride: [AccessibilityFinding] = [],
        scanAnalysisPresentationOverride: Bool = false
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
        self.scanFindingOverride = scanFindingOverride
        self.scanAnalysisPresentationOverride = scanAnalysisPresentationOverride
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

        let scanFindingOverride = AppLaunchConfiguration.scanFindingOverride(arguments: arguments)
        let scanAnalysisPresentationOverride = AppLaunchConfiguration.scanAnalysisPresentationOverride(arguments: arguments)
        if let authorization = AppLaunchConfiguration.cameraAuthorizationOverride(arguments: arguments) {
            return AppDependencies(
                onboardingState: onboardingState,
                cameraAuthorizationService: InMemoryCameraAuthorizationService(
                    authorization: authorization
                ),
                scanFindingOverride: scanFindingOverride,
                scanAnalysisPresentationOverride: scanAnalysisPresentationOverride
            )
        }

        if let onboardingState {
            return AppDependencies(
                onboardingState: onboardingState,
                scanFindingOverride: scanFindingOverride,
                scanAnalysisPresentationOverride: scanAnalysisPresentationOverride
            )
        }
        #endif

        return AppDependencies()
    }
}

private enum AppLaunchConfiguration {
    private static let onboardingStateArgument = "-accesslens-onboarding-state"
    private static let cameraAuthorizationArgument = "-accesslens-camera-authorization"
    private static let scanFindingsArgument = "-accesslens-scan-findings"

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

    static func scanFindingOverride(arguments: [String]) -> [AccessibilityFinding] {
        guard let argumentIndex = arguments.firstIndex(of: scanFindingsArgument) else {
            return []
        }
        let valueIndex = arguments.index(after: argumentIndex)
        guard valueIndex < arguments.endIndex, arguments[valueIndex] == "stable-low-contrast" else {
            return []
        }

        guard let sessionUUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111"),
              let findingID = UUID(uuidString: "22222222-2222-2222-2222-222222222222") else {
            return []
        }
        let sessionID = AnalysisSessionID(rawValue: sessionUUID)
        return [AccessibilityFinding(
            id: findingID,
            category: .potentialLowContrastText,
            title: "Potential low contrast",
            explanation: "Text in this area may be difficult to distinguish from its background.",
            evidenceSummary: "Deterministic UI-test finding.",
            evidenceStrength: .moderate,
            region: NormalizedRegion(x: 0.2, y: 0.2, width: 0.3, height: 0.1),
            firstObservedTime: 1,
            lastObservedTime: 3,
            supportingFrameRange: FindingFrameRange(
                first: AnalysisFrameSequence(rawValue: 1),
                last: AnalysisFrameSequence(rawValue: 3)
            ),
            supportingObservationCount: 3,
            sessionID: sessionID,
            sourceAnalyzerIDs: [
                AnalyzerIdentifier(rawValue: "vision.text.v1"),
                AnalyzerIdentifier(rawValue: "vision.visual-contrast.v1")
            ],
            relevantText: "EXIT",
            estimatedContrastRatio: ContrastRatio(lighterLuminance: 0.2, darkerLuminance: 0.02)
        )]
    }

    static func scanAnalysisPresentationOverride(arguments: [String]) -> Bool {
        guard let argumentIndex = arguments.firstIndex(of: scanFindingsArgument) else {
            return false
        }
        let valueIndex = arguments.index(after: argumentIndex)
        guard valueIndex < arguments.endIndex else { return false }
        return ["stable-low-contrast", "analyzing-empty"].contains(arguments[valueIndex])
    }
}
