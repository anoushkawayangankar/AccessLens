import RoomPlan
import SwiftUI

struct RoomPlanCapturePreview: UIViewRepresentable {
    let captureView: RoomCaptureView
    let updateViewport: (CGSize, UIInterfaceOrientation) -> Void

    func makeUIView(context: Context) -> RoomCaptureView {
        captureView
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {
        let orientation = uiView.window?.windowScene?.interfaceOrientation ?? .portrait
        updateViewport(uiView.bounds.size, orientation)
    }
}
