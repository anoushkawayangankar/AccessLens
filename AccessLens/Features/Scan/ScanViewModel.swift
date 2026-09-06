import Combine
import Foundation
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

    private let authorizationService: any CameraAuthorizationProviding
    private let sessionController: CameraSessionController
    private let analysisCoordinator: AnalysisCoordinator
    private let initialFindings: [AccessibilityFinding]
    private let forceAnalysisPresentation: Bool
    private var isVisible = false
    private var isApplicationActive = true
    private var hasActiveAnalysisSession = false
    private var activeAnalysisSessionID: AnalysisSessionID?
    private var announcedFindingIDs: Set<UUID> = []

    init(
        authorizationService: any CameraAuthorizationProviding,
        sessionController: CameraSessionController,
        analysisCoordinator: AnalysisCoordinator,
        initialFindings: [AccessibilityFinding] = [],
        forceAnalysisPresentation: Bool = false
    ) {
        self.authorizationService = authorizationService
        self.sessionController = sessionController
        self.analysisCoordinator = analysisCoordinator
        self.initialFindings = initialFindings
        self.forceAnalysisPresentation = forceAnalysisPresentation
        authorization = authorizationService.currentAuthorization()
        sessionController.setAuthorization(authorization)
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

    func appear() {
        isVisible = true
        authorization = authorizationService.currentAuthorization()
        sessionController.setAuthorization(authorization)
        sessionController.setScanVisible(true)
        updateAnalysisSession()
    }

    func disappear() {
        isVisible = false
        sessionController.setScanVisible(false)
        updateAnalysisSession()
    }

    func handle(scenePhase: ScenePhase) {
        isApplicationActive = scenePhase == .active
        updateAnalysisSession()
    }

    func requestCameraAccess() async {
        guard authorization == .notDetermined, !isRequestingPermission else { return }

        isRequestingPermission = true
        let updatedAuthorization = await authorizationService.requestAuthorization()
        authorization = updatedAuthorization
        isRequestingPermission = false
        sessionController.setAuthorization(updatedAuthorization)
        updateAnalysisSession()
    }

    func noteSettingsCouldNotOpen() {
        settingsCouldNotOpen = true
    }

    private func updateAnalysisSession() {
        let shouldAnalyze = isVisible && isApplicationActive && authorization == .authorized
        guard shouldAnalyze != hasActiveAnalysisSession else { return }

        hasActiveAnalysisSession = shouldAnalyze
        if shouldAnalyze {
            let sessionID = analysisCoordinator.beginSession()
            activeAnalysisSessionID = sessionID
            activeFindings = initialFindings
            announcedFindingIDs = []
            isAnalyzingEnvironment = true
        } else {
            activeAnalysisSessionID = nil
            activeFindings = []
            announcedFindingIDs = []
            isAnalyzingEnvironment = false
            analysisCoordinator.endSession()
        }
    }

    private func receive(_ result: StabilizedAnalysisResult) {
        guard activeAnalysisSessionID == result.sessionID else { return }
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
