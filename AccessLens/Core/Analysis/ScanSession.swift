import Foundation

/// The explicit lifecycle for one in-memory user scan. It prevents mutually
/// incompatible boolean state such as a scan being both active and complete.
nonisolated enum ScanSessionLifecycleState: Equatable, Sendable, Hashable {
    case idle
    case preparing
    case scanning
    case completing
    case completed
    case discarded
}

/// Framework-independent identity and lifecycle metadata for one live scan.
/// It intentionally contains no capture, Vision, image, or SwiftUI types.
nonisolated struct ScanSession: Identifiable, Equatable, Sendable, Hashable {
    let id: UUID
    let startedAt: Date
    let completedAt: Date?
    let lifecycleState: ScanSessionLifecycleState

    init(
        id: UUID = UUID(),
        startedAt: Date,
        completedAt: Date? = nil,
        lifecycleState: ScanSessionLifecycleState
    ) {
        self.id = id
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.lifecycleState = lifecycleState
    }

    func transitioned(to state: ScanSessionLifecycleState, at date: Date? = nil) -> ScanSession {
        ScanSession(
            id: id,
            startedAt: startedAt,
            completedAt: state == .completed ? date : completedAt,
            lifecycleState: state
        )
    }
}

/// An immutable, review-only record of evidence collected during one finished
/// scan. It lives solely in memory in Milestone 8 and is never a persistence
/// DTO or a substitute for a saved scan.
nonisolated struct CompletedScan: Identifiable, Equatable, Sendable, Hashable {
    let id: UUID
    let sessionID: UUID
    let startedAt: Date
    let completedAt: Date
    let findings: [AccessibilityFinding]
    let limitationsSummary: String

    init(
        sessionID: UUID,
        startedAt: Date,
        completedAt: Date,
        findings: [AccessibilityFinding],
        limitationsSummary: String = "AccessLens identifies potential issues from camera observations. It may miss barriers, and lighting, glare, motion, and camera angle can affect results. It does not provide accessibility or legal compliance certification."
    ) {
        id = sessionID
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.findings = findings
        self.limitationsSummary = limitationsSummary
    }

    var findingCount: Int { findings.count }
}

nonisolated protocol ScanSessionTimeProviding: Sendable {
    func now() -> Date
}

nonisolated struct SystemScanSessionClock: ScanSessionTimeProviding {
    func now() -> Date { Date() }
}

/// Pure state machine for session lifecycle and snapshot construction. The
/// Scan feature performs resource teardown between `beginCompletion()` and
/// `complete(with:at:)`; this state machine ensures that sequence is one-shot.
nonisolated struct ScanSessionWorkflow: Sendable {
    private(set) var session: ScanSession?

    var lifecycleState: ScanSessionLifecycleState {
        session?.lifecycleState ?? .idle
    }

    mutating func start(at date: Date) -> ScanSession? {
        guard session == nil || lifecycleState == .discarded || lifecycleState == .completed else {
            return nil
        }
        let preparing = ScanSession(startedAt: date, lifecycleState: .preparing)
        let scanning = preparing.transitioned(to: .scanning)
        session = scanning
        return scanning
    }

    mutating func beginCompletion() -> ScanSession? {
        guard let session, session.lifecycleState == .scanning else { return nil }
        let completing = session.transitioned(to: .completing)
        self.session = completing
        return completing
    }

    mutating func complete(with findings: [AccessibilityFinding], at date: Date) -> CompletedScan? {
        guard let session, session.lifecycleState == .completing else { return nil }
        let completed = session.transitioned(to: .completed, at: date)
        self.session = completed
        return CompletedScan(
            sessionID: completed.id,
            startedAt: completed.startedAt,
            completedAt: date,
            findings: findings
        )
    }

    mutating func discard() {
        guard let session,
              session.lifecycleState == .preparing || session.lifecycleState == .scanning || session.lifecycleState == .completing else {
            return
        }
        self.session = session.transitioned(to: .discarded)
    }
}
