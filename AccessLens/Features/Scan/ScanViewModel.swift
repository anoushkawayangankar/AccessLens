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
    @Published private(set) var recentSignageCandidates: [FindingCandidate] = []
    @Published private(set) var recentContrastCandidates: [FindingCandidate] = []

    private let authorizationService: any CameraAuthorizationProviding
    private let sessionController: CameraSessionController
    private let analysisCoordinator: AnalysisCoordinator
    private var isVisible = false
    private var isApplicationActive = true
    private var hasActiveAnalysisSession = false
    private var activeAnalysisSessionID: AnalysisSessionID?
    private var signageDeduplicator = TransientSignageDeduplicator()
    private var contrastStabilizer = TransientContrastCandidateStabilizer()

    init(
        authorizationService: any CameraAuthorizationProviding,
        sessionController: CameraSessionController,
        analysisCoordinator: AnalysisCoordinator
    ) {
        self.authorizationService = authorizationService
        self.sessionController = sessionController
        self.analysisCoordinator = analysisCoordinator
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
            signageDeduplicator.reset()
            contrastStabilizer.reset()
            recentSignageCandidates = []
            recentContrastCandidates = []
            isAnalyzingEnvironment = true
        } else {
            activeAnalysisSessionID = nil
            signageDeduplicator.reset()
            contrastStabilizer.reset()
            recentSignageCandidates = []
            recentContrastCandidates = []
            isAnalyzingEnvironment = false
            analysisCoordinator.endSession()
        }
    }

    private func receive(_ result: AnalysisPassResult) {
        guard activeAnalysisSessionID == result.sessionID else { return }
        let currentTime = result.candidates.compactMap(\.presentationTimeSeconds).max()
        let signageAdditions = signageDeduplicator.ingest(
            result.candidates,
            sessionID: result.sessionID,
            currentTime: currentTime
        )
        let contrastAdditions = contrastStabilizer.ingest(
            result.candidates,
            sessionID: result.sessionID,
            currentTime: currentTime
        )
        recentSignageCandidates = signageDeduplicator.candidates
        recentContrastCandidates = contrastStabilizer.candidates

        if let announcement = contrastAdditions.first?.recognizedText {
            UIAccessibility.post(
                notification: .announcement,
                argument: "Potential low estimated contrast: \(announcement)"
            )
        } else if let announcement = signageAdditions.first?.recognizedText {
            UIAccessibility.post(notification: .announcement, argument: "Signage detected: \(announcement)")
        }
    }
}
