@preconcurrency import AVFoundation

/// A deliberately narrow handoff point for a future bounded analysis
/// scheduler. The delegate runs on the video-output queue and must release
/// sample buffers promptly; this milestone registers no consumer.
nonisolated protocol CameraFrameConsumer: AnyObject {
    func cameraFrameSource(
        _ source: CameraFrameSource,
        didOutput sampleBuffer: CMSampleBuffer,
        videoRotationAngle: Double,
        isMirrored: Bool
    )
}

nonisolated final class CameraFrameSource {
    weak var consumer: (any CameraFrameConsumer)?

    func deliver(
        _ sampleBuffer: CMSampleBuffer,
        videoRotationAngle: Double,
        isMirrored: Bool
    ) {
        consumer?.cameraFrameSource(
            self,
            didOutput: sampleBuffer,
            videoRotationAngle: videoRotationAngle,
            isMirrored: isMirrored
        )
    }
}
