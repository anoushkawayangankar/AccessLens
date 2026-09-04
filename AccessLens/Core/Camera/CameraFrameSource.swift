@preconcurrency import AVFoundation

/// A deliberately narrow handoff point for a future bounded analysis
/// scheduler. The delegate runs on the video-output queue and must release
/// sample buffers promptly; this milestone registers no consumer.
nonisolated protocol CameraFrameConsumer: AnyObject {
    func cameraFrameSource(_ source: CameraFrameSource, didOutput sampleBuffer: CMSampleBuffer)
}

nonisolated final class CameraFrameSource {
    weak var consumer: (any CameraFrameConsumer)?

    func deliver(_ sampleBuffer: CMSampleBuffer) {
        consumer?.cameraFrameSource(self, didOutput: sampleBuffer)
    }
}
