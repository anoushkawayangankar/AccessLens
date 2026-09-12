import Combine
import Foundation
import OSLog
import SwiftUI
import UIKit

enum CameraPermissionPresentation: Equatable, Sendable {
    case requestPermission
    case cameraReady
    case denied
    case restricted

    init(authorization: CameraAuthorizationState) {
        switch authorization {
        case .notDetermined: self = .requestPermission
        case .authorized: self = .cameraReady
        case .denied: self = .denied
        case .restricted: self = .restricted
        }
    }
}

@MainActor
final class ScanViewModel: ObservableObject {
    @Published private(set) var authorization: CameraAuthorizationState
    @Published private(set) var isRequestingPermission = false
    @Published private(set) var settingsCouldNotOpen = false
    @Published private(set) var isAnalyzingEnvironment = false
    @Published private(set) var activeFindings: [AccessibilityFinding] = []
    @Published private(set) var scanLifecycleState: ScanSessionLifecycleState = .idle
    @Published private(set) var completionError: ScanCompletionError?

    private let authorizationService: any CameraAuthorizationProviding
    private let sessionController: CameraSessionController
    private let passageCaptureController: RoomPlanPassageCaptureController
    private let analysisCoordinator: AnalysisCoordinator
    private let initialFindingsProvider: () -> [AccessibilityFinding]
    private let forceAnalysisPresentation: Bool
    private let clock: any ScanSessionTimeProviding
    private var isVisible = false
    private var isApplicationActive = true
    private var hasActiveAnalysisSession = false
    private(set) var activeAnalysisSessionID: AnalysisSessionID?
    private var workflow = ScanSessionWorkflow()
    private var hasConsumedInitialPresentation = false
    private var announcedFindingIDs: Set<UUID> = []

    init(
        authorizationService: any CameraAuthorizationProviding,
        sessionController: CameraSessionController,
        passageCaptureController: RoomPlanPassageCaptureController? = nil,
        analysisCoordinator: AnalysisCoordinator,
        initialFindings: [AccessibilityFinding] = [],
        initialFindingsProvider: (() -> [AccessibilityFinding])? = nil,
        forceAnalysisPresentation: Bool = false,
        clock: any ScanSessionTimeProviding = SystemScanSessionClock()
    ) {
        self.authorizationService = authorizationService
        self.sessionController = sessionController
        self.passageCaptureController = passageCaptureController ?? RoomPlanPassageCaptureController(
            roomPlanSupported: false,
            frameHandler: { _, _, _, _ in }
        )
        self.analysisCoordinator = analysisCoordinator
        self.initialFindingsProvider = initialFindingsProvider ?? { initialFindings }
        self.forceAnalysisPresentation = forceAnalysisPresentation
        self.clock = clock
        authorization = authorizationService.currentAuthorization()
        sessionController.setAuthorization(authorization)
        self.passageCaptureController.setAuthorization(authorization)
        analysisCoordinator.setResultHandler { [weak self] result in
            Task { @MainActor [weak self] in
                self?.receive(result)
            }
        }
    }

    var permissionPresentation: CameraPermissionPresentation {
        CameraPermissionPresentation(authorization: authorization)
    }

    /// Exists only for deterministic DEBUG launch composition. It never turns
    /// on analysis or supplies fake evidence in normal application behavior.
    var shouldPresentAnalysisFoundation: Bool {
        isAnalyzingEnvironment || forceAnalysisPresentation
    }

    var canFinishScan: Bool {
        scanLifecycleState == .scanning
    }

    var usesPassageCapture: Bool {
        passageCaptureController.capability.supportsPassageAnalysis
    }

    var hasActiveLiveScan: Bool {
        switch scanLifecycleState {
        case .preparing, .scanning, .completing:
            true
        case .idle, .completed, .discarded:
            false
        }
    }

    func appear() {
        isVisible = true
        authorization = authorizationService.currentAuthorization()
        sessionController.setAuthorization(authorization)
        passageCaptureController.setAuthorization(authorization)
        applyCaptureVisibility()
        updateAnalysisSession()
    }

    func disappear() {
        isVisible = false
        sessionController.setScanVisible(false)
        passageCaptureController.setScanVisible(false)
        if hasActiveLiveScan {
            discardScan()
        } else {
            stopLiveAnalysis()
        }
    }

    func handle(scenePhase: ScenePhase) {
        isApplicationActive = scenePhase == .active
        passageCaptureController.setApplicationActive(isApplicationActive)
        applyCaptureVisibility()
        updateAnalysisSession()
    }

