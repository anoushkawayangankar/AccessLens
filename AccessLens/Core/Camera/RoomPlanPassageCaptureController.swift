@preconcurrency import ARKit
import Combine
import CoreVideo
import Foundation
import OSLog
@preconcurrency import RoomPlan
import UIKit

nonisolated enum PassageCaptureCapability: Equatable, Sendable {
    case roomPlanLiDAR
    case cameraGeometryWithoutScale
    case unavailable

    var supportsPassageAnalysis: Bool { self == .roomPlanLiDAR }
}

nonisolated struct PassageCaptureCapabilityPolicy: Sendable {
    func capability(roomPlanSupported: Bool, hasCameraIntrinsics: Bool) -> PassageCaptureCapability {
        if roomPlanSupported { return .roomPlanLiDAR }
        return hasCameraIntrinsics ? .cameraGeometryWithoutScale : .unavailable
    }
}

enum PassageCaptureState: Equatable, Sendable {
    case unavailable
    case ready
    case running
    case limited
}

/// LiDAR-only RoomPlan capture path. On supported hardware it replaces the
/// AVCaptureSession while Scan is visible, so AccessLens never runs competing
/// camera sessions. RoomPlan values terminate in the delivery bridge.
@MainActor
final class RoomPlanPassageCaptureController: NSObject, ObservableObject {
    @Published private(set) var state: PassageCaptureState
    @Published private(set) var captureGuidance: String?

    let capability: PassageCaptureCapability
    let captureView: RoomCaptureView?

    private let deliveryBridge: RoomPlanPassageDeliveryBridge
    private var isVisible = false
    private var isApplicationActive = true
    private var isAuthorized = false
    private var isRunning = false

    init(
        roomPlanSupported: Bool = RoomCaptureSession.isSupported,
        hasCameraIntrinsics: Bool = true,
        frameHandler: @escaping @Sendable (
            CVPixelBuffer, TimeInterval, AnalysisImageOrientation, [PassageSurfaceEvidence]
        ) -> Void
    ) {
        capability = PassageCaptureCapabilityPolicy().capability(
            roomPlanSupported: roomPlanSupported,
            hasCameraIntrinsics: hasCameraIntrinsics
        )
        deliveryBridge = RoomPlanPassageDeliveryBridge(frameHandler: frameHandler)
        if roomPlanSupported {
            let view = RoomCaptureView(frame: .zero)
            view.isModelEnabled = false
            captureView = view
            state = .ready
        } else {
            captureView = nil
            state = .unavailable
        }
        super.init()
        captureView?.captureSession.delegate = self
    }

    func setAuthorization(_ authorization: CameraAuthorizationState) {
        isAuthorized = authorization == .authorized
        applyLifecycle()
    }

    func setScanVisible(_ visible: Bool) {
        isVisible = visible
        applyLifecycle()
    }

    func setApplicationActive(_ active: Bool) {
        isApplicationActive = active
        applyLifecycle()
    }

    func updateViewport(size: CGSize, orientation: UIInterfaceOrientation) {
        deliveryBridge.updateViewport(size: size, orientation: orientation)
    }

    private func applyLifecycle() {
        guard capability.supportsPassageAnalysis, let session = captureView?.captureSession else { return }
        let shouldRun = isVisible && isApplicationActive && isAuthorized
        if shouldRun, !isRunning {
            var configuration = RoomCaptureSession.Configuration()
            configuration.isCoachingEnabled = true
            session.run(configuration: configuration)
            isRunning = true
            state = .running
            AppLog.analysis.info("RoomPlan passage capture started")
        } else if !shouldRun, isRunning {
            session.stop(pauseARSession: true)
            isRunning = false
            state = .ready
            captureGuidance = nil
            AppLog.analysis.info("RoomPlan passage capture stopped")
        }
    }
}

extension RoomPlanPassageCaptureController: RoomCaptureSessionDelegate {
    nonisolated func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        deliveryBridge.deliver(session: session, room: room)
    }

    nonisolated func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {
        let guidance: String?
        switch instruction {
        case .moveAwayFromWall: guidance = String(localized: "Move back slightly so room features remain in view.")
        case .slowDown: guidance = String(localized: "Hold the phone steady and move more slowly.")
        case .turnOnLight: guidance = String(localized: "More light may help AccessLens observe room features.")
        case .lowTexture: guidance = String(localized: "Room features are difficult to observe from this view.")
        case .moveCloseToWall: guidance = String(localized: "Move closer to the area being reviewed.")
        case .normal: guidance = nil
        @unknown default: guidance = nil
        }
        Task { @MainActor [weak self] in self?.captureGuidance = guidance }
    }

    nonisolated func captureSession(
        _ session: RoomCaptureSession,
        didEndWith data: CapturedRoomData,
        error: (any Error)?
    ) {
        guard error != nil else { return }
        Task { @MainActor [weak self] in
            self?.isRunning = false
            self?.state = .limited
            self?.captureGuidance = String(localized: "Passage measurement is temporarily unavailable. Other supported analysis can continue.")
        }
        AppLog.analysis.error("RoomPlan passage capture ended with an error")
    }
}

