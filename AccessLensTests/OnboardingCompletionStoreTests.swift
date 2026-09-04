import Foundation
import XCTest
@testable import AccessLens

@MainActor
final class OnboardingCompletionStoreTests: XCTestCase {
    func testInMemoryStoreDefaultsToIncomplete() {
        let store = InMemoryOnboardingCompletionStore()

        XCTAssertFalse(store.isCompleted)
    }

    func testCompletionPersistsThroughStoreAbstraction() {
        let store = InMemoryOnboardingCompletionStore()
        let state = OnboardingState(store: store)

        state.complete()

        let reloadedState = OnboardingState(store: store)
        XCTAssertTrue(store.isCompleted)
        XCTAssertTrue(reloadedState.isCompleted)
    }

    func testRepeatedCompletionIsSafe() {
        let store = InMemoryOnboardingCompletionStore()
        let state = OnboardingState(store: store)

        state.complete()
        state.complete()

        XCTAssertTrue(state.isCompleted)
        XCTAssertEqual(state.destination, .home)
    }

    func testUserDefaultsStoreUsesOnlyItsNamespacedKey() {
        let suiteName = "AccessLensTests.Onboarding.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected an isolated UserDefaults suite.")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsOnboardingCompletionStore(defaults: defaults)
        XCTAssertFalse(store.isCompleted)

        store.isCompleted = true

        XCTAssertTrue(defaults.bool(forKey: UserDefaultsOnboardingCompletionStore.key))
    }
}

