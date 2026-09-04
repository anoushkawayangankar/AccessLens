@preconcurrency import AVFoundation
import Combine
import OSLog

/// Owns one capture session and confines all session mutation to a serial
/// queue. The published state is updated on the main actor for SwiftUI.
nonisolated final class CameraSessionController: NSObject, ObservableObject, @unchecked Sendable {
    @MainActor @Published private(set) var state: CameraSessionState = .idle

    let session = AVCaptureSession()
    let frameSource = CameraFrameSource()

    private let sessionQueue = DispatchQueue(label: "com.anoushka.accesslens.camera.session")
    private let videoOutputQueue = DispatchQueue(label: "com.anoushka.accesslens.camera.frames")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoOutputDelegate: CameraVideoOutputDelegate

    private var policy = CameraRuntimePolicy()
    private var isConfigured = false
    private var didAttemptMediaServicesRecovery = false
    private var notificationTokens: [NSObjectProtocol] = []

    override init() {
        videoOutputDelegate = CameraVideoOutputDelegate()
        super.init()
        videoOutputDelegate.frameSource = frameSource
        observeSessionNotifications()
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }

    func setAuthorization(_ authorization: CameraAuthorizationState) {
        AppLog.camera.debug("Camera authorization is \(authorization.logValue, privacy: .public)")
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.policy.isAuthorized = authorization == .authorized
            self.applyPolicy()
        }
    }

    func setScanVisible(_ isVisible: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.policy.isScanVisible = isVisible
            self.applyPolicy()
        }
    }

    func setApplicationIsActive(_ isActive: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.policy.isApplicationActive = isActive
            self.applyPolicy()
        }
    }

    private func applyPolicy() {
        if policy.shouldRun {
            configureAndStartIfNeeded()
        } else {
            stopIfRunning()
        }
    }

    private func configureAndStartIfNeeded() {
        guard !session.isRunning else { return }

        guard configureIfNeeded() else { return }
        guard policy.shouldRun, !session.isRunning else { return }

        session.startRunning()
        didAttemptMediaServicesRecovery = false
        publish(.running)
        AppLog.camera.info("Camera session started")
    }

    private func configureIfNeeded() -> Bool {
        guard !isConfigured else { return true }

        publish(.configuring)
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let device = preferredBackCamera() else {
            fail(with: .noCameraDevice)
            return false
        }

        if session.inputs.isEmpty {
            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else {
                    fail(with: .cannotAddInput)
                    return false
                }
                session.addInput(input)
            } catch {
                fail(with: .cannotCreateInput)
                return false
            }
        }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(videoOutputDelegate, queue: videoOutputQueue)

        if !session.outputs.contains(where: { $0 === videoOutput }) {
            guard session.canAddOutput(videoOutput) else {
                fail(with: .cannotAddOutput)
                return false
            }
            session.addOutput(videoOutput)
        }
        isConfigured = true
        publish(.ready)
        AppLog.camera.info("Camera session configured")
        return true
    }

    private func stopIfRunning() {
        guard session.isRunning else { return }
        session.stopRunning()
        publish(policy.isInterrupted ? .interrupted : .ready)
        AppLog.camera.info("Camera session stopped")
    }

    private func preferredBackCamera() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.DiscoverySession(
                deviceTypes: [
                    .builtInWideAngleCamera,
                    .builtInDualWideCamera,
                    .builtInDualCamera,
                    .builtInTripleCamera
                ],
                mediaType: .video,
                position: .back
            ).devices.first
    }

    private func fail(with error: CameraError) {
        publish(.unavailable(error))
        AppLog.camera.error("Camera session failed: \(error.logValue, privacy: .public)")
    }

    private func publish(_ newState: CameraSessionState) {
        Task { @MainActor [weak self] in
            self?.state = newState
        }
    }

    private func observeSessionNotifications() {
        let center = NotificationCenter.default
        notificationTokens = [
            center.addObserver(
                forName: AVCaptureSession.wasInterruptedNotification,
                object: session,
                queue: nil
            ) { [weak self] _ in
                self?.handleInterruptionBegan()
            },
            center.addObserver(
                forName: AVCaptureSession.interruptionEndedNotification,
                object: session,
                queue: nil
            ) { [weak self] _ in
                self?.handleInterruptionEnded()
            },
            center.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification,
                object: session,
                queue: nil
            ) { [weak self] notification in
                self?.handleRuntimeError(notification)
            }
        ]
    }

    private func handleInterruptionBegan() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.policy.isInterrupted = true
            self.publish(.interrupted)
            AppLog.camera.info("Camera session interrupted")
            self.applyPolicy()
        }
    }

    private func handleInterruptionEnded() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.policy.isInterrupted = false
            AppLog.camera.info("Camera session interruption ended")
            self.applyPolicy()
        }
    }

    private func handleRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
        let wasMediaServicesReset = error?.code == AVError.Code.mediaServicesWereReset.rawValue

        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard wasMediaServicesReset, !self.didAttemptMediaServicesRecovery else {
                self.fail(with: .sessionRuntimeFailure)
                return
            }

            self.didAttemptMediaServicesRecovery = true
            self.isConfigured = false
            AppLog.camera.notice("Attempting one camera media-services recovery")
            self.configureAndStartIfNeeded()
        }
    }
}

nonisolated private final class CameraVideoOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    weak var frameSource: CameraFrameSource?

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameSource?.deliver(sampleBuffer)
    }
}

nonisolated private extension CameraAuthorizationState {
    var logValue: String {
        switch self {
        case .notDetermined: "notDetermined"
        case .authorized: "authorized"
        case .denied: "denied"
        case .restricted: "restricted"
        }
    }
}
