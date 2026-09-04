import Combine
import Foundation
import OSLog

protocol OnboardingCompletionStoring: AnyObject {
    var isCompleted: Bool { get set }
}

final class UserDefaultsOnboardingCompletionStore: OnboardingCompletionStoring {
    static let key = "com.anoushka.accesslens.onboarding.completed"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var isCompleted: Bool {
        get { defaults.bool(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}

/// Deterministic storage for tests, previews, and DEBUG launch overrides.
final class InMemoryOnboardingCompletionStore: OnboardingCompletionStoring {
    var isCompleted: Bool

    init(isCompleted: Bool = false) {
        self.isCompleted = isCompleted
    }
}

enum AppRootDestination: Equatable, Sendable {
    case onboarding
    case home
}

/// The single owner of first-run completion state.
@MainActor
final class OnboardingState: ObservableObject {
    @Published private(set) var isCompleted: Bool

    private let store: OnboardingCompletionStoring

    init(store: OnboardingCompletionStoring) {
        self.store = store
        isCompleted = store.isCompleted
    }

    var destination: AppRootDestination {
        isCompleted ? .home : .onboarding
    }

    func complete() {
        guard !isCompleted else { return }

        store.isCompleted = true
        isCompleted = true
        AppLog.app.info("Onboarding completed")
    }
}

