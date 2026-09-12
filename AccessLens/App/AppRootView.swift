import SwiftUI

struct AppRootView: View {
    let dependencies: AppDependencies

    @ObservedObject private var navigator: AppNavigator
    @ObservedObject private var onboardingState: OnboardingState

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _navigator = ObservedObject(wrappedValue: dependencies.navigator)
        _onboardingState = ObservedObject(wrappedValue: dependencies.onboardingState)
    }

    var body: some View {
        Group {
            switch onboardingState.destination {
            case .onboarding:
                OnboardingView(onboardingState: onboardingState)
            case .home:
                NavigationStack(path: $navigator.path) {
                    HomeView(onStartScan: {
                        navigator.navigate(to: .scan)
                    }, onHistory: {
                        navigator.navigate(to: .savedScans)
                    })
                        .navigationDestination(for: AppRoute.self) { route in
                            destination(for: route)
                        }
                }
                .transaction { if reduceMotion { $0.disablesAnimations = true } }
            }
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            dependencies.lifecycleCoordinator.handle(scenePhase: newPhase)
            dependencies.cameraLifecycleCoordinator.handle(scenePhase: newPhase)
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case let .findingDetail(finding):
            FindingDetailView(guidance: dependencies.guidanceProvider.guidance(for: finding)) {
                navigator.goBack()
            }
            .id(finding.id)
        case .scan:
            ScanView(
                authorizationService: dependencies.cameraAuthorizationService,
                sessionController: dependencies.cameraSessionController,
                analysisCoordinator: dependencies.analysisCoordinator,
                initialFindingsProvider: dependencies.nextScanFindingOverride,
                forceAnalysisPresentation: dependencies.scanAnalysisPresentationOverride,
                onCompleted: { completedScan in
                    navigator.showCompletedScan(completedScan)
                },
                onDiscard: {
                    navigator.goBack()
                }
            )
        case let .scanReview(completedScan):
            CompletedScanReviewView(scan: completedScan, repository: dependencies.completedScanRepository) {
                navigator.returnToRoot()
            }
        case .savedScans:
            ScanHistoryView(repository: dependencies.completedScanRepository, onOpen: { id in
                navigator.navigate(to: .scanDetail(id: id))
            }, onStartScan: {
                navigator.navigate(to: .scan)
            })
        case let .scanDetail(id):
            HistoricalScanReviewView(id: id, repository: dependencies.completedScanRepository) {
                navigator.goBack()
            }
        default:
            FutureDestinationView(route: route)
        }
    }
}

private struct FutureDestinationView: View {
    let route: AppRoute

    var body: some View {
        ContentUnavailableView {
            Label("Not Available Yet", systemImage: "clock")
        } description: {
            Text("This product surface will be introduced in a later milestone.")
        }
        .navigationTitle(title)
    }

    private var title: String {
        switch route {
        case .scan:
            "Scan"
        case .scanReview:
            "Scan Review"
        case .findingDetail:
            "Finding Detail"
        case .savedScans:
            "Saved Scans"
        case .scanDetail:
            "Scan Detail"
        case .settings:
            "Settings"
        }
    }
}

struct AppRootView_Previews: PreviewProvider {
    static var previews: some View {
        AppRootView(dependencies: AppDependencies())
    }
}
