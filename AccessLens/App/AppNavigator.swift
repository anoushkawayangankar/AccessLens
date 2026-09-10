import Foundation
import Combine

/// The sole owner of app-level navigation state.
///
/// Features own their internal state; this object only owns routes between
/// product surfaces.
@MainActor
final class AppNavigator: ObservableObject {
    @Published var path: [AppRoute] = []

    func navigate(to route: AppRoute) {
        path.append(route)
    }

    func goBack() {
        _ = path.popLast()
    }

    func returnToRoot() {
        path.removeAll()
    }

    /// Completion removes the live route so back navigation cannot reopen its
    /// stopped camera. The review owns only the finished domain value.
    func showCompletedScan(_ scan: CompletedScan) {
        path = [.scanReview(scan)]
    }
}

enum AppRoute: Hashable, Sendable {
    case scan
    case scanReview(CompletedScan)
    case findingDetail(id: UUID)
    case savedScans
    case scanDetail(id: UUID)
    case settings
}
