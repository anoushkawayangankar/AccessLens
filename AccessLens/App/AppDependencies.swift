import Foundation

/// Creates application-scoped dependencies at the composition root.
///
/// Feature services remain feature-owned. Camera runtime dependencies are
/// composed here alongside the local completed-scan repository.
@MainActor
final class AppDependencies {
    let navigator: AppNavigator
    let lifecycleCoordinator: AppLifecycleCoordinator
    let onboardingState: OnboardingState
    let cameraAuthorizationService: any CameraAuthorizationProviding
    let cameraSessionController: CameraSessionController
    let cameraLifecycleCoordinator: CameraLifecycleCoordinator
    let analysisCoordinator: AnalysisCoordinator
    let completedScanRepository: any CompletedScanRepository
    let guidanceProvider: any AccessibilityGuidanceProviding
    /// DEBUG launch composition may provide deterministic evidence for one
    /// test scan. Production composition always returns an empty array.
    private let scanFindingOverrideProvider: ScanFindingOverrideProvider
    let scanAnalysisPresentationOverride: Bool

    init(
        navigator: AppNavigator? = nil,
        lifecycleCoordinator: AppLifecycleCoordinator? = nil,
        onboardingState: OnboardingState? = nil,
        cameraAuthorizationService: (any CameraAuthorizationProviding)? = nil,
        cameraSessionController: CameraSessionController? = nil,
        analysisCoordinator: AnalysisCoordinator? = nil,
        completedScanRepository: (any CompletedScanRepository)? = nil,
        guidanceProvider: any AccessibilityGuidanceProviding = DeterministicAccessibilityGuidanceProvider(),
        scanFindingOverrides: [[AccessibilityFinding]] = [],
        scanAnalysisPresentationOverride: Bool = false
    ) {
        self.navigator = navigator ?? AppNavigator()
        self.guidanceProvider = guidanceProvider
        self.completedScanRepository = completedScanRepository ?? SwiftDataCompletedScanRepository()
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
        scanFindingOverrideProvider = ScanFindingOverrideProvider(overrides: scanFindingOverrides)
        self.scanAnalysisPresentationOverride = scanAnalysisPresentationOverride
        sessionController.frameSource.consumer = coordinator
    }

    func nextScanFindingOverride() -> [AccessibilityFinding] {
        scanFindingOverrideProvider.next()
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
        // UI tests opt into a fresh in-memory history on every launch. This
        // branch is absent in Release and never touches the user's disk store.
        let testRepository: (any CompletedScanRepository)? = arguments.contains("-accesslens-history")
            ? InMemoryCompletedScanRepository(scans: AppLaunchConfiguration.historyOverride(arguments: arguments))
            : nil
        let scanAnalysisPresentationOverride = AppLaunchConfiguration.scanAnalysisPresentationOverride(arguments: arguments)
        if let authorization = AppLaunchConfiguration.cameraAuthorizationOverride(arguments: arguments) {
            return AppDependencies(
                onboardingState: onboardingState,
                cameraAuthorizationService: InMemoryCameraAuthorizationService(
                    authorization: authorization
                ),
                completedScanRepository: testRepository,
                scanFindingOverrides: scanFindingOverride.isEmpty ? [] : [scanFindingOverride],
                scanAnalysisPresentationOverride: scanAnalysisPresentationOverride
            )
        }

        if let onboardingState {
            return AppDependencies(
                onboardingState: onboardingState,
                completedScanRepository: testRepository,
                scanFindingOverrides: scanFindingOverride.isEmpty ? [] : [scanFindingOverride],
                scanAnalysisPresentationOverride: scanAnalysisPresentationOverride
            )
        }
        #endif

        return AppDependencies()
    }
}

/// A test-composition helper only. It has no production UI control and keeps
/// deterministic evidence scoped to a single test-created scan session.
private final class ScanFindingOverrideProvider {
    private var overrides: [[AccessibilityFinding]]

    init(overrides: [[AccessibilityFinding]]) {
        self.overrides = overrides
    }

    func next() -> [AccessibilityFinding] {
        guard !overrides.isEmpty else { return [] }
        return overrides.removeFirst()
    }
}

private enum AppLaunchConfiguration {
    #if DEBUG
    static func historyOverride(arguments: [String]) -> [CompletedScan] {
        guard let index = arguments.firstIndex(of: "-accesslens-history"),
              arguments.indices.contains(index + 1), arguments[index + 1] == "seeded" else { return [] }
        let findings = scanFindingOverride(arguments: ["-accesslens-scan-findings", "stable-low-contrast"])
        guard let newer = UUID(uuidString: "33333333-3333-3333-3333-333333333333"),
              let older = UUID(uuidString: "44444444-4444-4444-4444-444444444444") else { return [] }
        return [
            CompletedScan(sessionID: older, startedAt: Date(timeIntervalSince1970: 100), completedAt: Date(timeIntervalSince1970: 110), findings: []),
            CompletedScan(sessionID: newer, startedAt: Date(timeIntervalSince1970: 200), completedAt: Date(timeIntervalSince1970: 210), findings: findings)
        ]
    }
    #endif
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
        guard valueIndex < arguments.endIndex,
              ["stable-low-contrast", "multiple-low-contrast"].contains(arguments[valueIndex]) else {
            return []
        }

        guard let sessionUUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111"),
              let findingID = UUID(uuidString: "22222222-2222-2222-2222-222222222222") else {
            return []
        }
        let sessionID = AnalysisSessionID(rawValue: sessionUUID)
        let contexts = arguments[valueIndex] == "multiple-low-contrast" ? ["EXIT", "ELEVATOR"] : ["EXIT"]
        return contexts.enumerated().map { index, text in AccessibilityFinding(
            id: index == 0 ? findingID : sessionUUID,
            category: .potentialLowContrastText,
            title: "Potential low contrast",
            explanation: "Text in this area may be difficult to distinguish from its background.",
            evidenceSummary: "Deterministic UI-test finding.",
            evidenceStrength: index == 0 ? .moderate : .limited,
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
            relevantText: text,
            estimatedContrastRatio: ContrastRatio(lighterLuminance: 0.2, darkerLuminance: 0.02)
        ) }
    }

    static func scanAnalysisPresentationOverride(arguments: [String]) -> Bool {
        guard let argumentIndex = arguments.firstIndex(of: scanFindingsArgument) else {
            return false
        }
        let valueIndex = arguments.index(after: argumentIndex)
        guard valueIndex < arguments.endIndex else { return false }
        return ["stable-low-contrast", "multiple-low-contrast", "analyzing-empty"].contains(arguments[valueIndex])
    }
}