    func requestCameraAccess() async {
        guard authorization == .notDetermined, !isRequestingPermission else { return }

        isRequestingPermission = true
        let updatedAuthorization = await authorizationService.requestAuthorization()
        authorization = updatedAuthorization
        isRequestingPermission = false
        sessionController.setAuthorization(updatedAuthorization)
        passageCaptureController.setAuthorization(updatedAuthorization)
        applyCaptureVisibility()
        updateAnalysisSession()
    }

    func noteSettingsCouldNotOpen() {
        settingsCouldNotOpen = true
    }

    /// Stops camera/analysis first, then freezes only the compact stabilized
    /// finding values into an in-memory review snapshot. Repeated calls after
    /// the first safely return nil.
    func finishScan() -> CompletedScan? {
        completionError = nil
        guard workflow.beginCompletion() != nil else { return nil }
        scanLifecycleState = .completing
        AppLog.lifecycle.info("Scan completion requested")

        // Ask the runtime to stop before collecting the final stable state.
        // `completeSession` clears the analysis gate before cancelling work,
        // which rejects any late OCR/contrast result deterministically.
        sessionController.setScanVisible(false)
        passageCaptureController.setScanVisible(false)
        let finalFindings = stopLiveAnalysis(returningFinalFindings: true)

        guard let completed = workflow.complete(with: finalFindings, at: clock.now()) else {
            completionError = .couldNotCreateSnapshot
            scanLifecycleState = .discarded
            return nil
        }

        scanLifecycleState = .completed
        activeFindings = []
        announcedFindingIDs = []
        AppLog.lifecycle.info("Scan completed")
        return completed
    }

    /// Ends an active scan without producing a review snapshot. This is used
    /// only after explicit user confirmation when leaving Scan.
    func discardScan() {
        guard hasActiveLiveScan else { return }
        workflow.discard()
        scanLifecycleState = .discarded
        sessionController.setScanVisible(false)
        passageCaptureController.setScanVisible(false)
        _ = stopLiveAnalysis(returningFinalFindings: false)
        activeFindings = []
        announcedFindingIDs = []
        AppLog.lifecycle.info("Scan discarded")
    }

    private func updateAnalysisSession() {
        let shouldAnalyze = isVisible && isApplicationActive && authorization == .authorized
        guard scanLifecycleState != .completed, scanLifecycleState != .discarded else { return }

        if shouldAnalyze, workflow.session == nil {
            _ = workflow.start(at: clock.now())
            scanLifecycleState = workflow.lifecycleState
            AppLog.lifecycle.info("Scan started")
        }

        let shouldRunAnalysis = shouldAnalyze && scanLifecycleState == .scanning
        guard shouldRunAnalysis != hasActiveAnalysisSession else { return }

        if shouldRunAnalysis {
            hasActiveAnalysisSession = true
            let sessionID = analysisCoordinator.beginSession()
            activeAnalysisSessionID = sessionID
            if !hasConsumedInitialPresentation {
                activeFindings = initialFindingsProvider()
                hasConsumedInitialPresentation = true
            } else {
                activeFindings = []
            }
            announcedFindingIDs = []
            isAnalyzingEnvironment = true
        } else {
            stopLiveAnalysis()
        }
    }

    private func applyCaptureVisibility() {
        let shouldShowCapture = isVisible && isApplicationActive
        sessionController.setScanVisible(shouldShowCapture && !usesPassageCapture)
        passageCaptureController.setScanVisible(shouldShowCapture && usesPassageCapture)
    }

    @discardableResult
    private func stopLiveAnalysis(returningFinalFindings: Bool = false) -> [AccessibilityFinding] {
        // The Scan view owns the last compact result that was already accepted
        // for this session. Freeze it before clearing the coordinator; the
        // coordinator's gate then rejects any later work.
        let finalFindings = activeFindings
        if hasActiveAnalysisSession {
            hasActiveAnalysisSession = false
            activeAnalysisSessionID = nil
            _ = analysisCoordinator.completeSession()
        } else {
            analysisCoordinator.endSession()
        }
        activeFindings = []
        announcedFindingIDs = []
        isAnalyzingEnvironment = false
        return returningFinalFindings ? finalFindings : []
    }

    func receive(_ result: StabilizedAnalysisResult) {
        guard scanLifecycleState == .scanning,
              activeAnalysisSessionID == result.sessionID else { return }
        activeFindings = result.findings

        let newIDs = result.newlyPromotedFindingIDs.subtracting(announcedFindingIDs)
        if let finding = activeFindings.first(where: { newIDs.contains($0.id) }) {
            announcedFindingIDs.insert(finding.id)
            let text = finding.relevantText.map { ": \($0)" } ?? ""
            UIAccessibility.post(
                notification: .announcement,
                argument: "New potential finding\(text)"
            )
        }
    }
}

enum ScanCompletionError: Equatable, Sendable {
    case couldNotCreateSnapshot
}
