import SwiftUI
import UIKit

struct ScanView: View {
    @StateObject private var viewModel: ScanViewModel
    @ObservedObject private var sessionController: CameraSessionController
    @Environment(\.scenePhase) private var scenePhase

    init(
        authorizationService: any CameraAuthorizationProviding,
        sessionController: CameraSessionController,
        analysisCoordinator: AnalysisCoordinator,
        initialFindings: [AccessibilityFinding] = [],
        forceAnalysisPresentation: Bool = false
    ) {
        _viewModel = StateObject(
            wrappedValue: ScanViewModel(
                authorizationService: authorizationService,
                sessionController: sessionController,
                analysisCoordinator: analysisCoordinator,
                initialFindings: initialFindings,
                forceAnalysisPresentation: forceAnalysisPresentation
            )
        )
        _sessionController = ObservedObject(wrappedValue: sessionController)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                Text("Scan")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("scan-heading")

                preview
                statusCard

                Text(analysisSummary)
                    .font(.body)
                    .accessibilityIdentifier("scan-foundation-message")

                if viewModel.shouldPresentAnalysisFoundation {
                    findingsSection
                }
            }
            .frame(maxWidth: AppLayout.maximumReadableWidth, alignment: .leading)
            .padding(AppSpacing.page)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Scan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.appear() }
        .onDisappear { viewModel.disappear() }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            viewModel.handle(scenePhase: newPhase)
        }
        .onChange(of: viewModel.authorization) { _, authorization in
            switch authorization {
            case .denied:
                announce("Camera access is off. Enable it in Settings to use AccessLens scanning.")
            case .restricted:
                announce("Camera access is restricted on this device.")
            case .notDetermined, .authorized:
                break
            }
        }
        .onChange(of: sessionController.state) { _, state in
            switch state {
            case .interrupted:
                announce("Camera interrupted. AccessLens will resume it when possible.")
            case let .unavailable(error):
                announce(error.userFacingError.message)
            case .idle, .configuring, .ready, .running:
                break
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if shouldShowPreview {
            CameraPreview(session: sessionController.session)
                .frame(minHeight: 260)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous)
                .fill(.quaternary)
                .frame(minHeight: 180)
                .overlay {
                    Image(systemName: "camera")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .accessibilityHidden(true)
        }
    }

    private var shouldShowPreview: Bool {
        guard viewModel.authorization == .authorized else { return false }
        if case .unavailable = sessionController.state {
            return false
        }
        return true
    }

    @ViewBuilder
    private var statusCard: some View {
        switch viewModel.permissionPresentation {
        case .requestPermission:
            statusContainer(
                title: "Enable the camera",
                message: "Allow camera access to use AccessLens for environmental scanning.",
                symbolName: "camera"
            ) {
                Button("Enable Camera") {
                    Task { await viewModel.requestCameraAccess() }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: AppLayout.minimumTouchTarget)
                .accessibilityIdentifier("enable-camera")
            }
        case .cameraReady:
            cameraRuntimeStatus
        case .denied:
            statusContainer(
                title: "Camera access is off",
                message: "Enable camera access in Settings to use AccessLens scanning.",
                symbolName: "camera.fill"
            ) {
                Button("Open Settings") {
                    openSettings()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: AppLayout.minimumTouchTarget)
                .accessibilityIdentifier("open-camera-settings")

                if viewModel.settingsCouldNotOpen {
                    Text("Settings could not be opened. You can change camera access in the Settings app.")
                        .font(.footnote)
                }
            }
            .accessibilityIdentifier("camera-denied-state")
        case .restricted:
            statusContainer(
                title: "Camera access is restricted",
                message: "Camera access is restricted on this device and cannot be changed by AccessLens.",
                symbolName: "camera.fill"
            )
            .accessibilityIdentifier("camera-restricted-state")
        }
    }

    @ViewBuilder
    private var cameraRuntimeStatus: some View {
        switch sessionController.state {
        case .idle, .configuring, .ready:
            statusContainer(
                title: "Preparing camera",
                message: "AccessLens is preparing the camera.",
                symbolName: "camera"
            )
        case .running:
            statusContainer(
                title: viewModel.isAnalyzingEnvironment ? "Analyzing environment" : "Camera ready",
                message: "Point your camera at visible signs. AccessLens presents potential findings only when repeated evidence is usable; it does not certify accessibility.",
                symbolName: "text.viewfinder"
            )
        case .interrupted:
            statusContainer(
                title: "Camera interrupted",
                message: "The camera is temporarily unavailable. AccessLens will resume it when possible.",
                symbolName: "pause.circle"
            )
        case let .unavailable(error):
            statusContainer(
                title: error.userFacingError.title,
                message: error.userFacingError.message,
                symbolName: "exclamationmark.triangle"
            )
            .accessibilityIdentifier("camera-unavailable-state")
        }
    }

    private var analysisSummary: String {
        if viewModel.isAnalyzingEnvironment {
            return "AccessLens analyzes visible text and environmental signage on this device. Potential findings require repeated usable evidence and should be verified in person."
        }
        return "Camera analysis starts when camera input is available. AccessLens does not certify accessibility or legal compliance."
    }

    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Label("Potential findings", systemImage: "exclamationmark.magnifyingglass")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            if viewModel.activeFindings.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("No potential issues identified yet.")
                        .font(.body)
                        // This semantic label, rather than a layout coordinate,
                        // is the stable entry point for the empty-state UI test.
                        .accessibilityIdentifier("no-potential-findings")
                    Text("This does not mean the environment is accessible. Continue reviewing the space directly.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                ForEach(viewModel.activeFindings) { finding in
                    findingCard(finding)
                }
            }
        }
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
        .accessibilityIdentifier("potential-findings")
    }

    private func findingCard(_ finding: AccessibilityFinding) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Label(finding.title, systemImage: "exclamationmark.magnifyingglass")
                .font(.headline)
            if let text = finding.relevantText {
                Text(text)
                    .font(.body.weight(.semibold))
            }
            Text(finding.explanation)
                .font(.body)
            Text("Evidence strength: \(finding.evidenceStrength.rawValue.capitalized)")
                .font(.subheadline)
            if let ratio = finding.estimatedContrastRatio {
                Text("Estimated text/background contrast: \(ratio.value, format: .number.precision(.fractionLength(1))):1")
                    .font(.subheadline)
            }
            Text("Estimated from camera observations. Review the environment directly before acting on this result.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(AppSpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tertiary, in: RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("stable-finding-\(finding.id.uuidString)")
    }

    private func statusContainer<Content: View>(
        title: String,
        message: String,
        symbolName: String,
        @ViewBuilder content: () -> Content = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Label(title, systemImage: symbolName)
                .font(.headline)
            Text(message)
                .font(.body)
            content()
        }
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func openSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(settingsURL) else {
            viewModel.noteSettingsCouldNotOpen()
            return
        }

        UIApplication.shared.open(settingsURL)
    }

    private func announce(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

#if DEBUG
struct ScanView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ScanView(
                authorizationService: InMemoryCameraAuthorizationService(authorization: .denied),
                sessionController: CameraSessionController(),
                analysisCoordinator: AnalysisCoordinator()
            )
        }
    }
}
#endif
