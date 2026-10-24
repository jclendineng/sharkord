import AVKit
import SwiftUI
import WebRTC

#if os(iOS)
// the call in picture in picture once the app goes to the background, showing the track it is
// given. it sits behind the call bar, the view the window animates from and back to
struct PictureInPictureSource: UIViewRepresentable {
    let track: VideoTrackBox?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()

        context.coordinator.attach(to: view)

        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.show(track?.track)
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private let content = AVPictureInPictureVideoCallViewController()
        private let videoView = SampleBufferVideoView()
        private var controller: AVPictureInPictureController?
        private var track: RTCVideoTrack?

        func attach(to view: UIView) {
            guard AVPictureInPictureController.isPictureInPictureSupported() else {
                return
            }

            videoView.frame = content.view.bounds
            videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            content.view.addSubview(videoView)
            content.preferredContentSize = CGSize(width: 9, height: 16)

            videoView.onAspectChange = { [weak content] size in
                content?.preferredContentSize = size
            }

            let source = AVPictureInPictureController.ContentSource(
                activeVideoCallSourceView: view,
                contentViewController: content
            )
            let controller = AVPictureInPictureController(contentSource: source)

            controller.canStartPictureInPictureAutomaticallyFromInline = false
            self.controller = controller
        }

        func show(_ newTrack: RTCVideoTrack?) {
            guard newTrack !== track else {
                return
            }

            if let track {
                track.remove(videoView.renderer)
            }

            track = newTrack

            if let newTrack {
                newTrack.add(videoView.renderer)
            }

            // nothing to show leaves the app going to the background as it always did
            controller?.canStartPictureInPictureAutomaticallyFromInline = newTrack != nil

            if newTrack == nil {
                controller?.stopPictureInPicture()
            }
        }

        func stop() {
            if let track {
                track.remove(videoView.renderer)
            }

            track = nil
            controller?.stopPictureInPicture()
            controller = nil
        }
    }
}

// a sample buffer layer turned by the frame's rotation, the only kind of view picture in
// picture draws from a call: webrtc's metal view stays blank in its window
final class SampleBufferVideoView: UIView {
    let renderer = SampleBufferRenderer()

    // the picture's shape once turned upright, which the window takes
    var onAspectChange: ((CGSize) -> Void)?

    private var rotation = RTCVideoRotation._0
    private var frameSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .black
        layer.addSublayer(renderer.displayLayer)
        renderer.onShapeChange = { [weak self] size, rotation in
            self?.apply(size: size, rotation: rotation)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let isSideways = rotation == ._90 || rotation == ._270
        let displayLayer = renderer.displayLayer

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.bounds = CGRect(
            origin: .zero,
            size: isSideways ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
        )
        displayLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        displayLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(rotation.rawValue) * .pi / 180))
        CATransaction.commit()
    }

    private func apply(size: CGSize, rotation: RTCVideoRotation) {
        let isSideways = rotation == ._90 || rotation == ._270
        let upright = isSideways ? CGSize(width: size.height, height: size.width) : size

        self.rotation = rotation
        setNeedsLayout()

        if upright != frameSize {
            frameSize = upright
            onAspectChange?(upright)
        }
    }
}

// frames arrive on webrtc's decoding thread, so this keeps off the main actor and hands only
// the picture's shape over to it
nonisolated final class SampleBufferRenderer: NSObject, RTCVideoRenderer, @unchecked Sendable {
    let displayLayer = AVSampleBufferDisplayLayer()

    var onShapeChange: (@MainActor (CGSize, RTCVideoRotation) -> Void)?

    private var lastSize = CGSize.zero
    private var lastRotation = RTCVideoRotation._0
    private var pool: CVPixelBufferPool?
    private var poolSize = CGSize.zero

    override init() {
        super.init()

        displayLayer.videoGravity = .resizeAspect
    }

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame, let pixelBuffer = pixelBuffer(of: frame.buffer), let sample = Self.sample(with: pixelBuffer) else {
            return
        }

        let renderer = displayLayer.sampleBufferRenderer

        if renderer.status == .failed {
            renderer.flush()
        }

        renderer.enqueue(sample)

        let size = CGSize(width: Int(frame.width), height: Int(frame.height))

        if size != lastSize || frame.rotation != lastRotation {
            lastSize = size
            lastRotation = frame.rotation

            let rotation = frame.rotation
            let onShapeChange = onShapeChange

            DispatchQueue.main.async {
                onShapeChange?(size, rotation)
            }
        }
    }

    // the phone's hardware decoder hands over a pixel buffer as it is, vp8's software one
    // planes that are copied into one
    private func pixelBuffer(of buffer: RTCVideoFrameBuffer) -> CVPixelBuffer? {
        if let buffer = buffer as? RTCCVPixelBuffer {
            return buffer.pixelBuffer
        }

        return copy(buffer.toI420())
    }

    private func copy(_ i420: RTCI420BufferProtocol) -> CVPixelBuffer? {
        let width = Int(i420.width)
        let height = Int(i420.height)

        guard let pool = pool(width: width, height: height) else {
            return nil
        }

        var output: CVPixelBuffer?

        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output) == kCVReturnSuccess, let output else {
            return nil
        }

        CVPixelBufferLockBaseAddress(output, [])

        defer {
            CVPixelBufferUnlockBaseAddress(output, [])
        }

        guard
            let lumaBase = CVPixelBufferGetBaseAddressOfPlane(output, 0),
            let chromaBase = CVPixelBufferGetBaseAddressOfPlane(output, 1)
        else {
            return nil
        }

        let luma = lumaBase.assumingMemoryBound(to: UInt8.self)
        let chroma = chromaBase.assumingMemoryBound(to: UInt8.self)
        let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(output, 0)
        let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(output, 1)

        for row in 0..<height {
            memcpy(luma + row * lumaStride, i420.dataY + row * Int(i420.strideY), width)
        }

        let chromaWidth = (width + 1) / 2

        for row in 0..<(height + 1) / 2 {
            let u = i420.dataU + row * Int(i420.strideU)
            let v = i420.dataV + row * Int(i420.strideV)
            let line = chroma + row * chromaStride

            for column in 0..<chromaWidth {
                line[column * 2] = u[column]
                line[column * 2 + 1] = v[column]
            }
        }

        return output
    }

    private func pool(width: Int, height: Int) -> CVPixelBufferPool? {
        let size = CGSize(width: width, height: height)

        if let pool, poolSize == size {
            return pool
        }

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        var created: CVPixelBufferPool?

        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &created)
        pool = created
        poolSize = size

        return created
    }

    // shown the moment it arrives, a call has no timeline to place it on
    private static func sample(with pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?

        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &format)

        guard let format else {
            return nil
        }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?

        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil,
            imageBuffer: pixelBuffer,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sample
        )

        guard let sample else {
            return nil
        }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary] {
            attachments.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
        }

        return sample
    }
}
#endif
