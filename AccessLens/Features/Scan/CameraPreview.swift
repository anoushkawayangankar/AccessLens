@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// SwiftUI bridge for AVFoundation's native preview layer. The preview has no
/// accessibility content: ScanView provides the meaningful text status.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewView {
        CameraPreviewView(session: session)
    }

    func updateUIView(_ previewView: CameraPreviewView, context: Context) {
        previewView.session = session
    }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var session: AVCaptureSession? {
        didSet { previewLayer.session = session }
    }

    private var previewLayer: AVCaptureVideoPreviewLayer {
        guard let previewLayer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("CameraPreviewView requires AVCaptureVideoPreviewLayer.")
        }
        return previewLayer
    }

    init(session: AVCaptureSession) {
        self.session = session
        super.init(frame: .zero)
        previewLayer.videoGravity = .resizeAspectFill
        isAccessibilityElement = false
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
        updateVideoRotationIfSupported()
    }

    private func updateVideoRotationIfSupported() {
        guard let connection = previewLayer.connection,
              let interfaceOrientation = window?.windowScene?.interfaceOrientation else {
            return
        }

        let rotationAngle: CGFloat
        switch interfaceOrientation {
        case .portrait:
            rotationAngle = 90
        case .portraitUpsideDown:
            rotationAngle = 270
        case .landscapeLeft:
            rotationAngle = 180
        case .landscapeRight:
            rotationAngle = 0
        default:
            return
        }

        if connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
    }
}
