import SwiftUI

@main
struct AccessLensApp: App {
    @State private var dependencies = AppDependencies.forApplicationLaunch(
        arguments: ProcessInfo.processInfo.arguments
    )

    var body: some Scene {
        WindowGroup {
            AppRootView(dependencies: dependencies)
        }
    }
}