/// Thread-safe, bounded conversion from RoomPlan/ARKit output to application
/// values. It retains neither CapturedRoom nor ARFrame after delivery.
private nonisolated final class RoomPlanPassageDeliveryBridge: @unchecked Sendable {
    typealias Handler = @Sendable (
        CVPixelBuffer, TimeInterval, AnalysisImageOrientation, [PassageSurfaceEvidence]
    ) -> Void

    private let lock = NSLock()
    private let frameHandler: Handler
    private var viewportSize = CGSize(width: 1, height: 1)
    private var interfaceOrientation = UIInterfaceOrientation.portrait

    init(frameHandler: @escaping Handler) {
        self.frameHandler = frameHandler
    }

    func updateViewport(size: CGSize, orientation: UIInterfaceOrientation) {
        guard size.width > 0, size.height > 0 else { return }
        lock.lock()
        viewportSize = size
        interfaceOrientation = orientation
        lock.unlock()
    }

    func deliver(session: RoomCaptureSession, room: CapturedRoom) {
        guard let frame = session.arSession.currentFrame else { return }
        lock.lock()
        let viewport = viewportSize
        let orientation = interfaceOrientation
        lock.unlock()

        let surfaces = room.doors.map { ($0, PassageSurfaceKind.door) }
            + room.openings.map { ($0, PassageSurfaceKind.opening) }
        let evidence = surfaces.prefix(8).map { surface, kind in
            makeEvidence(surface: surface, kind: kind, camera: frame.camera,
                         viewport: viewport, orientation: orientation)
        }
        frameHandler(
            frame.capturedImage,
            frame.timestamp,
            Self.analysisOrientation(for: orientation),
            evidence
        )
    }

    private func makeEvidence(
        surface: CapturedRoom.Surface,
        kind: PassageSurfaceKind,
        camera: ARCamera,
        viewport: CGSize,
        orientation: UIInterfaceOrientation
    ) -> PassageSurfaceEvidence {
        let quality: PassageMeasurementQuality
        switch surface.confidence {
        case .high: quality = .usable
        case .medium: quality = .approximate
        case .low: quality = .insufficient
        @unknown default: quality = .insufficient
        }
        let width = quality.supportsNumericPresentation
            ? PassageWidth(meters: Double(surface.dimensions.x))
            : nil
        return PassageSurfaceEvidence(
            surfaceID: surface.identifier,
            kind: kind,
            region: projectedRegion(surface: surface, camera: camera, viewport: viewport, orientation: orientation),
            estimatedWidth: width,
            measurementMethod: width == nil ? .unavailable : .roomPlanLiDAR,
            measurementQuality: width == nil ? .insufficient : quality
        )
    }

    private func projectedRegion(
        surface: CapturedRoom.Surface,
        camera: ARCamera,
        viewport: CGSize,
        orientation: UIInterfaceOrientation
    ) -> NormalizedRegion? {
        guard viewport.width > 1, viewport.height > 1,
              surface.dimensions.x > 0, surface.dimensions.y > 0 else { return nil }
        let halfWidth = surface.dimensions.x / 2
        let halfHeight = surface.dimensions.y / 2
        let localCorners = [
            SIMD4<Float>(-halfWidth, -halfHeight, 0, 1), SIMD4<Float>(halfWidth, -halfHeight, 0, 1),
            SIMD4<Float>(-halfWidth, halfHeight, 0, 1), SIMD4<Float>(halfWidth, halfHeight, 0, 1)
        ]
        let points = localCorners.map { corner -> CGPoint in
            let world = surface.transform * corner
            return camera.projectPoint(SIMD3(world.x, world.y, world.z), orientation: orientation, viewportSize: viewport)
        }
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let minimumX = max(0, points.map(\.x).min() ?? 0)
        let maximumX = min(viewport.width, points.map(\.x).max() ?? 0)
        let minimumY = max(0, points.map(\.y).min() ?? 0)
        let maximumY = min(viewport.height, points.map(\.y).max() ?? 0)
        let region = NormalizedRegion(
            x: Double(minimumX / viewport.width), y: Double(minimumY / viewport.height),
            width: Double((maximumX - minimumX) / viewport.width),
            height: Double((maximumY - minimumY) / viewport.height)
        )
        return NormalizedRegionAssociation.isValid(region) ? region : nil
    }

    private static func analysisOrientation(for orientation: UIInterfaceOrientation) -> AnalysisImageOrientation {
        switch orientation {
        case .landscapeLeft: .up
        case .landscapeRight: .down
        case .portraitUpsideDown: .left
        case .portrait, .unknown: .right
        @unknown default: .right
        }
    }
}
