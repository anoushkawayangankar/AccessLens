import Foundation

/// A presentation-safe description of a recoverable product error.
/// Technical errors map to this value at feature boundaries; raw framework
/// errors and private context are not shown directly to people using the app.
struct UserFacingError: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let message: String
    let recoveryActionTitle: String?

    init(
        id: UUID = UUID(),
        title: String,
        message: String,
        recoveryActionTitle: String? = nil
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.recoveryActionTitle = recoveryActionTitle
    }
}

