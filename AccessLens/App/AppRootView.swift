import SwiftUI

struct AppRootView: View {
    let dependencies: AppDependencies

    @ObservedObject private var navigator: AppNavigator

    @Environment(\.scenePhase) private var scenePhase

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _navigator = ObservedObject(wrappedValue: dependencies.navigator)
    }

    var body: some View {
        NavigationStack(path: $navigator.path) {
            HomeView()
                .navigationDestination(for: AppRoute.self) { route in
                    FutureDestinationView(route: route)
                }
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            dependencies.lifecycleCoordinator.handle(scenePhase: newPhase)
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
